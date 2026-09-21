#!/usr/bin/env bash
# whisperless installer — R2T2 push-to-talk dictation for Hyprland/sway/i3/X11.
#
# Designed for a fresh machine: installs system deps, uv + Python 3.12, the
# R2T2 checkout with venv, model weights, the patched server (systemd user
# service), the client and the hotkey. Idempotent — safe to re-run; existing
# artifacts are reused, server files are always refreshed from this package.
#
# Interactive: asks for the hotkey and install destination (Enter keeps the
# configured/current value). Non-interactive runs (no TTY) use the config;
# pass HOTKEY="SUPER + I" to override non-interactively.
#
# Window managers: binds are written for Hyprland, sway and i3; anything else
# gets printed instructions (the client itself is compositor-agnostic via
# wtype/ydotool/xdotool).
#
# Configuration: ~/.config/whisperless/config.conf (installed from
# whisperless.conf on first run). Edit + re-run install.sh to apply
# server-side values; client values are read live per dictation.
#
# Env flags:  SKIP_MODELS=1 (keep weights), SKIP_SMOKE=1 (skip wav smoke test)
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$HOME/.config/whisperless"
REPO_URL="https://github.com/netease-youdao/Confucius4-R2T2"

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'EOF'
whisperless installer — R2T2 push-to-talk dictation for Linux desktops

Usage: ./install.sh

Installs and configures everything for a fresh machine: system deps, uv +
Python 3.12, the R2T2 checkout + venv, model weights, patched GPU server
(systemd user service), the whisperless client and your hotkey. Idempotent.

Interactive prompts: install destination and hotkey (Enter keeps default).

Environment flags:
  SKIP_MODELS=1     skip model download (weights already present)
  SKIP_SMOKE=1      skip the end-to-end WAV smoke test
  HOTKEY="..."      pre-answer the hotkey prompt (non-interactive installs)

Configuration: ~/.config/whisperless/config.conf
  (installed from whisperless.conf; edit + re-run to apply server changes)

Uninstall: ./uninstall.sh          (add --purge to delete venv + models)
Docs:      README.md
EOF
  exit 0
fi

# ---------------------------------------------------------------- helpers
have() { command -v "$1" >/dev/null 2>&1; }

# FILE KEY VALUE — set KEY="VALUE", preserving any trailing comment
set_key() {
  local f="$1" key="$2" val="$3"
  if grep -qE "^${key}=" "$f"; then
    sed -i -E 's|^('"${key}"'=)"[^"]*"(.*)$|\1"'"${val}"'"\2|' "$f"
    grep -qF "${key}=\"${val}\"" "$f" || \
      sed -i -E 's|^('"${key}"'=).*$|\1"'"${val}"'"|' "$f"
  else
    [ -n "$(tail -c1 "$f")" ] && printf '\n' >> "$f"   # ensure trailing newline
    printf '%s="%s"\n' "$key" "$val" >> "$f"
  fi
}

ask() {  # ask PROMPT DEFAULT -> $__ASK (does not write config)
  printf '%s [%s]: ' "$1" "$2"
  read -r ans || ans=""
  ans="${ans//\"/}"
  ans="${ans//\\//}"
  __ASK="${ans:-$2}"
}

# ------------------------------------------------------- S1 (Preflight)
step "S1 (Preflight): checking system dependencies"

pkgmap() {  # binary -> distro package name
  case "$1:$2" in
    pw-record:pacman) echo pipewire-audio ;;
    pw-record:apt)    echo pipewire-bin ;;
    pw-record:dnf)    echo pipewire-utils ;;
    notify-send:apt)  echo libnotify-bin ;;
    *)                echo "$1" ;;
  esac
}

missing=()
for t in git curl notify-send; do
  have "$t" || missing+=("$t")
