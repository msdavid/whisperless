"""Text insertion helpers for the whisperless client (MIT).

ime_commit(): insert text as a Wayland input method (zwp_input_method_v2).
wait_modifiers_released(): hold key typers back while a modifier is down.
"""
import fcntl
import os
import re
import select
import socket
import struct
import time
from pathlib import Path

# The text reaches the focused field as one committed string, not as synthesized
# keypresses, so modifiers held on any keyboard can't turn letters into shortcuts
# (CTRL+M = Enter) and no keystrokes can be dropped. Needs a compositor with
# input-method-v2 (wlroots-based, Hyprland) and an app with text-input-v3 enabled
# (GTK, Qt, Chromium, most terminals); anything else falls back to the key typers.

class _Wayland:
    """Bare Wayland wire-protocol client: just what ime_commit needs."""
    def __init__(self):
        path = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
        if not path.startswith("/"):
            path = os.path.join(os.environ["XDG_RUNTIME_DIR"], path)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.buf = b""
        self.last_id = 1  # 1 = wl_display

    def new_id(self):
        self.last_id += 1
        return self.last_id

    def send(self, obj, opcode, *args):
        body = b""
        for a in args:
            if isinstance(a, str):
                b = a.encode() + b"\0"
                body += struct.pack("=I", len(b)) + b + b"\0" * (-len(b) % 4)
            else:
                body += struct.pack("=I", a)
        self.sock.sendall(struct.pack("=II", obj, (8 + len(body)) << 16 | opcode) + body)

    def events(self, timeout):
        """Yield (object, opcode, payload); stop after timeout without data.
        A wl_display.error is fatal to the connection: raise it."""
        end = time.monotonic() + timeout
        while True:
            while len(self.buf) >= 8:
                obj, word = struct.unpack_from("=II", self.buf)
                size = word >> 16
                if len(self.buf) < size:
                    break
                payload, self.buf = self.buf[8:size], self.buf[size:]
                if obj == 1 and word & 0xFFFF == 0:
                    raise ConnectionError("wayland protocol error")
                yield obj, word & 0xFFFF, payload
            left = end - time.monotonic()
            if left <= 0 or not select.select([self.sock], [], [], left)[0]:
                return
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("wayland socket closed")
            self.buf += chunk

    def roundtrip(self, on_event=None):
        """wl_display.sync and wait for its reply; other events go to on_event."""
        cb = self.new_id()
        self.send(1, 0, cb)
        for obj, op, payload in self.events(2):
            if obj == cb:
                return True
            if on_event:
                on_event(obj, op, payload)
        return False

def ime_commit(text, wait=0.3):
    """Commit text to the focused field; False if no input method can reach it
    (no Wayland, no protocol, another input method owns the seat, or the focused
    app doesn't activate text input within `wait` seconds)."""
    try:
        wl = _Wayland()
    except (OSError, KeyError):
        return False
    try:
        reg = wl.new_id()
        wl.send(1, 1, reg)  # wl_display.get_registry
        names = {}

        def on_global(obj, op, p):  # wl_registry.global(name, interface, version)
            if obj == reg and op == 0:
                n = struct.unpack_from("=I", p, 4)[0]
                names[p[8:8 + n - 1].decode()] = struct.unpack_from("=I", p)[0]

        wl.roundtrip(on_global)
        if "wl_seat" not in names or "zwp_input_method_manager_v2" not in names:
            return False
        seat, mgr, im = wl.new_id(), wl.new_id(), wl.new_id()
        wl.send(reg, 0, names["wl_seat"], "wl_seat", 1, seat)  # wl_registry.bind
        wl.send(reg, 0, names["zwp_input_method_manager_v2"], "zwp_input_method_manager_v2", 1, mgr)
        wl.send(mgr, 0, seat, im)  # get_input_method
        # input-method state is double-buffered: activate/deactivate apply on done,
        # and commit must echo the number of done events seen so far
        serial, pending, active = 0, False, False
        for obj, op, _ in wl.events(wait):
            if obj != im:
                continue
            if op in (0, 1):  # activate / deactivate
                pending = op == 0
            elif op == 5:  # done
                serial += 1
                active = pending
                if active:
                    break
            elif op == 6:  # unavailable: another input method is bound
                return False
        if not active:
            return False
        data = text.encode()
        while data:  # commit_string is capped at 4000 bytes; split on char boundaries
            n = min(len(data), 3000)
            while n < len(data) and data[n] & 0xC0 == 0x80:
                n -= 1
            wl.send(im, 0, data[:n].decode())  # commit_string
            wl.send(im, 3, serial)  # commit
            data = data[n:]
        ok = wl.roundtrip()
        wl.send(im, 6)  # destroy
        return ok
    except OSError:
        return False
    finally:
        wl.sock.close()

# Key typers inject into the same keyboard state the user's hands use: a still-held
# hotkey modifier turns typed letters into shortcuts. Wait until none is down.
_MODIFIER_KEYS = (29, 97, 42, 54, 56, 100, 125, 126)  # L/R ctrl, shift, alt, meta
_EVIOCGKEY = 0x80000000 | 96 << 16 | ord("E") << 8 | 0x18  # 96 bytes = KEY_MAX bits

def _keyboard_devices():
    """event nodes whose key capabilities include left CTRL (real keyboards),
    from /proc/bus/input/devices; opening every input node is slow."""
    devs = []
    try:
        blocks = Path("/proc/bus/input/devices").read_text().split("\n\n")
    except OSError:
        return devs
    for block in blocks:
        ev = re.search(r"^H: Handlers=.*\b(event\d+)", block, re.M)
        keys = re.search(r"^B: KEY=([0-9a-f ]+)$", block, re.M)
        if not ev or not keys:
            continue
        # least significant word is last; bit 29 (KEY_LEFTCTRL) is in it on 32- and 64-bit
        if int(keys.group(1).split()[-1], 16) >> 29 & 1:
            devs.append("/dev/input/" + ev.group(1))
    return devs

def wait_modifiers_released(timeout=2.0):
    """Block until no keyboard reports a held modifier, up to timeout; False if
    one is still held then. Needs read access to /dev/input (the `input` group);
    unreadable devices are skipped."""
    fds = []
    for dev in _keyboard_devices():
        try:
            fds.append(os.open(dev, os.O_RDONLY | os.O_NONBLOCK))
        except OSError:
            pass
    def modifier_down(fd):
        try:
            state = fcntl.ioctl(fd, _EVIOCGKEY, bytes(96))
        except OSError:  # device unplugged meanwhile
            return False
        return any(state[k // 8] >> (k % 8) & 1 for k in _MODIFIER_KEYS)

    try:
        end = time.monotonic() + timeout
        while any(modifier_down(fd) for fd in fds):
            if time.monotonic() >= end:
                return False
            time.sleep(0.02)
        return True
    finally:
        for fd in fds:
            os.close(fd)
