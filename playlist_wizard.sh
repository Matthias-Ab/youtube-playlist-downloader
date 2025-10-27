#!/bin/bash
set -euo pipefail

# ==============================================
# YouTube Playlist Downloader Wizard (Ubuntu 24.04)
# ==============================================

# ---------- helpers ----------
msg() { echo -e "\033[1;36m$*\033[0m"; }
warn() { echo -e "\033[1;33m$*\033[0m"; }
err()  { echo -e "\033[1;31m$*\033[0m" >&2; }
confirm() {
  local prompt="${1:-Continue?} [y/N]: "
  read -rp "$prompt" ans || true
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

require_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Required command '$1' not found."
    return 1
  fi
}

sanitize_name() {
  printf '%s' "$1" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/_/g; s/_+/_/g; s/^_|_$//g'
}

# ---------- optional install ----------
msg "=== YouTube Playlist Downloader Wizard ==="
if confirm "Do you want me to install/update yt-dlp and ffmpeg now?"; then
  if [[ $EUID -ne 0 ]]; then
    warn "This step needs sudo rights."
  fi
  sudo apt update
  sudo apt install -y ffmpeg ca-certificates
  if dpkg -s yt-dlp >/dev/null 2>&1; then
    sudo apt remove -y yt-dlp || true
  fi
  sudo wget -q https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -O /usr/local/bin/yt-dlp
  sudo chmod a+rx /usr/local/bin/yt-dlp
  msg "yt-dlp version: $(/usr/local/bin/yt-dlp --version)"
fi

# ---------- sanity checks ----------
require_bin yt-dlp || { err "Install yt-dlp first."; exit 1; }
require_bin ffmpeg || { warn "ffmpeg not found. Audio/video extraction will fail."; }

# ---------- cookies (optional) ----------
COOKIES_ARG=""
msg "If playlists have hidden/age-restricted items, cookies help."
echo "Use cookies from browser?"
echo "  1) None (default)"
echo "  2) Chrome/Chromium"
echo "  3) Firefox"
read -rp "Choose [1-3]: " cookies_choice
case "${cookies_choice:-1}" in
  2) COOKIES_ARG="--cookies-from-browser chrome" ;;
  3) COOKIES_ARG="--cookies-from-browser firefox" ;;
  *) COOKIES_ARG="" ;;
esac

# ---------- export format ----------
echo
msg "Playlist export format (per playlist file):"
echo "  1) URL-only (.txt with one URL per line)  [recommended]"
echo "  2) title;url (archival-friendly)"
read -rp "Choose [1-2]: " export_choice
case "${export_choice:-1}" in
  2) EXPORT_MODE="title_url" ;;
  *) EXPORT_MODE="urls" ;;
esac

# ---------- download type ----------
echo
msg "What do you want to download?"
echo "  1) Audio only"
echo "  2) Video"
read -rp "Choose [1-2]: " dltype_choice
if [[ "${dltype_choice:-1}" == "2" ]]; then
  MODE="video"
else
  MODE="audio"
fi

AUDIO_FMT="mp3"
AUDIO_Q="0"
VIDEO_CONTAINER="mp4"
if [[ "$MODE" == "audio" ]]; then
  echo
  msg "Audio format:"
  echo "  1) mp3 (compatible)"
  echo "  2) m4a (no re-encode when possible, smaller)"
  echo "  3) opus (very efficient)"
  read -rp "Choose [1-3]: " afmt_choice
  case "${afmt_choice:-1}" in
    2) AUDIO_FMT="m4a" ;;
    3) AUDIO_FMT="opus" ;;
    *) AUDIO_FMT="mp3" ;;
  esac
else
  echo
  msg "Video container:"
  echo "  1) mp4 (widely compatible)"
  echo "  2) mkv (flexible)"
  read -rp "Choose [1-2]: " vfmt_choice
  case "${vfmt_choice:-1}" in
    2) VIDEO_CONTAINER="mkv" ;;
    *) VIDEO_CONTAINER="mp4" ;;
  esac
fi

