#!/bin/bash
set -e

TMP_DIR="/tmp/balkon_sounds"
ZIP1="$HOME/Downloads/kenney_interface-sounds.zip"
OUT_DIR="/home/pfeifer/src/own/misc/balkon-borg/src/android/app/assets/audio/ui"

mkdir -p "$TMP_DIR"
mkdir -p "$OUT_DIR"

unzip -o "$ZIP1" -d "$TMP_DIR" > /dev/null

# Helper function to convert to WAV (16-bit, mono, 44100 Hz)
conv() {
    src="$1"
    dst="$2"
    ffmpeg -y -i "$src" -c:a pcm_s16le -ac 1 -ar 44100 "$dst" < /dev/null > /dev/null 2>&1
}

echo "Converting blips..."
conv "$TMP_DIR/Audio/click_001.ogg" "$OUT_DIR/blip-1.wav"
conv "$TMP_DIR/Audio/click_002.ogg" "$OUT_DIR/blip-2.wav"
conv "$TMP_DIR/Audio/click_003.ogg" "$OUT_DIR/blip-3.wav"
conv "$TMP_DIR/Audio/click_004.ogg" "$OUT_DIR/blip-4.wav"
conv "$TMP_DIR/Audio/click_005.ogg" "$OUT_DIR/blip-5.wav"

echo "Converting chirps..."
conv "$TMP_DIR/Audio/confirmation_001.ogg" "$OUT_DIR/chirp-1.wav"
conv "$TMP_DIR/Audio/confirmation_002.ogg" "$OUT_DIR/chirp-2.wav"
conv "$TMP_DIR/Audio/confirmation_003.ogg" "$OUT_DIR/chirp-3.wav"

echo "Converting power sounds..."
conv "$TMP_DIR/Audio/maximize_008.ogg" "$OUT_DIR/power-up.wav"
conv "$TMP_DIR/Audio/minimize_008.ogg" "$OUT_DIR/power-down.wav"

echo "Converting PTT..."
conv "$TMP_DIR/Audio/switch_001.ogg" "$OUT_DIR/ptt-click.wav"
conv "$TMP_DIR/Audio/confirmation_004.ogg" "$OUT_DIR/ptt-roger.wav"

echo "Converting sad sounds..."
conv "$TMP_DIR/Audio/error_004.ogg" "$OUT_DIR/sad-1.wav"
conv "$TMP_DIR/Audio/error_005.ogg" "$OUT_DIR/sad-2.wav"

echo "Converting twitters (easter eggs placeholders)..."
conv "$TMP_DIR/Audio/glitch_001.ogg" "$OUT_DIR/twitter-1.wav"
conv "$TMP_DIR/Audio/glitch_002.ogg" "$OUT_DIR/twitter-2.wav"

echo "Sounds installed in $OUT_DIR."
rm -rf "$TMP_DIR"
