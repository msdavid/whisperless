# Changelog

All notable changes to whisperless are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions are semver-ish (major.minor.patch).

## [Unreleased]

### Added
- Configurable ASR engine knobs (server-side, rendered into the systemd unit
  by `install.sh`): `CHUNK_SIZE_MS`, `LOOKAHEAD_MS`, `UNFIX_TOKEN_NUM`,
  `ROLLBACK_PUNCTUATION`, `MAX_NEW_TOKENS`, `TEMPERATURE`, `REPETITION_PENALTY`,
  `MAX_NUM_SEQS`, `KV_CACHE_DTYPE`, `MAX_NUM_BATCHED_TOKENS`, and four
  `VAD_*` tuning keys. Defaults match the previous hardcoded behavior except
  `MAX_NUM_SEQS=8` (was vLLM's 256; single-user, frees VRAM for KV cache).
- Context / hotword biasing: client config `CONTEXT` is sent as the ASR
  `system_prompt` header field and now also biases the offline finalize
  re-decode; `USE_VAD` and `SMOOTH` header flags exposed from config.
- `PAUSE_MEDIA=1` (default on): media that is playing (any MPRIS player, via
  `playerctl`) pauses while recording and resumes afterwards; players that were
  already paused are left alone. Skipped silently without `playerctl`.

### Fixed
- Worker errors crashed with `NameError` (`traceback` not imported), so the
  "whisperless failed" notification and the logged traceback never appeared.
- Final transcript could carry R2T2 structural markers from the offline
  re-decode — a trailing `|` when the audio ends mid-sentence, and newlines.
  `wtype` types `\n` as Return, which sends chat messages. The server now
  sanitizes the final `reset:true` text (`sanitize_offline_text()`), and the
  client applies the same transform in `type_text` as a safety net.
- Premature dictation stops left no trace of the trigger: the client now logs
  why the stream ended (`stream end: signal|mic_eof|max_secs`), the recorder
  exit code, and the final `reset` transcript.

## [0.1.0] - 2026-09-20

### Added
- Push-to-talk dictation toggle client (`whisperless`): pidfile-based toggle,
  mic capture via pw-record/arecord, WebSocket streaming to R2T2, text typing
  via wtype/ydotool/xdotool (auto chain, `TYPER=` override).
- `whisperless.service` systemd user unit template rendered from config.
- Installer (`install.sh`) for fresh machines: distro-mapped system deps,
  uv bootstrap, Python 3.12 venv, model download with resume, patched server,
  client, service, hotkey binding, warmup wait, WAV smoke test. Idempotent;
  config-merge for new options on upgrade.
- Uninstaller (`uninstall.sh`, `--purge` for venv + models).
- Configuration file (`~/.config/whisperless/config.conf`): hotkey, install
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
- Random "whisperless failed" (recorder teardown race).
