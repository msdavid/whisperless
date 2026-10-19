# Whisperless — Configuration Guide

Every knob, explained in plain English.

Whisperless turns your voice into typed text. All of its settings live in one file —
`~/.config/whisperless/config.conf` — and this guide explains what each one does, when you
might want to touch it, and what changing it costs you. No systems knowledge required: if a
word like "KV cache" shows up, it comes with a translation.

> A styled version of this guide is available at
> [`docs/configuration-guide.html`](configuration-guide.html).

## Start here

The one-minute mental model. Whisperless has two parts: a **listener** (the app you trigger
with your hotkey) and an **AI brain** (a speech recognition engine that runs on your
computer's graphics card). Settings mostly fall into two buckets — things about *you and your
keyboard*, and things about *the AI brain*.

**How changes take effect:**

- **next dictation** — the setting applies the moment you start your next recording. Edit and
  go.
- **re-run installer** — the setting is copied into the AI brain's startup configuration when
  the installer runs, so after editing you must re-run `./install.sh` once (it copies the new
  values and restarts the brain for you). For that reason, restarting the brain on its own —
  for example with `systemctl --user restart whisperless` — is **not** enough: it would come
  back with the old values still copied in.

## How to change a setting

Open `~/.config/whisperless/config.conf` in any text editor. Every setting is one line that
looks like `KEY=value`, and lines starting with `#` are explanations you can ignore or
rewrite. Edit a value, save the file, and apply it as described above. If you ever break the
file, deleting it and re-running `./install.sh` rebuilds it with factory defaults.

## Everyday settings

### `HOTKEY`
**Default:** `CTRL + space` · **Applies:** re-run installer

The key combination you press to start recording, and press again to stop and get your text.
Use any combination your keyboard has, written like `SUPER + K` (SUPER is the Windows/⌘ key)
or `CTRL + space`.

*When to modify:* if the current combo collides with a shortcut you use in other apps (for
example, CTRL+space starts autocomplete in some code editors). The installer moves the
binding for you.

### `MAX_SECS`
**Default:** `120` · **Applies:** next dictation

A safety stop: if a recording somehow keeps going, it is finalized after this many seconds and
your text appears anyway. It exists so a forgotten recording can't run forever.

*When to modify:* only if you regularly dictate longer monologues than two minutes — raise it
to `300`. Lower it if you want a forcing function for shorter thoughts.

## Accuracy & word choice

Settings that change *what the AI writes down*. These are the highest-value knobs for
everyday use.

### `CONTEXT`
**Default:** (empty) · **Applies:** next dictation

A cheat-sheet you hand to the AI before it listens: names, product names, jargon, or the topic
you're about to discuss. Speech models are surprisingly good at English in general but
regularly mangle words that aren't in their vocabulary — company names, people's names,
acronyms. This setting tells the model what to expect, and it will favor those words when the
audio is ambiguous.

Write anything helpful, up to a few paragraphs. Real example: if you keep getting
*"Raffinate"* when you say *Refinitiv*, set `CONTEXT=Refinitiv, FST, Celerris, Hamish`.

*When to modify:* whenever you notice the same wrong word appearing repeatedly, or before a
call/project full of specialized terms. Empty is perfectly fine for casual chat.

### `VOICE_LANG`
**Default:** `English` · **Applies:** next dictation

Which language you'll be speaking. Name one language, or use `zhen` for automatic
Chinese-and-English mixing (handy if you switch mid-sentence).

*When to modify:* when you dictate in a different language, or mix Chinese and English.
Telling the model the language removes its need to guess — usually more accurate, occasionally
worse if you actually switch languages.

### `SMOOTH`
**Default:** `0` (off) · **Applies:** next dictation

A one-word instruction to the AI: *"smooth the text"* — tidy it up, polish phrasing. Useful if
you speak in fragments and want cleaner sentences out.

*When to modify:* try `SMOOTH=1` if you want dictation that reads like prose. Turn it off if
you need a faithful, word-for-word transcript.

### `USE_VAD`
**Default:** `0` (off) · **Applies:** next dictation

Turns on a *pause detector*. While you dictate, it notices when you stop talking for a moment
and commits the words so far as a finished sentence — the pause between paragraphs becomes a
period. Everything still appears in order; the text just gets "banked" in chunks instead of
one blob at the end.

*When to modify:* try it if you dictate long stretches and want the on-screen text to feel
more settled. Leave it off if you pause a lot mid-sentence (a pause would then cut your
sentence in the live view — your final text is still re-checked at the end, but the live text
may look jumpy). Turning it on also turns on `STREAMING`.

### `ROLLBACK_PUNCTUATION`
**Default:** `0` (off) · **Applies:** re-run installer

Behind the scenes, the AI keeps the last few words "in pencil" and can still rewrite them as
it hears more. This setting says: once a sentence ends with punctuation, stop rewriting the
words before it — lock them in pen.

*When to modify:* experiment. It can make the live text steadier and reduce endless small
revisions, at a small risk of locking in a mistake the model would otherwise have fixed.

## Typing & timing

Your finished text has to get into whatever app you're using. When the app supports it, it is
handed over directly, the way a language input method (like a Chinese keyboard) does; otherwise
it is "typed" by pressing virtual keys. These settings control that last step.

### `TYPER`
**Default:** `auto` · **Applies:** next dictation

How the text gets in. `ime` hands it over as an input method: no keys are pressed, so a key
you're still holding can't interfere (CTRL+M is Enter, which would send a half-finished
message). It works on Hyprland, sway and other wlroots desktops, in apps that support input
methods (GTK, Qt, Chrome, most terminals). `wtype`, `ydotool` and `xdotool` press virtual keys
instead; they first wait until you've let go of CTRL/SHIFT/ALT/SUPER. `auto` tries `ime`
first and falls back to the key typers (on KDE and GNOME only `ydotool` can type, and only
plain ASCII characters).

*When to modify:* almost never. Pin one only if a specific program ignores one method but
accepts another.

### `SETTLE_DELAY`
**Default:** `0.15` seconds · **Applies:** next dictation

A short breath before the virtual keys are pressed. Your hotkey includes a modifier key (like
CTRL), and the computer needs a blink of an eye to register that you let go — otherwise the
typed text could arrive while the system still thinks CTRL is held, triggering other
shortcuts.

*When to modify:* only if you see stray behavior right when text appears (wrong menus opening,
characters swallowed). Try `0.3`. Lower values make text appear marginally sooner.

### `TYPE_DELAY`
**Default:** `5` milliseconds · **Applies:** next dictation

The pause between virtual keystrokes when `wtype` types the text (only when the input
method can't be used). With no pause the whole
sentence arrives in one burst, and some programs drop letters from it.

*When to modify:* if typed text is missing letters but the log's `typed via` line shows the
full sentence, raise it (`10`). Each millisecond adds about 0.1 s per 100 characters.
`ydotool` and `xdotool` ignore it (they already pace their keystrokes).

### `GRACE_TAIL`
**Default:** `0.4` seconds · **Applies:** next dictation

After you press stop, the microphone keeps listening for this long and adds what it hears.
Your mouth is often still finishing the last word as your finger hits the key — this catches
it.

*When to modify:* if the last word still gets cut off — especially when you stop speaking at
the very moment you press the key — raise it (`0.5`). If you sometimes get a stray breath or
"mm" appended, lower it (`0.2`).

### `TRAILING_SPACE`
**Default:** `1` (on) · **Applies:** next dictation

Types one space after your text, so when you continue by hand the next word doesn't glue
itself to the last dictated word.

*When to modify:* set `TRAILING_SPACE=0` if you find the extra space annoying, for example
when ending sentences exactly or dictating into fields that trim poorly.

## Microphone & media

### `MIC_TARGET`
**Default:** (system default microphone) · **Applies:** next dictation

Which microphone to record from. Empty means "whatever the computer currently considers its
default microphone" — usually exactly what you want, and it follows you when you plug in a
headset.

*When to modify:* if recordings pick up the wrong device (e.g. you want the laptop mic while a
conference app grabs the headset). Find the number by running `wpctl status` in a terminal —
each source has an id, e.g. `MIC_TARGET=60`.

### `PAUSE_MEDIA`
**Default:** `1` (on) · **Applies:** next dictation

While you dictate, any music or podcast that is currently playing politely pauses, and resumes
when you're done. Only players you had *already paused yourself* stay paused. Works with
Spotify, browsers, video players — anything that follows the standard media controls.

*When to modify:* set `PAUSE_MEDIA=0` if you'd rather background music keep playing, or if the
pause/resume behavior annoys you.

## Looks & feedback

### `NOTIFY`
**Default:** `1` (on) · **Applies:** next dictation

Small desktop popups: "recording started", and a preview of the finished text. Your quiet
confirmation that things worked.

*When to modify:* `NOTIFY=0` for total silence.

### `BORDER`
**Default:** `1` (on) · **Applies:** re-run installer

While recording, the outline of your active window turns red, so you can see at a glance
whether you're being recorded — even on a different monitor. When you finish, your original
outline colors are restored exactly.

*When to modify:* `BORDER=0` if you find the red border distracting.

### `BORDER_COLOR` and `BORDER_INACTIVE_COLOR`
**Default:** red variants · **Applies:** re-run installer

The recording color itself, for the window you're typing into and for the other windows. The
format is `rgba(rrggbbaa)` — six digits for the color (like web colors), two extra digits at
the end for transparency (00 invisible, ff solid).

*When to modify:* pure taste. Example: a calmer amber — `BORDER_COLOR="rgba(ffaa33ff)"`.

### `WM`
**Default:** `auto` · **Applies:** re-run installer

Which desktop system you use, so the installer writes the hotkey binding in the right place.
`auto` detects it.

*When to modify:* only if detection ever picks wrong on an unusual setup.

## AI engine tuning

These control the AI brain that runs on your graphics card. Picture the brain as an office
worker: **GPU memory** is desk space, and the **KV cache** — the term you'll see below — is
the worker's notepad: short notes about everything heard so far, so it doesn't have to re-read
the whole conversation for every new word. Bigger notepad = remembers more = more desk space
needed. All of these are safe to leave at defaults; they're here so the brain can be squeezed
onto a graphics card that's also running your desktop, games, or other AI work. **Re-run
installer** applies to every setting in this section.

### `GPU_MEM_UTIL`
**Default:** `0.55` · **Applies:** re-run installer

The fraction of your graphics card's memory the AI brain claims when it starts — here, 55%.
The rest stays free for your desktop, browser, and games. This is the single most important
number for keeping the machine pleasant to use while dictation is available.

*When to modify:* raise it (e.g. `0.7`) if dictation is the heavy workload and you want more
headroom for long dictations; lower it if your desktop or games are starved. Too low and the
brain refuses to start (it literally won't fit).

### `MAX_MODEL_LEN`
**Default:** `8192` · **Applies:** re-run installer

The size of the notepad: how much "recent memory" the AI may keep at once, counted in word
pieces (tokens). A token is roughly a syllable-to-word of speech. 8192 tokens needs about 1 GB
of memory with this model — the sweet spot on a 16 GB card shared with a desktop.

*When to modify:* raise it for very long dictations with the extra memory to spare; lower it
(e.g. `4096`) to save roughly half a GB. Halving this number is the most effective way to free
graphics memory.

### `MAX_NUM_SEQS`
**Default:** `8` · **Applies:** re-run installer

How many recordings the brain will handle at the same time. Eight is generous for one person
(you can literally only speak into one microphone at a time); the factory default of hundreds
is for server farms. Setting it low reserves memory for the notepad instead of for imaginary
second and third speakers.

*When to modify:* leave it. Only raise it if several people dictate at once — and note the
default `BIND_IP` doesn't allow that anyway.

### `KV_CACHE_DTYPE`
**Default:** `auto` · **Applies:** re-run installer

The precision of the notepad's handwriting. `auto` means full detail. `fp8` means "write in
shorthand" — the notes take half the space, leaving room for a longer memory, with a tiny
chance of slightly less accurate text on difficult audio.

*When to modify:* try `fp8` when you want a bigger `MAX_MODEL_LEN` but can't afford the memory
at full detail.

### `MAX_NUM_BATCHED_TOKENS`
**Default:** `2048` · **Applies:** re-run installer

How much work the brain bundles into a single micro-second of computation. Small values make
the running text update smoothly (nothing big blocks the pipeline); large values favor bulk
efficiency. For one person dictating, small is right — 2048 is the tuned value.

*When to modify:* don't, unless you're benchmarking. It interacts with `MAX_MODEL_LEN` in ways
that can prevent startup.

### `MAX_NEW_TOKENS`
**Default:** `1024` · **Applies:** re-run installer

When you press stop, the brain re-listens to the *entire* recording once more and writes the
final, best version of your text. This is the word budget for that final pass. 1024 tokens
comfortably covers several minutes of speech.

*When to modify:* raise it only if you dictate very long stretches and notice the final text
coming out shorter than what you said. Costs nothing at rest.

### `TEMPERATURE`
**Default:** `0.0` · **Applies:** re-run installer

The AI's risk appetite when choosing words. 0 means "always pick the most likely word" —
exactly what you want from a transcriptionist. Higher values make it creative, which is
wonderful for writing poetry and terrible for dictation.

*When to modify:* don't. This exists so you *can*, not because you should.

### `REPETITION_PENALTY`
**Default:** `1.0` · **Applies:** re-run installer

A leash against one known AI failure mode: getting stuck in a loop and repeating the same
phrase over and over. Values above 1.0 (try `1.1`) make repeats less likely. 1.0 means the
leash is slack.

*When to modify:* if you ever see the same phrase loop in the final text, set `1.1`. If proper
nouns start coming out subtly wrong, go back to `1.0` — the leash can also suppress
legitimately repeated words.

### `STREAMING`
**Default:** `0` (off) · **Applies:** next dictation

Off: the brain does nothing while you talk and listens to the whole recording once when you
press stop (about half a second for 30 seconds of speech). On: it also transcribes every
slice as you go, which keeps the graphics card busy the whole time. whisperless doesn't show
that live text, so off loses nothing. `CHUNK_SIZE_MS`, `LOOKAHEAD_MS`, `UNFIX_TOKEN_NUM` and
`ROLLBACK_PUNCTUATION` below only matter when it's on.

*When to modify:* leave it off. `USE_VAD=1` turns it on by itself.

### `CHUNK_SIZE_MS`
**Default:** `160` · **Applies:** re-run installer

How often the brain looks at the microphone: every 160 milliseconds it processes the latest
slice and updates the live text. Smaller = snappier live text but more work for the graphics
card (it re-reads its whole notepad each time). Values from 80 to 2000 are supported.

*When to modify:* `320` halves the workload if the GPU is busy with something else; the live
text just updates in bigger steps. Your final text quality doesn't change.

### `LOOKAHEAD_MS`
**Default:** `160` · **Applies:** re-run installer

Extra audio shown to the brain alongside each slice, from slightly in the future — like
reading a sentence with the next word visible before deciding the previous one. It prevents
words from being committed wrong just because their ending hadn't arrived yet.

*When to modify:* rarely. It trades a little latency (the live text lags this many
milliseconds behind your voice) for accuracy.

### `UNFIX_TOKEN_NUM`
**Default:** `1` · **Applies:** re-run installer

How many of the newest words stay "in pencil" — revisable as more audio arrives. More pencil
words = the model can fix recent mistakes better, but the live text wobbles more. Fewer = more
stable live text, more chance an early mishearing sticks.

*When to modify:* experimentation territory. If you enjoy watching the live text and hate
seeing it rewrite itself, try `0`.

## Voice detection (VAD)

These tune the pause detector described at `USE_VAD`. They only matter when `USE_VAD=1`. The
detector listens in slices of one-hundredth of a second ("frames" — 10 milliseconds each), so
a frame count is just a time in tenths-of-seconds: 8 frames = 80 ms, 20 frames = 200 ms.
**Re-run installer** applies to all four.

### `VAD_SPEECH_THRESHOLD`
**Default:** `0.4` · **Applies:** re-run installer

How convinced the detector must be that a slice contains a voice, on a scale from 0 to 1.
Lower = more eager to call something speech (catches whispers, but may trigger on keyboard
clatter); higher = stricter.

*When to modify:* if segments cut off when you speak softly, lower it toward `0.3`; if it
fires on background noise, raise toward `0.5`.

### `VAD_MIN_SPEECH_FRAME`
**Default:** `8` (= 80 ms) · **Applies:** re-run installer

The shortest noise that counts as "you started talking". Anything shorter is treated as a
cough or a click and ignored.

*When to modify:* raise it if lip-smacks and breaths keep starting fake segments.

### `VAD_MIN_SILENCE_FRAME`
**Default:** `20` (= 200 ms) · **Applies:** re-run installer

How long you must stay silent before the detector decides the sentence is finished and banks
the text so far. This is the "natural pause" length.

*When to modify:* you habitually pause mid-sentence to think → raise it (`30` = 300 ms). You
want sentences banked aggressively → lower it.

### `VAD_MAX_SPEECH_FRAME`
**Default:** `2000` (= 20 s) · **Applies:** re-run installer

The longest a single unbroken stretch of talking may run before the detector banks it anyway,
even without a pause. A pressure valve so one rambling minute doesn't pile up uncommitted.

*When to modify:* lower it if you want text banked more often during continuous speech.

## Where the AI lives

### `SERVER_DIR`
**Default:** `~/apps/r2t2/Confucius4-R2T2` · **Applies:** re-run installer

The folder on your computer where the AI brain (its program and the downloaded model, a few
gigabytes) is installed.

*When to modify:* only if you deliberately move the installation — set the new path here
before re-running `./install.sh`.

### `PORT`
**Default:** `8272` · **Applies:** re-run installer

The "door number" the brain listens on, on your computer. Two programs can't share a door.

*When to modify:* only if another program on this machine already uses door 8272 — then pick
any free number between 1024 and 65535.

### `BIND_IP`
**Default:** `127.0.0.1` · **Applies:** re-run installer

*Who is allowed to knock on that door.* `127.0.0.1` is computer-speak for "only this very
computer" — nobody on your Wi-Fi can reach your microphone-driven AI, which is exactly what
you want for something that transcribes speech.

*When to modify:* only if you deliberately want to dictate from another device on your home
network — and understand you'd be sending voice over the network to this machine. Keep the
loopback address unless you have that specific reason.

### `GPU_INDEX`
**Default:** `0` · **Applies:** re-run installer

Which graphics card to use, if you have several. 0 is the first one.

*When to modify:* multi-GPU machines where card 0 is busy with something else (big AI
workloads often grab card 0 first).

## Common recipes

| You want… | Do this |
|---|---|
| Better accuracy on names and jargon | Set `CONTEXT` to the names you use. This is the #1 fix. Takes effect next dictation. |
| Dictate in another language / mix Chinese + English | Change `VOICE_LANG`. |
| Stop accidental "send" in chat apps | Already fixed in the current version (stray Enter and `\|` artifacts are stripped before typing). If you still see it, update via `./install.sh`. |
| Free up graphics memory for games | Lower `GPU_MEM_UTIL` (e.g. 0.45), or `MAX_MODEL_LEN=4096`, or both. Re-run the installer. |
| Room for very long dictations | Raise `MAX_SECS` (client-side) and, if memory allows, `MAX_MODEL_LEN` and `MAX_NEW_TOKENS`. |
| Less GPU usage while the machine is busy | Keep `STREAMING=0` (the default): the GPU only works once, when you stop. |
| Last word keeps getting cut off | Raise `GRACE_TAIL` to 0.4. |
| Text arrives with weird extra behavior when it appears | Raise `SETTLE_DELAY` to 0.3 (the modifier-key "glue" issue). |
| Text has missing letters or presses Enter early | Check the log (`~/.cache/whisperless.log`) says `typed via ime`; if it says `wtype`, the app doesn't accept input methods: be in the `input` group and raise `TYPE_DELAY` to 10. |
| Wrong microphone is recorded | Find its id with `wpctl status` and set `MIC_TARGET`. |
| See if you're being recorded from across the room | Keep `BORDER=1`; recolor with `BORDER_COLOR`. |

**Golden rule:** `CONTEXT` first. Every other knob on this page tunes mechanics; that one
tunes understanding.
