#!/bin/bash
# Install live Norwegian and English microphone dictation for zsh on macOS.
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'This installer is for macOS.' >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  for brew_dir in /opt/homebrew/bin /usr/local/bin; do
    if [[ -x "$brew_dir/brew" ]]; then
      export PATH="$brew_dir:$PATH"
      break
    fi
  done
fi

if ! command -v brew >/dev/null 2>&1; then
  printf '%s\n' 'Homebrew (brew) is missing.' \
    'Install Homebrew from https://brew.sh/ and run this script again.' >&2
  exit 1
fi

usage() {
  printf '%s\n' \
    'Usage: bash setup-dictation.sh [norwegian-size english-size]' \
    '  Norwegian: tiny (29.9 MB), base (55.3 MB), small (175 MB),' \
    '             medium (539 MB), large (1.08 GB)' \
    '  English:   base (59.7 MB), small (190 MB)' \
    '  Run without arguments to choose both models with the keyboard.'
}

select_model() {
  local label="$1" selected="$2" key index marker option
  shift 2
  local options=("$@")
  local count="${#options[@]}"

  printf '\nChoose a %s model. Use ↑/↓ to move and Space to select.\n' "$label"
  while true; do
    for ((index = 0; index < count; index++)); do
      marker='○'
      if (( index == selected )); then marker='●'; fi
      printf '\033[2K  %s %s\n' "$marker" "${options[index]}"
    done
    IFS= read -rsn1 key || return 1
    case "$key" in
      ' '|''|$'\r') break ;;
      $'\033')
        IFS= read -rsn2 -t 1 key || key=''
        case "$key" in
          '[A'|'OA') selected=$(( (selected + count - 1) % count )) ;;
          '[B'|'OB') selected=$(( (selected + 1) % count )) ;;
        esac
        ;;
    esac
    printf '\033[%dA\r' "$count"
  done
  option="${options[selected]}"
  selected_size="${option%% *}"
  printf 'Selected %s %s\n' "$label" "$option"
}

case "$#" in
  0)
    if [[ ! -t 0 || ! -t 1 ]]; then
      usage >&2
      exit 2
    fi
    select_model Norwegian 2 \
      'tiny (29.9 MB)' 'base (55.3 MB)' 'small (175 MB)' 'medium (539 MB)' 'large (1.08 GB)'
    norwegian_size="$selected_size"
    select_model English 1 'base (59.7 MB)' 'small (190 MB)'
    english_size="$selected_size"
    ;;
  1)
    if [[ "$1" == --help || "$1" == -h ]]; then
      usage
      exit 0
    fi
    usage >&2
    exit 2
    ;;
  2) norwegian_size="$1"; english_size="$2" ;;
  *) usage >&2; exit 2 ;;
esac

model_checksum() {
  case "$1:$2" in
    no:tiny)   printf '%s\n' e5fb42192cdf31bea624a524d035e8895030b2bb4b31d4ea2a1ebf0ea8f57237 ;;
    no:base)   printf '%s\n' dcb9f3ab963cd288974c826c1519ff73b78b2372e80d388a6ce94f29c6a5b40f ;;
    no:small)  printf '%s\n' 2a9025afb6e825fc4ae6a46671e0cb2f43e62f1dec87270deea6fe61b5285a20 ;;
    no:medium) printf '%s\n' 18733de634af639a43b0f8c5f5a2ea0920de4c5b32a5570ec130981581c0e5e7 ;;
    no:large)  printf '%s\n' feb5951ae694a62cfeb81fb501f6cfa8cc50d96bcddb1e4e8215f7006bac23a2 ;;
    en:base)   printf '%s\n' 4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f ;;
    en:small)  printf '%s\n' bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30 ;;
    *) usage >&2; return 2 ;;
  esac
}

norwegian_checksum="$(model_checksum no "$norwegian_size")"
english_checksum="$(model_checksum en "$english_size")"

brew install whisper.cpp
stream_path="$(brew --prefix whisper.cpp)/bin/whisper-stream"
if [[ ! -x "$stream_path" ]]; then
  printf '%s\n' "Could not find whisper-stream at $stream_path." >&2
  exit 1
fi

model_dir="$HOME/.local/share/whisper"
mkdir -p "$model_dir"
temp_dir="$(mktemp -d "$model_dir/.setup.XXXXXX")"
trap 'rm -rf -- "$temp_dir"' EXIT

model_matches() {
  local model_file="$1" expected="$2" checksum
  [[ -f "$model_file" ]] || return 1
  checksum="$(shasum -a 256 < "$model_file")" || return 1
  [[ "${checksum%% *}" == "$expected" ]]
}

