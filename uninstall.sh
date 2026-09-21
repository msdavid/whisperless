#!/usr/bin/env bash
# hypr-input uninstaller — removes the service, client and hotkey bind.
# Config is kept unless --purge is passed; --purge also deletes the R2T2
# checkout (venv + model weights, ~15GB).
set -euo pipefail

step() { printf '\n==> %s\n' "$*"; }

step "Stopping r2t2.service"
systemctl --user disable --now r2t2.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/r2t2.service"
systemctl --user daemon-reload

step "Removing client"
rm -f "$HOME/.local/bin/voice-input"

step "Removing hotkey bind"
for f in "$HOME/.config/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.conf"; do
  [ -f "$f" ] && grep -q "voice-input" "$f" || continue
  cp "$f" "$f.bak.hypr-input"
  sed -i '/voice-input/d' "$f"
  echo "    bind removed from $f (backup: $f.bak.hypr-input)"
done
echo "    note: a previous hyprvoice-toggle bind (if any) is NOT restored — re-add manually if needed"
command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1 || true

if [ "${1:-}" = "--purge" ]; then
  SERVER_DIR="$HOME/apps/r2t2/Confucius4-R2T2"
  conf="$HOME/.config/hypr-input/config.conf"
  if [ -f "$conf" ]; then
    # shellcheck disable=SC1090
    SERVER_DIR="$(bash -c "source '$conf' >/dev/null 2>&1 && printf '%s' \"\$SERVER_DIR\"")"
  fi
  SERVER_DIR="${SERVER_DIR%/}"
  step "Purging $SERVER_DIR"
  rm -rf "$SERVER_DIR"
  rm -rf "$HOME/.config/hypr-input"
else
  echo "    kept $HOME/apps/r2t2 and ~/.config/hypr-input (use --purge to delete)"
fi

step "Done — hypr-input removed"