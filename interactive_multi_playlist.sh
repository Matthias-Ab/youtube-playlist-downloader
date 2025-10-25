#!/bin/bash
set -euo pipefail

# Interactive multi-playlist MP3 downloader (URL-only .txt)
# - Prompts once for how many playlists + collects all URLs up front
# - For each playlist:
#     * auto get title
#     * terminal-friendly folder name
#     * export URL-only TXT (one URL per line)
#     * download MP3s into that folder
#     * per-playlist archive (skip already-downloaded)
#     * log failures and retry them once

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found. Install it."; exit 1; }; }
require_bin yt-dlp
require_bin awk
require_bin sed
require_bin tr

echo "=== YouTube Playlists → MP3 (interactive, URL-only .txt) ==="
echo

read -rp "How many playlists do you want to download? > " COUNT
if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
  echo "Please enter a positive integer."
  exit 1
fi

# Collect all playlist URLs first so you can step away
declare -a PLAYLIST_URLS=()
for ((i=1; i<=COUNT; i++)); do
  read -rp "Enter playlist URL #$i: " PURL
  PURL="$(echo "$PURL" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -z "$PURL" ]] && { echo "Empty URL, skipping this slot."; continue; }
  PLAYLIST_URLS+=("$PURL")
done

# Sanitize to terminal-friendly: lowercase, non-alnum -> underscores, collapse repeats
sanitize_name() {
  printf '%s' "$1" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/_/g; s/_+/_/g; s/^_|_$//g'
}

# Get playlist title with fallback
get_playlist_title() {
  local url="$1"
  local title
  title="$(yt-dlp --flat-playlist --playlist-end 1 --print "%(playlist_title)s" "$url" 2>/dev/null | head -n1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [[ -z "$title" || "$title" == "NA" ]]; then
    local fallback
    fallback="$(yt-dlp --flat-playlist --playlist-end 1 --print "%(uploader)s_%(playlist_id)s" "$url" 2>/dev/null | head -n1)"
    [[ -z "$fallback" || "$fallback" == "NA" ]] && fallback="youtube_playlist_$(date +%s)"
    title="$fallback"
  fi
  echo "$title"
}

# Export playlist to URL-only TXT (one URL per line)
export_playlist_urls() {
  local url="$1"
  local outfile="$2"
  # Use webpage URLs; strip blanks; keep first occurrence order
  yt-dlp --flat-playlist --print "%(webpage_url)s" "$url" \
    | sed '/^[[:space:]]*$/d' \
    | awk '!seen[$0]++' \
    > "$outfile"
}

# Download a single URL to MP3
download_one() {
  local url="$1"
  local outdir="$2"
  local archive="$3"
  yt-dlp \
    -f "ba" \
    --extract-audio --audio-format mp3 --audio-quality 0 \
    --download-archive "$archive" \
    --no-overwrites \
    --continue \
    --restrict-filenames \
    --force-ipv4 \
    -o "$outdir/%(title)s.%(ext)s" \
    "$url"
}

echo
echo "Starting processing for ${#PLAYLIST_URLS[@]} playlist(s)…"
declare -a FAILED_URLS_ALL=()

for PURL in "${PLAYLIST_URLS[@]}"; do
  echo
  echo "▶ Extracting playlist title…"
  PTITLE="$(get_playlist_title "$PURL")"
  SAFE_NAME="$(sanitize_name "$PTITLE")"
  [[ -z "$SAFE_NAME" ]] && SAFE_NAME="youtube_playlist_$(date +%s)"

  OUT_DIR="$SAFE_NAME"
  URLS_TXT="${SAFE_NAME}.txt"        # URL-only file
  ARCHIVE_FILE="${SAFE_NAME}.archive"
  FAILED_FILE="${SAFE_NAME}_failed.log"

  echo "▶ Using folder: $OUT_DIR"
  mkdir -p "$OUT_DIR"
  : > "$FAILED_FILE"

  echo "▶ Exporting URL-only list → $URLS_TXT"
  export_playlist_urls "$PURL" "$URLS_TXT"

  TOTAL=$(wc -l < "$URLS_TXT" | tr -d ' ')
  echo "▶ Found $TOTAL items."
  if [[ "$TOTAL" -eq 0 ]]; then
    echo "No items found. Skipping this playlist."
    continue
  fi

  echo "▶ Downloading MP3s into $OUT_DIR …"
  n=0
  while IFS= read -r URL_ITEM; do
    n=$((n+1))
    [[ -z "$URL_ITEM" ]] && continue
    echo "[$n/$TOTAL] $URL_ITEM"
    if ! download_one "$URL_ITEM" "$OUT_DIR" "$ARCHIVE_FILE"; then
      echo "$URL_ITEM" | tee -a "$FAILED_FILE"
      FAILED_URLS_ALL+=("$URL_ITEM")
    fi
  done < "$URLS_TXT"

  # Retry failed once for this playlist
  if [[ -s "$FAILED_FILE" ]]; then
    echo "▶ Retrying failed once for: $SAFE_NAME"
    mapfile -t FAILED_LIST < "$FAILED_FILE"
    : > "${FAILED_FILE}.retry.log"
    for U in "${FAILED_LIST[@]}"; do
      echo "Retry: $U"
      if ! download_one "$U" "$OUT_DIR" "$ARCHIVE_FILE"; then
        echo "$U" >> "${FAILED_FILE}.retry.log"
      fi
    done

    if [[ -s "${FAILED_FILE}.retry.log" ]]; then
      echo "Some items still failed after retry. See: ${FAILED_FILE}.retry.log"
    else
      echo "All previously failed items downloaded on retry ✅"
      rm -f "$FAILED_FILE" "${FAILED_FILE}.retry.log" 2>/dev/null || true
    fi
  fi

  echo "✔ Finished playlist: $PTITLE"
  echo "   - Folder: $OUT_DIR/"
  echo "   - Archive: $ARCHIVE_FILE"
  echo "   - URL list: $URLS_TXT"
done

echo
echo "=== All requested playlists processed ==="
if [[ "${#FAILED_URLS_ALL[@]}" -gt 0 ]]; then
  echo "Some URLs failed. Check *_failed.log (and *.retry.log) files per playlist."
else
  echo "All downloads completed without persistent failures ✅"
fi
