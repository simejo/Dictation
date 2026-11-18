# Dictation

Local Norwegian and English microphone dictation for macOS. Text appears live in Terminal and is saved to a timestamped transcript.

## Setup

1. Install [Homebrew](https://brew.sh/) if needed.
2. From this folder, run `bash setup-dictation.sh`.
3. Choose a Norwegian model, then an English model. Use **↑/↓** to move and **Space** to select. Setup installs `whisper.cpp` and downloads the two selected models.

## Use

Open a new Terminal window, then run:

```sh
dictation no   # Norwegian
dictation en   # English
```

Allow microphone access when macOS prompts you. Press **Ctrl+C** to stop. Transcript files (`transcript-*.txt`) are saved in the folder where you ran the command and ignored by Git.

Rerun setup to change models or to install Dictation on another Mac after cloning this repository.
