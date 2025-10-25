#!/bin/bash
set -euo pipefail

# ---------------------------
# Interactive multi-playlist MP3 downloader for Ubuntu 24.04
# - Asks how many playlists
# - For each: fetch title, make terminal-friendly folder, export TXT (title;url), download MP3s
# - Skips already-downloaded using per-playlist archive
# - Logs failures and retries them once at the end
# ---------------------------

require_bin() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found. Please install it."; exit 1; }
}
require_bin yt-dlp
require_bin awk
require_bin sed
require_bin tr

echo "=== YouTube Playlists → MP3 (interactive) ==="
echo "This script will:"
echo "  • Ask how many playlists"
echo "  • For each: create <playlist_name>.txt (title;url), folder <playlist_name>/"
echo "  • Download MP3s into that folder"
echo "  • Keep a per-playlist archive to skip already-downloaded"
echo "  • Retry failures once"
echo

read -rp "How many playlists do you want to download? > " COUNT
if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
  echo "Please enter a positive integer."
  exit 1
fi

# Sanitize to terminal-friendly: lowercase, replace non-alnum with underscores, collapse repeats, trim edges.
sanitize_name() {
  printf '%s' "$1" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/_/g; s/_+/_/g; s/^_|_$//g'
}

# Extract a single playlist title (fast) with fallback
get_playlist_title() {
  local url="$1"
  # Try to get playlist title (limit to 1 line to avoid per-entry spam)
  local title
  title="$(yt-dlp --flat-playlist --playlist-end 1 --print "%(playlist_title)s" "$url" 2>/dev/null | head -n1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  if [[ -z "$title" || "$title" == "NA" ]]; then
    # Fallback: uploader + playlist_id
    local fallback
    fallback="$(yt-dlp --flat-playlist --playlist-end 1 --print "%(uploader)s_%(playlist_id)s" "$url" 2>/dev/null | head -n1)"
    if [[ -z "$fallback" || "$fallback" == "NA" ]]; then
      title="youtube_playlist_$(date +%s)"
    else
      title="$fallback"
    fi
  fi
  echo "$title"
}

# Export playlist to TXT: "title;url" per line.
# Also produce a URL-only .urls file for the downloader.
export_playlist_txt() {
  local url="$1"
  local txt="$2"
  local urls="$3"

  # We’ll print title;url. Title can sometimes contain semicolons — make them commas to keep the format stable.
  yt-dlp --flat-playlist --print "%(title)s;%(url)s" "$url" \
  | sed 's/;/,/1' \
  | awk -F';' 'NF>=2{print $1";"$2}' \
  | sed '/^[[:space:]]*$/d' \
  > "$txt"

  # URL-only list for downloading
  awk -F';' '{print $NF}' "$txt" | sed '/^[[:space:]]*$/d' | sort -u > "$urls"
}

# Download a single URL to MP3; return nonzero on failure so caller can log it.
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

# Process each playlist interactively
declare -a FAILED_URLS_ALL=()

for ((i=1; i<=COUNT; i++)); do
  echo
  read -rp "Enter playlist URL #$i: " PURL
  PURL="$(echo "$PURL" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [[ -z "$PURL" ]]; then
    echo "Skipped empty URL."
    continue
  fi

  echo "▶ Extracting playlist title..."
  PTITLE="$(get_playlist_title "$PURL")"
  SAFE_NAME="$(sanitize_name "$PTITLE")"

  [[ -z "$SAFE_NAME" ]] && SAFE_NAME="youtube_playlist_$(date +%s)"

  OUT_DIR="$SAFE_NAME"
  TXT_FILE="${SAFE_NAME}.txt"
  URLS_FILE="${SAFE_NAME}.urls"
  ARCHIVE_FILE="${SAFE_NAME}.archive"
  FAILED_FILE="${SAFE_NAME}_failed.log"

  echo "▶ Using folder: $OUT_DIR"
  mkdir -p "$OUT_DIR"
  : > "$FAILED_FILE"

  echo "▶ Exporting playlist entries to $TXT_FILE (title;url) and $URLS_FILE (urls)"
  export_playlist_txt "$PURL" "$TXT_FILE" "$URLS_FILE"

  TOTAL=$(wc -l < "$URLS_FILE" | tr -d ' ')
  echo "▶ Found $TOTAL items."

  if [[ "$TOTAL" -eq 0 ]]; then
    echo "No items found for this playlist. Continuing to next…"
    continue
  fi

  echo "▶ Downloading MP3s into $OUT_DIR ..."
  n=0
  while IFS= read -r URL_ITEM; do
    n=$((n+1))
    [[ -z "$URL_ITEM" ]] && continue
    echo "[$n/$TOTAL] $URL_ITEM"
    if ! download_one "$URL_ITEM" "$OUT_DIR" "$ARCHIVE_FILE"; then
      echo "$URL_ITEM" | tee -a "$FAILED_FILE"
      FAILED_URLS_ALL+=("$URL_ITEM")
    fi
  done < "$URLS_FILE"

  # Retry failed once for this playlist
  if [[ -s "$FAILED_FILE" ]]; then
    echo "▶ Retrying failed ones once for: $SAFE_NAME"
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
  echo "   - Archive: $ARCHIVE_FILE (prevents re-downloading)"
  echo "   - List: $TXT_FILE (title;url)"
done

echo
echo "=== All requested playlists processed ==="
if [[ "${#FAILED_URLS_ALL[@]}" -gt 0 ]]; then
  echo "Some URLs failed. Check *_failed.log (and *.retry.log if present) files per playlist."
else
  echo "All downloads completed without persistent failures ✅"
fi