# ---------- filename style ----------
echo
msg "Filename style:"
echo "  1) Terminal-friendly (safe ASCII, underscores)"
echo "  2) Keep spaces & Unicode (prettier names)"
read -rp "Choose [1-2]: " name_choice
if [[ "${name_choice:-1}" == "2" ]]; then
  RESTRICT_FLAG=()
else
  RESTRICT_FLAG=(--restrict-filenames)
fi

# ---------- network & retries ----------
echo
msg "Network / stability options:"
FORCE_IPV4_FLAG=()
if confirm "Force IPv4 (helpful on some ISPs)?"; then
  FORCE_IPV4_FLAG=(--force-ipv4)
fi

read -rp "How many retries per item? [default 5]: " retries
RETRIES="${retries:-5}"

# ---------- parallelism ----------
echo
msg "Parallel processing:"
read -rp "How many playlists to process concurrently? [0 = sequential, e.g., 2]: " par
PARALLEL="${par:-0}"
if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]]; then PARALLEL=0; fi

# ---------- collect playlist URLs ----------
echo
read -rp "How many playlist URLs will you enter? " COUNT
if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
  err "Please enter a positive integer."
  exit 1
fi

declare -a PLAYLIST_URLS=()
for ((i=1; i<=COUNT; i++)); do
  read -rp "Enter playlist URL #$i: " PURL
  PURL="$(echo "$PURL" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -z "$PURL" ]] && { warn "Empty URL, skipping this slot."; continue; }
  PLAYLIST_URLS+=("$PURL")
done

# ---------- functions ----------
get_playlist_title() {
  local url="$1"
  local title=""
  if ! title="$(yt-dlp $COOKIES_ARG --flat-playlist --playlist-end 1 --print "%(playlist_title)s" "$url" 2>/dev/null | head -n1)"; then
    title=""
  fi
  title="$(echo "$title" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [[ -z "$title" || "$title" == "NA" ]]; then
    local fb
    fb="$(yt-dlp $COOKIES_ARG --flat-playlist --playlist-end 1 --print "%(uploader)s_%(playlist_id)s" "$url" 2>/dev/null | head -n1)"
    [[ -z "$fb" || "$fb" == "NA" ]] && fb="youtube_playlist_$(date +%s)"
    title="$fb"
  fi
  echo "$title"
}

export_playlist_urls() {
  local url="$1" ; local outfile="$2"
  yt-dlp $COOKIES_ARG --flat-playlist --print "%(webpage_url)s" "$url" \
    | sed '/^[[:space:]]*$/d' \
    | awk '!seen[$0]++' \
    > "$outfile"
}

export_playlist_title_url() {
  local url="$1" ; local outfile="$2"
  yt-dlp $COOKIES_ARG --flat-playlist --print "%(title)s;%(webpage_url)s" "$url" \
    | sed '/^[[:space:]]*$/d' \
    > "$outfile"
}

download_one_audio() {
  local url="$1" ; local outdir="$2" ; local archive="$3"
  yt-dlp $COOKIES_ARG \
    -f "ba" \
    --extract-audio --audio-format "$AUDIO_FMT" --audio-quality "$AUDIO_Q" \
    --download-archive "$archive" \
    --no-overwrites \
    --continue \
    --retries "$RETRIES" \
    "${RESTRICT_FLAG[@]}" \
    "${FORCE_IPV4_FLAG[@]}" \
    -o "$outdir/%(title)s.%(ext)s" \
    "$url"
}

download_one_video() {
  local url="$1" ; local outdir="$2" ; local archive="$3"
  yt-dlp $COOKIES_ARG \
    -f "bv*+ba/b" \
    --merge-output-format "$VIDEO_CONTAINER" \
    --download-archive "$archive" \
    --no-overwrites \
    --continue \
    --retries "$RETRIES" \
    "${RESTRICT_FLAG[@]}" \
    "${FORCE_IPV4_FLAG[@]}" \
    -o "$outdir/%(title)s.%(ext)s" \
    "$url"
}