install_model() {
  local filename="$1" url="$2" checksum="$3"
  if model_matches "$model_dir/$filename" "$checksum"; then
    return 0
  fi
  printf 'Downloading %s…\n' "$filename"
  curl -fL --retry 3 -o "$temp_dir/$filename" "$url"
  if ! model_matches "$temp_dir/$filename" "$checksum"; then
    printf 'Checksum verification failed for %s.\n' "$filename" >&2
    return 1
  fi
  mv -f "$temp_dir/$filename" "$model_dir/$filename"
}

norwegian_model="nb-$norwegian_size.bin"
english_model="en-$english_size.bin"
install_model "$norwegian_model" \
  "https://huggingface.co/NbAiLab/nb-whisper-$norwegian_size/resolve/main/ggml-model-q5_0.bin" \
  "$norwegian_checksum"
install_model "$english_model" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$english_size.en-q5_1.bin" \
  "$english_checksum"

{
  printf 'dictation() {\n  local stream_path=%q norwegian_model=%q english_model=%q\n' \
    "$stream_path" "$model_dir/$norwegian_model" "$model_dir/$english_model"
  cat <<'ZSH'
  local language="${1:-no}" model
  if (( $# > 1 )); then
    printf '%s\n' 'Usage: dictation [no|en]' >&2
    return 2
  fi
  case "$language" in
    no) model="$norwegian_model" ;;
    en) model="$english_model" ;;
    *) printf '%s\n' 'Usage: dictation [no|en]' >&2; return 2 ;;
  esac

  local timestamp transcript result=0
  timestamp="$(date +%Y%m%d-%H%M%S)" || return 1
  transcript="$PWD/transcript-$timestamp-$$-$RANDOM.txt"
  (umask 077; setopt noclobber; : > "$transcript") || return 1
  printf 'Saving transcript to %s\n' "$transcript"

  setopt localoptions pipefail
  "$stream_path" -m "$model" \
    -l "$language" --step 1000 --length 5000 | (
      # Let the recorder stop on Ctrl+C, then read through EOF and save the last line.
      trap '' INT
      exec /usr/bin/perl -e '
        use strict;
        use warnings;
        $| = 1;
        open my $out, ">>", $ARGV[0] or die "Cannot open transcript: $!\n";
        select((select($out), $| = 1)[0]);
        my ($buffer, $pending, $started) = ("", "", 0);

        sub clean {
          my ($text) = @_;
          $text =~ s/\e\[[0-9;]*[A-Za-z]//g;
          $text =~ s/^\s+|\s+$//g;
          return $text;
        }

        while (1) {
          my $bytes = sysread STDIN, my $chunk, 4096;
          die "Cannot read dictation output: $!\n" unless defined $bytes;
          last unless $bytes;
          print STDOUT $chunk or die "Cannot write to the terminal: $!\n";
          $buffer .= $chunk;
          while ($buffer =~ s/\A([^\r\n]*)([\r\n])//) {
            my ($line, $ending) = ($1, $2);
            my $text = clean($line);
            # The first erase-line sequence marks the start of transcription.
            if (!$started) {
              $started = 1 if $line =~ /\e\[2K/ && $ending eq "\r";
              next;
            }
            if ($ending eq "\r") {
              $pending = $text if length $text;
            } else {
              print {$out} "$text\n" or die "Cannot write transcript: $!\n" if length $text;
              $pending = "";
            }
          }
        }

        if ($started) {
          my $last = clean($buffer);
          $last = $pending unless length $last;
          print {$out} "$last\n" or die "Cannot write transcript: $!\n" if length $last;
        }
        close $out or die "Cannot finish transcript: $!\n";
      ' "$transcript"
    ) || result=$?

  printf '\nTranscript file: %s\n' "$transcript"
  return "$result"
}

dictate() {
  dictation "$@"
}
ZSH
} > "$temp_dir/dictate.zsh"
/bin/zsh -n "$temp_dir/dictate.zsh"
mv -f "$temp_dir/dictate.zsh" "$model_dir/dictate.zsh"

zshrc="${ZDOTDIR:-$HOME}/.zshrc"
source_line='source "$HOME/.local/share/whisper/dictate.zsh"'
touch "$zshrc"
if ! grep -Fxq "$source_line" "$zshrc"; then
  printf '\n%s\n' "$source_line" >> "$zshrc"
fi

printf '\n%s\n' \
  "Setup complete. Norwegian: $norwegian_size. English: $english_size." \
  'Open a new zsh terminal and run dictation no or dictation en.' \
  'Rerun this setup script to change models.' \
  'Each session saves a transcript in the folder you start it from.' \
  'Allow microphone access when macOS asks. Press Ctrl+C to stop.'
