# whisperless — R2T2 voice input for Linux desktops

![License: MIT](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux%20(Wayland%20%7C%20X11)-blue)
![Python](https://img.shields.io/badge/python-3.12-blue)
![GPU](https://img.shields.io/badge/GPU-NVIDIA%20CUDA-76b900)
![Cloud](https://img.shields.io/badge/cloud-none%20%2F%20100%25%20local-brightgreen)
![ASR](https://img.shields.io/badge/ASR-Confucius4--R2T2-orange)

Push-to-talk dictation for Hyprland, sway, i3 and other Linux desktops using
[Confucius4-R2T2](https://github.com/netease-youdao/Confucius4-R2T2)
streaming ASR. Press a hotkey, speak, press again — the text (with punctuation)
is typed into whatever window has focus.

```
CTRL+space ──▶ 🎤 speak ──▶ CTRL+space ──▶ "What time is it? It works." typed into focus
```

## Why whisperless?

- **Runs 100% locally.** The model lives on your own GPU — no cloud APIs, no
  accounts, no API keys, no telemetry. Audio never leaves the machine, and it
  keeps working with the network unplugged (the installer downloads open model
  weights once, everything after that is offline).
- **Really fast.** The server stays warm in memory (vLLM), so dictation starts
  the instant you press the key, streams at ~0.5s chunk latency while you
  talk, and the punctuated text lands in your window ~1-1.5s after you press
  stop. No round-trips to a datacenter, ever.
- **Open source.** MIT-licensed client and installer; the bundled server
  changes are Apache-2.0 with every modification documented (`server/NOTICE`).
  No paid tiers, nothing phoning home.

> 🤖 LLM agent? Read [`llms.txt`](llms.txt) instead — the whole project as a dense machine-readable reference.

## Contents

[How it works](#how-it-works) · [Requirements](#requirements) ·
[Install](#install) · [Configure](#configure) ·
[Window manager support](#window-manager-support) · [Use](#use) ·
[Files](#files) · [Troubleshooting](#operations--troubleshooting) ·
[Updating](#updating) · [Server patches](#server-patches-why-and-what-to-redo-after-upstream-updates) ·
[Acknowledgments](#acknowledgments) · [License](#license)

## How it works

```
whisperless.service (systemd user, always warm)     ~/.local/bin/whisperless
  Confucius4-R2T2 ws_server.py               pw-record 16 kHz s16 → WS frames →
  vLLM on your GPU, ~8-9GB VRAM              ws://127.0.0.1:8272/asr_stream_api_v1
  boots in ~2 min, latency ~0.5s/chunk       → collects incremental text → wtype
```

Two moving parts: their **server** (unmodified except the patches below, kept warm
by systemd so dictation starts instantly) and a small **Python client** that captures
the mic (`pw-record`, or `arecord` on non-PipeWire systems), streams it to the server
over a WebSocket, and types the final transcript (`wtype` on Wayland, `ydotool`/
`xdotool` fallbacks — see "Window manager support"). At stop, the server re-decodes
the whole utterance offline — that's what gives you terminal punctuation (streaming
mode never emits it).

## Requirements

- Linux with a Wayland compositor or X11 session, systemd user session
- Text injector: `wtype` (Wayland) or `ydotool` or `xdotool` (X11) — at least one;
  the installer installs `wtype` if none is present
- Mic capture: PipeWire (`pw-record`) or ALSA (`arecord`)
- NVIDIA GPU: ≥6GB free VRAM (a 16GB card shares comfortably with a desktop)
- Network for the one-time setup (~15GB: wheels + model weights)
- Non-NVIDIA GPUs are untested; the vLLM backend requires CUDA

## Install

```bash
git clone <this-repo-or-copy> whisperless && cd whisperless
./install.sh
```

That's it — safe on a fresh machine. The installer is **idempotent** (re-run anytime;
it re-applies server files and the unit, but keeps your config, venv and weights) and
handles everything:

| Step | What happens |
|------|--------------|
| S1 (Preflight) | Installs missing system deps (`git curl libnotify`, a text injector, a mic recorder) via pacman/apt/dnf, checks the NVIDIA driver, bootstraps `uv` |
| S2 (Config) | Installs `~/.config/whisperless/config.conf` from `whisperless.conf` (never overwrites an existing one). **Asks for the install destination and hotkey** — press Enter to keep the defaults; your answers are written back to the config |
| S3 (Server Setup) | Clones R2T2 to `~/apps/r2t2/Confucius4-R2T2`, creates a uv venv with Python 3.12, installs the package (vLLM backend) |
| S4 (Server files) | Copies the patched `server/ws_server.py` over the clone |
| S5 (Models) | Downloads the ASR model (~4GB) + Stream-VAD (~2MB); resumes if partial |
| S6 (Client) | Installs `whisperless` to `~/.local/bin` (shebang pointed at the venv) |
| S7 (Service) | Renders `whisperless.service` from config, enables + starts it, waits for warmup |
| S8 (Smoke test) | Streams the repo's sample WAV through the whole pipeline and prints the transcript |
| S9 (Hotkey) | Detects the window manager and writes the bind: Hyprland (`hyprland.lua`/`.conf`), sway/i3 (`bindsym $mod+k exec whisperless`) — anything else prints exact binding instructions. Reloads the compositor config |

Flags: `SKIP_MODELS=1 ./install.sh` (weights already present), `SKIP_SMOKE=1 ./install.sh`.

**First boot takes 1-2 minutes** (CUDA graph capture); later restarts ~30s. The
service auto-restarts on failure and starts at login.

## Configure

Everything lives in `~/.config/whisperless/config.conf` (shell-style `KEY=value`):

```bash
SERVER_DIR="$HOME/apps/r2t2/Confucius4-R2T2"  # checkout; venv + models live here
PORT=8272                  # server websocket port
BIND_IP=127.0.0.1          # keep loopback unless serving other machines
GPU_INDEX=0                # CUDA device for the server
GPU_MEM_UTIL=0.55          # vLLM memory budget (lower it if other GPU apps need room)
MAX_MODEL_LEN=8192         # KV cache context cap (raises vLLM VRAM reservation)
HOTKEY="CTRL + space"      # keybind (lua syntax; converted automatically for sway/i3/.conf)
VOICE_LANG=English         # English | Chinese | zhen (auto zh+en) | other supported languages
MAX_SECS=120               # auto-finalize dictation after N seconds
SETTLE_DELAY=0.15          # pause before typing; prevents WM shortcut races
GRACE_TAIL=0.25            # extra capture after stop so the last word isn't clipped
TRAILING_SPACE=1           # append a space after inserted text
NOTIFY=1                   # desktop notifications (0 = silent)
MIC_TARGET=                # pw-record --target; empty = default source (wpctl status)
TYPER=auto                 # text injection: auto | wtype | ydotool | xdotool
WM=auto                    # bind target: auto | hyprland | sway | i3 | other
BORDER=1                   # Hyprland: focused-window border turns red while recording
BORDER_COLOR="rgba(ff3333ff)"          # active border while recording
BORDER_INACTIVE_COLOR="rgba(ff333355)" # inactive borders while recording
```

Client-side values (`VOICE_LANG`…`BORDER_INACTIVE_COLOR`) apply on the next
dictation. Server-side values (`PORT`, `GPU_*`) need `./install.sh` re-run (it
re-renders the unit and restarts the service).

To change the **hotkey or install destination**, just re-run `./install.sh` — it asks
again (Enter keeps the current value) and re-binds. Non-interactive installs (no TTY)
skip the prompts and use the configured values; pass `HOTKEY="SUPER + I"` to override
in scripts.

Mic tips: `wpctl status` lists sources; set `MIC_TARGET=<node id>` to pick one
(only applies to `pw-record`; `arecord` uses the ALSA default device).

## Window manager support

The server and client are compositor-agnostic; only the hotkey binding is WM-specific:

| WM / desktop | Bind written by installer | Config reload |
|---|---|---|
| Hyprland | `hyprland.lua` (lua) or `hyprland.conf` | `hyprctl reload` |
| sway | `bindsym $mod+k exec whisperless` in `~/.config/sway/config` | `swaymsg reload` |
| i3 | `bindsym $mod+k exec whisperless` in `~/.config/i3/config` | `i3-msg reload` |
| anything else | printed instructions (GNOME/KDE shortcuts, X11 WM keymaps) | — |

Detection order: `WM=` config override → `hyprctl`/`swaymsg`/`i3-msg` presence →
`$XDG_CURRENT_DESKTOP`.

**Text injection chain** (client, first that succeeds wins — `TYPER=` pins one):

- Wayland session: `wtype` → `ydotool` (needs a running `ydotoold` daemon)
- X11 session: `ydotool` → `xdotool` (`--clearmodifiers`, which also guards
  against stuck modifiers on X11)

**Mic capture chain:** `pw-record` (PipeWire) → `arecord` (ALSA). `MIC_TARGET`
selects the PipeWire source; `MIC_TARGET=60`-style ids don't map to ALSA devices.

## Use

1. Focus any text field
2. Press `CTRL+space` → notification confirms recording, the focused window's
   border turns red (Hyprland, `BORDER=1`)
3. Speak
4. Press `CTRL+space` again → the punctuated transcript is typed, the border
   restores, a notification shows the text

Recording auto-stops after `MAX_SECS`. Rapid double-presses are safe (toggle uses a
pidfile + signals, not press/release binds). The stop keeps capturing a short grace
tail and drains buffered mic audio before finalizing, so trailing words survive.

**Replacing hyprvoice:** on Hyprland the installer removes any `hyprvoice-toggle`
bind it finds (that's the migration path from the old whisperx flow — `CTRL+space`
now runs whisperless). The hyprvoice scripts themselves are left on disk but unbound.

Border feedback reads the current border colors at recording start and restores them
at the end (exact for single-color 0° gradients; multi-stop gradients degrade to
their first stop, logged). `BORDER=0` disables it. On non-Hyprland compositors the
border feature is silently skipped.

## Files

| Path | Role |
|------|------|
| `install.sh` / `uninstall.sh` | idempotent installer / uninstaller (`--purge` deletes models too) |
| `whisperless.conf` | documented default config (source of the installed config) |
| `whisperless` | client source (installer installs it with a venv shebang) |
| `whisperless.service` | systemd user unit template (rendered from config at install) |
| `server/ws_server.py` | canonical patched server, copied over the upstream clone |
| `offline_probe.py` | diagnostic: offline decode of a wav on the same engine |
| `llms.txt` | machine-readable project reference for LLM agents (dense; not for humans) |

Runtime paths: `~/apps/r2t2/Confucius4-R2T2/` (checkout, `.venv`, `models/`,
`checkpoints/vad/`), `~/.config/systemd/user/whisperless.service`,
`~/.config/whisperless/config.conf`, `~/.local/bin/whisperless`,
`~/.cache/whisperless.log` (client log).

## Operations & troubleshooting

```bash
systemctl --user status r2t2          # server health
journalctl --user -u r2t2 -f          # server logs (includes per-chunk latency)
tail -f ~/.cache/whisperless.log      # client log (transcript chunks, errors+tracebacks)
~/.local/bin/whisperless --test f.wav # 16 kHz mono s16 wav through the pipeline
systemctl --user restart r2t2         # after changing server-side config or weights
```

- **"whisperless failed" with empty text** → check `~/.cache/whisperless.log`; errors
  log the exception type + traceback.
- **"no text injector found"** → install `wtype` (Wayland) or `ydotool`/`xdotool`, or
  set `TYPER=` explicitly; the client logs which backend it used for every insert.
- **sway/i3 modifier caveats** → the installer lowercases the hotkey (`SUPER + K` →
  `$mod+k`); if your compose needs exact case (e.g. `Shift`), edit the `bindsym` line
  manually.
- **Shortcut keys firing while typing** → the `SETTLE_DELAY` guard; increase it.
- **Last word missing** → increase `GRACE_TAIL`.
- **Terminal punctuation missing** → make sure you're running the patched server
  (`./install.sh` re-applies it); plain upstream streaming never emits it.
- **Server won't start, KV cache error** → lower `GPU_MEM_UTIL` *and* `MAX_MODEL_LEN`,
  then re-run `./install.sh`.
- **vLLM + Blackwell (RTX 50xx)** → needs the repo's current vLLM (≥0.8.5); the
  installer installs whatever `pyproject.toml` resolves today (tested with 0.14.0).

## Updating

Upstream changes are not pulled automatically. To update:

```bash
cd ~/apps/r2t2/Confucius4-R2T2 && git pull        # bring in upstream changes
./install.sh                                       # re-applies patches + restarts
```

Re-verify the patches still apply cleanly — see below, and re-check the diff against
the package's `server/ws_server.py`.

## Server patches (why, and what to redo after upstream updates)

`server/ws_server.py` in this package is the source of truth; the installer copies it
over the clone. Applied changes (also marked `# patched` inline):

1. **Engine init** — `GPU_MEM_UTIL`/`MAX_MODEL_LEN` read from env (upstream
   hardcodes `0.95` and 64k context: on a 16GB GPU shared with a desktop that fails
   KV-cache allocation at boot), `max_new_tokens=1024` (upstream 1 — breaks the
   offline finalize's decode budget), `max_num_batched_tokens=2048`.
2. **EOS finalize** — the streaming finish never emits terminal punctuation (LSP
   append-only design; upstream's own `example.py` behaves the same). At EOS the
   endpoint re-decodes the full utterance offline via `transcribe()` and returns the
   complete punctuated transcript as the final `reset:True` message (falls back to
   the streaming finish on error).
3. **Unit environment** — `PYTHONUNBUFFERED=1` (their debug prints are otherwise
   swallowed by journal buffering).

Client consequence: `reset:True` messages replace the accumulated text.

## Acknowledgments

- [Confucius4-R2T2](https://github.com/netease-youdao/Confucius4-R2T2) — NetEase
  Youdao's streaming ASR model and its WebSocket server (Apache-2.0)
- [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) — the architecture it builds on
- [FireRedVAD](https://huggingface.co/FireRedTeam/FireRedVAD) — streaming VAD
- The old hyprvoice flow that motivated this rewrite

## License

| Part | License | Notes |
|------|---------|-------|
| This repository (client, installer, docs) | [MIT](LICENSE) | |
| `server/ws_server.py` (bundled upstream file, modified) | [Apache-2.0](server/LICENSE) | changes documented in [`server/NOTICE`](server/NOTICE) |
| Confucius4-R2T2 model weights | [NetEase Model Use License](https://github.com/netease-youdao/Confucius4-R2T2/blob/master/MODEL_LICENSE) | **not open source**, not redistributed — downloaded at install; fine for personal use, review before commercial use |