process_playlist() {
  local PURL="$1"
  echo
  msg "▶ Extracting playlist title…"
  local PTITLE SAFE_NAME
  PTITLE="$(get_playlist_title "$PURL")"
  SAFE_NAME="$(sanitize_name "$PTITLE")"
  [[ -z "$SAFE_NAME" ]] && SAFE_NAME="youtube_playlist_$(date +%s)"

  local OUT_DIR="$SAFE_NAME"
  local ARCHIVE_FILE="${SAFE_NAME}.archive"
  local FAILED_FILE="${SAFE_NAME}_failed.log"
  local LIST_FILE="${SAFE_NAME}.txt"

  echo "▶ Folder: $OUT_DIR"
  mkdir -p "$OUT_DIR"
  : > "$FAILED_FILE"

  echo "▶ Exporting playlist → $LIST_FILE"
  if [[ "$EXPORT_MODE" == "title_url" ]]; then
    export_playlist_title_url "$PURL" "$LIST_FILE"
    EXTRACT_URL_CMD=(cut -d ';' -f 2-)
  else
    export_playlist_urls "$PURL" "$LIST_FILE"
    EXTRACT_URL_CMD=(cat)
  fi

  local TOTAL
  TOTAL=$(wc -l < "$LIST_FILE" | tr -d ' ')
  echo "▶ Found $TOTAL items."
  if [[ "$TOTAL" -eq 0 ]]; then
    warn "No items found, skipping."
    return 0
  fi

  echo "▶ Downloading into $OUT_DIR …"
  local n=0
  while IFS= read -r URL_ITEM; do
    n=$((n+1))
    [[ -z "$URL_ITEM" ]] && continue
    URL_ITEM="$("${EXTRACT_URL_CMD[@]}" <<<"$URL_ITEM")"
    echo "[$n/$TOTAL] $URL_ITEM"
    if [[ "$MODE" == "audio" ]]; then
      if ! download_one_audio "$URL_ITEM" "$OUT_DIR" "$ARCHIVE_FILE"; then
        echo "$URL_ITEM" | tee -a "$FAILED_FILE"
      fi
    else
      if ! download_one_video "$URL_ITEM" "$OUT_DIR" "$ARCHIVE_FILE"; then
        echo "$URL_ITEM" | tee -a "$FAILED_FILE"
      fi
    fi
  done < "$LIST_FILE"

  if [[ -s "$FAILED_FILE" ]]; then
    msg "▶ Retrying failed once for: $SAFE_NAME"
    mapfile -t FAILED_LIST < "$FAILED_FILE"
    : > "${FAILED_FILE}.retry.log"
    for U in "${FAILED_LIST[@]}"; do
      echo "Retry: $U"
      if [[ "$MODE" == "audio" ]]; then
        download_one_audio "$U" "$OUT_DIR" "$ARCHIVE_FILE" || echo "$U" >> "${FAILED_FILE}.retry.log"
      else
        download_one_video "$U" "$OUT_DIR" "$ARCHIVE_FILE" || echo "$U" >> "${FAILED_FILE}.retry.log"
      fi
    done
    if [[ -s "${FAILED_FILE}.retry.log" ]]; then
      warn "Some items still failed. See: ${FAILED_FILE}.retry.log"
    else
      echo "All previously failed items downloaded on retry ✅"
      rm -f "$FAILED_FILE" "${FAILED_FILE}.retry.log" 2>/dev/null || true
    fi
  fi

  echo "✔ Finished: $PTITLE"
  echo "   - Folder: $OUT_DIR/"
  echo "   - Archive: $ARCHIVE_FILE"
  echo "   - List:    $LIST_FILE"
}

# ---------- dispatch (sequential or parallel) ----------
msg "Starting ${#PLAYLIST_URLS[@]} playlist(s)…"
if [[ "$PARALLEL" -gt 0 ]]; then
  warn "Running up to $PARALLEL playlist(s) in parallel…"
  running=0
  pids=()
  for PURL in "${PLAYLIST_URLS[@]}"; do
    ( process_playlist "$PURL" ) &
    pids+=($!)
    running=$((running+1))
    if [[ "$running" -ge "$PARALLEL" ]]; then
      wait -n
      running=$((running-1))
    fi
  done
  for pid in "${pids[@]}"; do wait "$pid"; done
else
  for PURL in "${PLAYLIST_URLS[@]}"; do
    process_playlist "$PURL"
  done
fi

msg "=== All done. Happy archiving! ==="