done
have wtype || have ydotool || have xdotool || missing+=("wtype")   # text injection
have pw-record || have arecord || missing+=("pw-record")           # mic capture
if [ ${#missing[@]} -gt 0 ]; then
  info "installing missing system packages: ${missing[*]}"
  if have pacman; then M=pacman
  elif have apt-get; then M=apt
  elif have dnf; then M=dnf
  else die "no pacman/apt/dnf found — install manually, then re-run: ${missing[*]}"
  fi
  pkgs=()
  for t in "${missing[@]}"; do pkgs+=("$(pkgmap "$t" "$M")"); done
  if [ "$M" = pacman ]; then sudo pacman -S --needed "${pkgs[@]}"
  elif [ "$M" = apt ]; then sudo apt-get update -qq && sudo apt-get install -y "${pkgs[@]}"
  else sudo dnf install -y "${pkgs[@]}"; fi
fi
for t in git curl notify-send; do
  have "$t" || die "missing after install: $t (install it manually, then re-run)"
done
have wtype || have ydotool || have xdotool || die "no text injector found (wtype/ydotool/xdotool)"
have pw-record || have arecord || die "no mic recorder found (pw-record/arecord)"
have nvidia-smi || die "nvidia-smi not found — this package needs an NVIDIA GPU + driver"

if ! have uv; then
  step "S1 (Preflight): installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
have uv || die "uv not found after install"

# ------------------------------------------------------- S2 (Config)
step "S2 (Config): whisperless configuration"
# Migration from the 0.1.0 hypr-input layout
if [ -d "$HOME/.config/hypr-input" ] && [ ! -d "$CONF_DIR" ]; then
  mv "$HOME/.config/hypr-input" "$CONF_DIR"
  info "migrated config: ~/.config/hypr-input -> ~/.config/whisperless"
fi
mkdir -p "$CONF_DIR"
if [ ! -f "$CONF_DIR/config.conf" ]; then
  cp "$PKG_DIR/whisperless.conf" "$CONF_DIR/config.conf"
  info "installed $CONF_DIR/config.conf (defaults)"
else
  info "keeping existing $CONF_DIR/config.conf"
fi
ENV_HOTKEY="${HOTKEY:-}"   # explicit env override survives the config source
# shellcheck disable=SC1091
source "$CONF_DIR/config.conf"
# Merge options added by newer package versions into older configs
while IFS= read -r key; do
  if ! grep -qE "^${key}=" "$CONF_DIR/config.conf"; then
    [ -n "$(tail -c1 "$CONF_DIR/config.conf")" ] && printf '\n' >> "$CONF_DIR/config.conf"
    grep -E "^${key}=" "$PKG_DIR/whisperless.conf" | head -1 >> "$CONF_DIR/config.conf"
    info "added new option: $key"
  fi
done < <(grep -oE '^[A-Z_]+=' "$PKG_DIR/whisperless.conf" | tr -d '=')
# Defaults for keys missing from very old configs
HOTKEY="${HOTKEY:-SUPER + K}"; SERVER_DIR="${SERVER_DIR:-$HOME/apps/r2t2/Confucius4-R2T2}"
HOTKEY="${ENV_HOTKEY:-$HOTKEY}"   # env override wins over config
PORT="${PORT:-8272}"; BIND_IP="${BIND_IP:-127.0.0.1}"; GPU_INDEX="${GPU_INDEX:-0}"
GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.55}"; MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
WM="${WM:-auto}"
[[ "$PORT" =~ ^[0-9]+$ ]] || die "PORT must be numeric in $CONF_DIR/config.conf"
case "$SERVER_DIR" in "$HOME"/*) ;; *) die "SERVER_DIR must be under \$HOME" ;; esac

# Installation destination: asked at install time (Enter keeps configured value)
if [ -t 0 ]; then
  ask "Install destination (R2T2 checkout; venv + models live here)" "$SERVER_DIR"
  SERVER_DIR="$__ASK"
fi
SERVER_DIR="${SERVER_DIR%/}"
case "$SERVER_DIR" in "$HOME"/*) ;; *) die "destination must be under \$HOME" ;; esac

# Hotkey: asked at install time (Enter keeps configured value)
if [ -z "$ENV_HOTKEY" ] && [ -t 0 ]; then
  ask "Hotkey to toggle dictation" "$HOTKEY"
  HOTKEY="$__ASK"
fi
if [ -n "$ENV_HOTKEY" ] || [ -t 0 ]; then
  set_key "$CONF_DIR/config.conf" HOTKEY "$HOTKEY"      # persist the choice
  set_key "$CONF_DIR/config.conf" SERVER_DIR "$SERVER_DIR"
fi

# ------------------------------------------------------- S3 (Server checkout)
step "S3 (Server Setup): R2T2 checkout + venv"
if [ ! -d "$SERVER_DIR/.git" ]; then
  mkdir -p "$(dirname "$SERVER_DIR")"
  git clone --depth 1 "$REPO_URL" "$SERVER_DIR"
else
  info "checkout exists: $SERVER_DIR (left as-is; see README 'Updating')"
fi
if [ ! -x "$SERVER_DIR/.venv/bin/python" ] || \
   ! "$SERVER_DIR/.venv/bin/python" -c "import r2t2" >/dev/null 2>&1; then
  (cd "$SERVER_DIR" && uv venv --python 3.12 .venv && uv pip install --python .venv/bin/python -e .)
else
  info "venv OK (skipping install)"
fi

# ------------------------------------------------------- S4 (Server files)
step "S4 (Server files): patched ws_server.py"
cp "$PKG_DIR/server/ws_server.py" "$SERVER_DIR/ws_server.py"
info "patched server installed (see README 'Server patches')"

# ------------------------------------------------------- S5 (Models)
if [ "${SKIP_MODELS:-0}" != 1 ]; then
  step "S5 (Models): downloading weights (ASR ~4GB + VAD ~2MB; resumes if partial)"
  HF_CLI="$SERVER_DIR/.venv/bin/hf"
  [ -x "$HF_CLI" ] || HF_CLI="$SERVER_DIR/.venv/bin/huggingface-cli"
  mkdir -p "$SERVER_DIR/models" "$SERVER_DIR/checkpoints/vad"
  "$HF_CLI" download netease-youdao/Confucius4-R2T2 --local-dir "$SERVER_DIR/models/Confucius4-R2T2"
  "$HF_CLI" download FireRedTeam/FireRedVAD --include "Stream-VAD/*" --local-dir "$SERVER_DIR/checkpoints/vad"
else
  step "S5 (Models): skipped (SKIP_MODELS=1)"
fi

# ------------------------------------------------------- S6 (Client)
step "S6 (Client): whisperless"
mkdir -p "$HOME/.local/bin"
{ echo "#!$SERVER_DIR/.venv/bin/python"; tail -n +2 "$PKG_DIR/whisperless"; } \
  > "$HOME/.local/bin/whisperless"
chmod +x "$HOME/.local/bin/whisperless"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) info "note: $HOME/.local/bin is not in PATH" ;; esac

# ------------------------------------------------------- S7 (Service)
step "S7 (Service): whisperless.service (systemd user unit)"
if [ -f "$HOME/.config/systemd/user/r2t2.service" ]; then
  systemctl --user disable --now r2t2.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/r2t2.service"
  info "migrated legacy r2t2.service -> whisperless.service"
fi
mkdir -p "$HOME/.config/systemd/user"
UNIT_DIR="%h${SERVER_DIR#"$HOME"}"
sed -e "s|@SERVER_DIR@|$UNIT_DIR|g" \
    -e "s|@BIND_IP@|$BIND_IP|g" \
    -e "s|@PORT@|$PORT|g" \
    -e "s|@GPU_INDEX@|$GPU_INDEX|g" \
    -e "s|@GPU_MEM_UTIL@|$GPU_MEM_UTIL|g" \
    -e "s|@MAX_MODEL_LEN@|$MAX_MODEL_LEN|g" \
    "$PKG_DIR/whisperless.service" > "$HOME/.config/systemd/user/whisperless.service"
systemctl --user daemon-reload
systemctl --user enable --now whisperless.service
systemctl --user restart whisperless.service   # apply any refreshed server files

step "S7 (Service): waiting for model warmup (first boot: 1-2 min)"
SINCE=$(systemctl --user show whisperless -p ActiveEnterTimestamp --value)
ready=""
for _ in $(seq 1 60); do
  if journalctl --user -u whisperless --since "$SINCE" --no-pager 2>/dev/null | grep -q "warmup complete"; then
    ready=1
    break
  fi
  systemctl --user is-active --quiet whisperless || { journalctl --user -u whisperless -n 25 --no-pager; die "whisperless service failed to start"; }
  sleep 5
done
[ -n "$ready" ] || die "server did not warm up within 5 minutes; check: journalctl --user -u whisperless -f"
info "server ready on $BIND_IP:$PORT"

# ------------------------------------------------------- S8 (Smoke test)
if [ "${SKIP_SMOKE:-0}" != 1 ] && [ -f "$SERVER_DIR/resources/test.wav" ]; then
  step "S8 (Smoke test): streaming repo sample through the full pipeline"
  "$HOME/.local/bin/whisperless" --test "$SERVER_DIR/resources/test.wav"
else
  step "S8 (Smoke test): skipped"
fi

# ------------------------------------------------------- S9 (Hotkey)
step "S9 (Hotkey): binding ($HOTKEY)"
detect_wm() {
  case "$WM" in
    hyprland|sway|i3|other) echo "$WM"; return ;;
  esac
  if have hyprctl; then echo hyprland
  elif have swaymsg; then echo sway
  elif have i3-msg; then echo i3
  else
    printf '%s' "${XDG_CURRENT_DESKTOP:-unknown}" | tr '[:upper:]' '[:lower:]'
  fi
}
WM_DETECTED=$(detect_wm)

insert_bind() {  # FILE BINDLINE COMMENT — replace any whisperless bind, append fresh
  cp "$1" "$1.bak.whisperless"
  sed -i '/whisperless/d' "$1"
  printf '%s\n' "$(cat "$1")" > "$1"   # normalize trailing newlines/blank lines
  printf '\n%s\n%s\n' "$3" "$2" >> "$1"
  info "bind set in $1: $2"
}

replace_hyprvoice() {  # FILE — whisperless replaces hyprvoice; unbind it
  local f="$1"
  grep -q "hyprvoice-toggle" "$f" || return 0
  cp "$f" "$f.bak.whisperless"
  sed -i '/hyprvoice-toggle/d' "$f"
  info "removed hyprvoice-toggle bind in $f (replaced by whisperless)"
}

wmkey() {  # "SUPER + K" -> sway/i3 bindsym form: $mod+k
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ' | sed 's|^super|\$mod|'
}

case "$WM_DETECTED" in
  hyprland)
    for f in "$HOME/.config/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.conf"; do
      [ -f "$f" ] || continue
      case "$f" in
        *.lua) BINDLINE="hl.bind(\"$HOTKEY\", hl.dsp.exec_cmd(\"whisperless\"))" ;;
        *)     BINDLINE="bind = ${HOTKEY// + /, }, exec, whisperless" ;;
      esac
      COMMENT='-- whisperless (R2T2 dictation), added by whisperless'
      case "$f" in *.conf) COMMENT='# whisperless (R2T2 dictation), added by whisperless' ;; esac
      if grep -qF "$BINDLINE" "$f"; then info "bind already present in $f"
      else insert_bind "$f" "$BINDLINE" "$COMMENT"; fi
      replace_hyprvoice "$f"
    done
    have hyprctl && hyprctl reload >/dev/null 2>&1 || true
    ;;
  sway)
    f="$HOME/.config/sway/config"
    BINDLINE="bindsym $(wmkey "$HOTKEY") exec whisperless"
    if [ -f "$f" ]; then
      if grep -qF "$BINDLINE" "$f"; then info "bind already present in $f"
      else insert_bind "$f" "$BINDLINE" "# whisperless (R2T2 dictation), added by whisperless"; fi
      have swaymsg && swaymsg reload >/dev/null 2>&1 || true
    else
      info "sway detected but no config at $f — add manually: bindsym \$mod+<key> exec whisperless"
    fi
    ;;
  i3)
    f="$HOME/.config/i3/config"
    BINDLINE="bindsym $(wmkey "$HOTKEY") exec whisperless"
    if [ -f "$f" ]; then
      if grep -qF "$BINDLINE" "$f"; then info "bind already present in $f"
      else insert_bind "$f" "$BINDLINE" "# whisperless (R2T2 dictation), added by whisperless"; fi
      have i3-msg && i3-msg reload >/dev/null 2>&1 || true
    else
      info "i3 detected but no config at $f — add manually: bindsym \$mod+<key> exec whisperless"
    fi
    ;;
  *)
    info "window manager/desktop '${WM_DETECTED}' is not auto-configured."
    info "Bind any key of your choice to run:  whisperless"
    info "  GNOME:  Settings > Keyboard > Custom Shortcuts -> command: whisperless"
    info "  KDE:    System Settings > Shortcuts > Add Command -> whisperless"
    info "  X11 WM: add bindsym / keymap entry calling whisperless"
    ;;
esac

step "Done"
info "config:  $CONF_DIR/config.conf"
info "service: systemctl --user status whisperless   (logs: journalctl --user -u whisperless -f)"
info "client:  $HOME/.local/bin/whisperless   (log: $HOME/.cache/whisperless.log)"
info "usage:   press $HOTKEY, speak, press again — text is typed into focus."