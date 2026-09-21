# Contributing to whisperless

Thanks for helping! This project is intentionally small — two moving parts
(a GPU server we patch lightly, and a ~200-line Python client) — so changes
should stay small too.

## Development setup

```bash
git clone <your-fork> && cd whisperless
./install.sh                 # full setup; safe to re-run
# or, while iterating on code with models already in place:
SKIP_MODELS=1 SKIP_SMOKE=1 ./install.sh
```

No linters are configured. Before committing:

```bash
bash -n install.sh uninstall.sh                       # shell syntax
python3 -c "import ast; ast.parse(open('whisperless').read().split('\n',1)[1])"
~/.local/bin/whisperless --test some-16k-mono.wav     # end-to-end pipeline
```

## How the pieces fit

| File | What it is | Gotchas |
|------|-----------|---------|
| `whisperless` | client: toggle, capture, WS stream, typing | source of truth is the copy here; `install.sh` rewrites the shebang when installing |
| `server/ws_server.py` | patched copy of upstream `ws_server.py` | edit **here**, never in `~/apps/r2t2` — install.sh copies this file over the checkout |
| `whisperless.conf` | documented default config | installed config lives at `~/.config/whisperless/config.conf`; installer merges new keys into existing configs |
| `whisperless.service` | systemd unit **template** (`@PLACEHOLDER@s`) | rendered by install.sh from config |

## Ground rules

1. **Server patches stay marked.** Any change to `server/ws_server.py` must
   carry a `# patched` comment and be reflected in `server/NOTICE` and the
   README "Server patches" section — that's our Apache-2.0 change statement.
2. **Config is the interface.** New behavior gets a `KEY=value` option with a
   default in `whisperless.conf`, not a new flag or hardcoded constant. The
   installer must keep working with configs written by older versions (never
   require a key).
3. **Client reads config live; server needs re-install.** If your change is
   server-side, say so in the PR description.
4. **Docs are part of the change.** Update `README.md` and `CHANGELOG.md`
   (Keep a Changelog format) in the same commit.
5. **Toggle/border logic is subtle.** The stop path has known races
   (ProcessLookupError on recorder teardown, WM modifier contamination during
   typing, trailing-word buffering). If you touch it, re-test the full
   round-trip: start → speak → stop, plus start → immediate stop on silence.

## Reporting issues

Include:
- `journalctl --user -u r2t2 -n 50` (server side)
- `~/.cache/whisperless.log` tail (client side — errors log full tracebacks)
- your `~/.config/whisperless/config.conf` (no secrets in it)
- GPU model + driver version (`nvidia-smi`)
