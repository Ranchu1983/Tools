# Claude Voice Setup — Install Guide (copy-paste to any machine ~/.claude/VOICE_SETUP.md)

Reads Claude Code responses aloud using **Piper** (neural TTS, natural sounding),
with **espeak-ng** as a fallback. Tested on Ubuntu 22.04 under WSL2 (WSLg audio).

---

## 1. System packages

```bash
# audio player that routes to the working sink (PulseAudio / WSLg PulseServer)
sudo apt-get update
sudo apt-get install -y pulseaudio-utils

# fallback engine (optional but recommended)
sudo apt-get install -y espeak-ng mbrola mbrola-en1 mbrola-us2
```

> **WSL note:** WSLg exposes audio at `/mnt/wslg/PulseServer` (env `PULSE_SERVER`).
> Use **`paplay`** (PulseAudio) to play — NOT `pw-play`, because local PipeWire has
> no output sink in WSL. `paplay` is the piece that actually reaches the speakers.

## 2. Install Piper (neural TTS engine)

```bash
pipx install piper-tts        # preferred; or: pip3 install --user piper-tts
# make sure ~/.local/bin is on PATH
which piper
```

## 3. Download voice models

Each Piper voice = **two files**: the `.onnx` model AND its matching `.onnx.json`.
Both are required.

```bash
mkdir -p ~/.local/share/piper-voices && cd ~/.local/share/piper-voices
BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US"

# Kusal (default in this setup)
curl -sL -o en_US-kusal-medium.onnx      "$BASE/kusal/medium/en_US-kusal-medium.onnx"
curl -sL -o en_US-kusal-medium.onnx.json "$BASE/kusal/medium/en_US-kusal-medium.onnx.json"

# Amy (alternate)
curl -sL -o en_US-amy-medium.onnx        "$BASE/amy/medium/en_US-amy-medium.onnx"
curl -sL -o en_US-amy-medium.onnx.json   "$BASE/amy/medium/en_US-amy-medium.onnx.json"

# verify (should be ~60 MB "data", not a tiny HTML 404 page)
ls -lh *.onnx && file *.onnx
```

Browse more voices at: https://huggingface.co/rhasspy/piper-voices/tree/main/en/en_US

## 4. Test playback

```bash
echo "Voice setup is working." \
  | piper -m ~/.local/share/piper-voices/en_US-kusal-medium.onnx \
          --length-scale 0.81 --output_file /tmp/voice.wav
paplay /tmp/voice.wav
```

If you hear it, you are done. If not, the WSLg/PulseAudio bridge to the OS is the
problem (not Piper) — confirm `echo $PULSE_SERVER` and that Windows audio works.

### Speed reference (`--length-scale`, lower = faster; calibrated on Amy)

| length-scale | approx wpm |
|---|---|
| 1.00 | ~179 |
| 0.99 | ~180 |
| 0.90 | ~193 |
| 0.87 | ~200 |
| 0.81 | ~220 (default) |
| 0.75 | ~221 |

Formula: `length-scale ≈ 179 / target_wpm`.

---

## 5. Add the Voice skill to Claude

Append the block below to `~/.claude/CLAUDE.md` (create the file if missing). This
makes Claude read its responses aloud in **every** session on that machine.

````markdown
## Skills

### Voice (read responses aloud)

Read my on-screen responses aloud. Primary engine is **Piper** (neural, natural). `espeak-ng` is the fallback.

- **Engine (Piper):** `echo "<plain-text summary>" | piper -m <model> --length-scale <scale> --output_file /tmp/voice.wav && paplay /tmp/voice.wav`
  - Models live in `~/.local/share/piper-voices/`. Default: `en_US-kusal-medium.onnx` (each model needs its matching `.onnx.json`). Also installed: `en_US-amy-medium.onnx`.
  - Playback MUST use `paplay` (PulseAudio → WSLg `/mnt/wslg/PulseServer`), NOT `pw-play` (local PipeWire has no sink).
- **Fallback engine (espeak-ng):** `espeak-ng -v mb-en1 -s <wpm> "<text>"`. MBROLA voices: `mb-en1` (British), `mb-us2` (American).
- **Default state: ON for every session.** Speak each response aloud from the start of every session, without waiting for a "voice on" command. Speak a cleaned-up plain-text version — strip markdown, code blocks, file paths, and symbols that read awkwardly.
- **Turn on:** "voice on" (re)enables speaking if it was turned off.
- **Turn off:** "voice off" stops speaking for the rest of that session only.
- **List voices:** on "list voice characters" / "list voices", enumerate `~/.local/share/piper-voices/*.onnx` and mark the current default.
- **Change voice:** switch the Piper model on "change voice to <name>".
- **Speed:** Piper uses `--length-scale` (lower = faster). `1.0`≈179 wpm, `0.87`≈200 wpm, `0.81`≈220 wpm. Target a wpm with `length-scale ≈ 179 / target_wpm`.

Current settings — State: ON by default (all sessions), Engine: Piper, Voice: `en_US-kusal-medium`, Speed: `--length-scale 0.81` (~220 wpm).
````

> If `~/.claude/CLAUDE.md` already has a `## Skills` heading, paste only the
> `### Voice ...` subsection under it (don't duplicate `## Skills`).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `paplay: command not found` | pulseaudio-utils missing | `sudo apt-get install -y pulseaudio-utils` |
| `pw-play: no node available` | using PipeWire (no sink in WSL) | use `paplay`, not `pw-play` |
| Piper WAV made but silent | audio bridge to OS not reaching speakers | check `echo $PULSE_SERVER`; restart WSL (`wsl --shutdown` in Windows) |
| `.onnx` is only a few KB | download got an HTML 404 | re-check the URL path; re-download both files |
| `piper: command not found` | `~/.local/bin` not on PATH | add `export PATH="$HOME/.local/bin:$PATH"` |
