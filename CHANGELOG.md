# Changelog

All notable changes to hypr-input are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions are semver-ish (major.minor.patch).

## [0.1.0] - 2026-09-20

### Added
- Push-to-talk dictation toggle client (`voice-input`): pidfile-based toggle,
  mic capture via pw-record/arecord, WebSocket streaming to R2T2, text typing
  via wtype/ydotool/xdotool (auto chain, `TYPER=` override).
- `r2t2.service` systemd user unit template rendered from config.
- Installer (`install.sh`) for fresh machines: distro-mapped system deps,
  uv bootstrap, Python 3.12 venv, model download with resume, patched server,
  client, service, hotkey binding, warmup wait, WAV smoke test. Idempotent;
  config-merge for new options on upgrade.
- Uninstaller (`uninstall.sh`, `--purge` for venv + models).
- Configuration file (`~/.config/hypr-input/config.conf`): hotkey, install
  destination, language, timeouts, typer, border feedback, mic target.
- Hyprland integration: hotkey binding (hyprland.lua/.conf), recording border
  feedback with exact save/restore, hyprvoice bind replacement.
- sway/i3 binding support; printed instructions for other desktops.
- Server patches: shared-GPU memory defaults, environment-driven engine
  knobs, offline re-decode at EOS for terminal punctuation.
- English + Chinese (and mixed) recognition; `VOICE_LANG=` language hint.

### Fixed
- Terminal punctuation missing in dictation (server: offline finalize at EOS).
- Last word(s) clipped at stop (grace tail + pipe drain).
- WM shortcuts firing during typing (settle delay before key injection).
- Random "voice-input failed" (recorder teardown race).
