#!/bin/bash

# Input file (change if your filename is different)
INPUT_FILE="ertrea playlist 1.txt"

# Output directory
OUTPUT_DIR="downloaded_songs_mp3"

# Log file for failures
FAILED_LOG="failed.log"

# Create output directory if not exists
mkdir -p "$OUTPUT_DIR"

# Clear the failed log if exists
> "$FAILED_LOG"

echo "Starting download process..."
echo "Saving MP3 files into: $OUTPUT_DIR"
echo "Failed attempts logged in: $FAILED_LOG"
echo

while IFS= read -r line
do
    # Extract URL from after the semicolon
    url=$(echo "$line" | awk -F';' '{print $2}')

    # Skip empty or malformed lines
    if [[ -z "$url" ]]; then
        continue
    fi

    echo "Processing URL: $url"

    yt-dlp \
        -f "ba" \
        --extract-audio \
        --audio-format mp3 \
        --audio-quality 0 \
        --no-continue \
        --no-overwrites \
        --restrict-filenames \
        -o "$OUTPUT_DIR/%(title)s.%(ext)s" \
        "$url"

    # If last command failed (non-zero), log the URL
    if [[ $? -ne 0 ]]; then
        echo "FAILED: $url" | tee -a "$FAILED_LOG"
        echo
    else
        echo "✅ Downloaded successfully"
        echo
    fi

done < "$INPUT_FILE"

echo "----------------------------------"
echo "Download script finished!"
echo "Check $OUTPUT_DIR for your songs."
echo "Any failures are inside: $FAILED_LOG"
