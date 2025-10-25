# YouTube Playlist → MP3/Audio/Video Downloader (Ubuntu)

Two scripts to archive YouTube playlists cleanly and reliably on Ubuntu 24.04:

* `interactive_multi_playlist.sh` — fast, focused: **URL-only .txt** per playlist + MP3 downloads.
* `playlist_wizard.sh` — full **guided wizard**: installs deps, picks audio/video formats, cookies, filename style, retries, and **parallel** processing.

Both scripts use the excellent [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) under the hood and organize downloads into per-playlist folders with a per-playlist archive (prevents re-downloading).

---

## Features

* **Multiple playlists** in one run (paste all URLs up front).
* **Per-playlist folders** and **per-playlist .txt** export:

  * `interactive_multi_playlist.sh`: URL-only (one URL per line).
  * `playlist_wizard.sh`: choose URL-only **or** `title;url`.
* **Terminal-friendly names** (lowercase + underscores) by default; pretty Unicode optional.
* **Skip already downloaded** using per-playlist download archive files.
* **MP3** by default; wizard lets you choose **m4a/opus** (audio) or **mp4/mkv** (video).
* **Robustness**: optional cookies (Chrome/Firefox), force IPv4, configurable retries.
* **Logging**: per-playlist `*_failed.log` (+ one retry pass).
* **Parallel playlists** (wizard): process N playlists concurrently.

---

## Requirements

* Ubuntu 24.04 LTS (or similar Linux)
* `bash`, `ffmpeg`, `yt-dlp`

> Tip: The Ubuntu apt package for `yt-dlp` can lag behind. Prefer the official standalone binary.

### Install / Update Dependencies

```bash
sudo apt update
sudo apt install -y ffmpeg ca-certificates
# Remove old yt-dlp from apt if present (often outdated)
sudo apt remove -y yt-dlp || true
# Install latest yt-dlp from GitHub
sudo wget https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -O /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp

yt-dlp --version   # should show a 2024/2025 version
```

The wizard script can perform these steps for you interactively.

---

## Quick Start

### 1) Clone / copy scripts

Place both scripts in a working directory (e.g., `~/Documents/Projects/yt-music-downloader/`).

```
interactive_multi_playlist.sh
playlist_wizard.sh
```

Make them executable:

```bash
chmod +x interactive_multi_playlist.sh playlist_wizard.sh
```

### 2) Run the simple multi-playlist downloader (MP3, URL-only)

```bash
./interactive_multi_playlist.sh
```

* Enter how many playlist URLs you have.
* Paste each URL.
* The script will:

  * auto-detect playlist title,
  * create `playlist_name/` folder,
  * export `playlist_name.txt` (URL-only),
  * download MP3s into `playlist_name/`,
  * maintain `playlist_name.archive` to skip duplicates.

### 3) Or run the full wizard

```bash
./playlist_wizard.sh
```

You’ll be guided to choose:

* Install/update `yt-dlp` & `ffmpeg`
* Audio vs Video
* MP3 / M4A / Opus (or MP4 / MKV)
* Filename style (safe ASCII or pretty Unicode)
* Cookies (Chrome/Firefox) if playlists hide items
* IPv4 only, retry count
* **Parallel playlists** (e.g., 2 at a time)
* Export format: URL-only **or** `title;url`

---

## Output Layout

For a playlist titled “Old Ethiopian Classics”, you’ll get:

```
old_ethiopian_classics/           # all files for this playlist
old_ethiopian_classics.txt        # URL list (or title;url if chosen in wizard)
old_ethiopian_classics.archive    # prevents re-downloading already done items
old_ethiopian_classics_failed.log # only if there are failures
old_ethiopian_classics_failed.log.retry.log # retry results (if needed)
```

Audio/video files are named with the video title (safe or pretty, based on your choice).

---

## Usage Examples

### Basic: Download 3 playlists as MP3 (URL-only list)

```bash
./interactive_multi_playlist.sh
# How many playlists? > 3
# Paste all three URLs when asked
```

### Wizard: Download audio in **m4a**, pretty filenames, with cookies from Chrome, 2 playlists in parallel

```bash
./playlist_wizard.sh
# Install/update deps? -> Yes
# Cookies? -> Chrome
# Export format? -> URL-only (recommended)
# What to download? -> Audio
# Audio format? -> m4a
# Filename style? -> Keep spaces & Unicode
# Force IPv4? -> Optional; choose based on your ISP
# Retries? -> e.g., 5
# Parallel playlists? -> 2
# How many URLs? -> Enter count, then paste them all
```

### Re-running later to fetch only new items

Just run either script again with the same playlists. Already-downloaded items are skipped thanks to the `*.archive` file.

---

## Advanced Notes

* **Cookies**: If YouTube hides age-restricted/unlisted-in-playlist items, choose cookies from your browser:

  * Chrome/Chromium: `--cookies-from-browser chrome`
  * Firefox: `--cookies-from-browser firefox`
    The wizard adds this automatically when you choose it.
* **Force IPv4**: Some ISPs have flaky IPv6 → enabling IPv4 may help (`--force-ipv4`).
* **Retries**: Wizard lets you set `--retries N`. The script also retries **failed items once** at the end.
* **Parallelism** (wizard only): Run multiple playlists concurrently (e.g., `-j 2`). Each playlist still downloads items sequentially for stability.

---

## Troubleshooting

**“Found 0 items” when exporting a playlist**

* Use the **latest** `yt-dlp` (see install steps).
* Some playlists hide items unless you’re signed in—enable **cookies** in the wizard.
* Verify quickly:

  ```bash
  yt-dlp --flat-playlist --print "%(webpage_url)s" "PASTE_PLAYLIST_URL" | head
  ```

  If you see URLs, the exporter works.

**`nsig` / signature extraction errors**

* Update `yt-dlp` to the newest release.

**Downloads are slow / throttled**

* Keep `yt-dlp` up to date.
* Consider running fewer parallel playlists.
* Try `--force-ipv4`.

**File names look odd (underscores)**

* Choose “Keep spaces & Unicode” in the wizard (removes `--restrict-filenames`).

**Already-downloaded videos are re-downloading**

* Make sure the `*.archive` file sits next to the playlist’s folder and stays intact.
* Don’t delete/modify it if you want to preserve skip behavior.

---

## FAQ

**Q: Can I export `title;url` instead of URL-only?**
A: Yes — the wizard offers this. The simple script is URL-only by design.

**Q: Can I download video instead of audio?**
A: Yes — use the wizard and choose **Video** (mp4 or mkv).

**Q: Can I run playlists while I do other things?**
A: Yes — both scripts collect **all URLs first**, then run unattended. The wizard also supports parallel playlists.

---

## Security / Legal

* Respect YouTube’s Terms of Service and local laws. Only download content you have the rights to archive.
* Cookies are read from your local browser on your machine when you opt in; they’re not transmitted anywhere by these scripts beyond `yt-dlp`’s local use.

---

## Changelog (high-level)

* **v2 (wizard)**: Add guided setup; choose audio/video formats; cookies; filename style; retries; IPv4; parallel playlists.
* **v1 (simple)**: Multi-playlist, URL-only export, MP3 downloads, per-playlist archives/logs, interactive batch input.

---

## Acknowledgments

* Built on top of [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) — huge thanks to the maintainers and contributors.
* Uses `ffmpeg` for audio extraction and muxing.

---
