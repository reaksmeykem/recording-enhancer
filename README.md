# Recording Enhancer

Dark, modern Windows GUI that cleans up voice in screen recordings using FFmpeg's
RNNoise AI denoiser — locally, nothing is uploaded.

![UI](https://img.shields.io/badge/UI-WPF_PowerShell-5E5CE6) ![Engine](https://img.shields.io/badge/Engine-FFmpeg_RNNoise-BF5AF2)

## What it does

- Lists recordings from a folder you choose (defaults to `Motionik-Recordings`),
  merges a nearby `microphone.webm` track if one exists, otherwise enhances the
  video's own audio. **Audio-only files (mp3, wav, m4a, aac, flac, ogg) work too**
  and export as `*-ENHANCED.m4a`.
- Two voice treatments:
  - **Natural** — gentle rumble filter + AI denoise only. Keeps the voice's own
    tone; leaves a little room sound on purpose.
  - **Classic** — the original chain: declip → high-pass → AI denoise → tone EQ
    → de-ess → soft compression.
- Restores analyzed loudness so speech is not quieter after cleanup.
- Writes a separate `*-ENHANCED.mp4`; video is stream-copied (not re-encoded),
  the original file is never modified.

## Requirements

- Windows 10/11
- [FFmpeg](https://www.gyan.dev/ffmpeg/builds/) (full build) on PATH or installed
  via `winget install Gyan.FFmpeg`

## Run it

**Option A — EXE:** double-click `Recording Enhancer.exe` (or build it yourself,
see below). The EXE still needs FFmpeg installed; it is a launcher, not a
self-contained runtime.

**Option B — script:** double-click `Recording Enhancer.bat`, or:

```powershell
powershell -ExecutionPolicy Bypass -File enhance-gui.ps1
```

## Build the EXE

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```

Downloads PS2EXE on first run and produces `Recording Enhancer.exe` next to the
script.

## Notes

- `rnnoise-model.rnnn` is the bundled voice model (standard RNNoise weights).
- If no recordings are found, use the folder icon in the title bar to pick the
  folder your screen recorder writes to.
- The window is frameless; close/minimize buttons are in the top-right pill.

## License

MIT
