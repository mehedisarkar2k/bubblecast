# Changelog

## 1.2.2 — 2026-10-25

- Google Drive works out of the box: official releases include Bubblecast's own Google client, so **Connect Google Drive → Allow** is all a user does. No client file to pick or share.

## 1.2.1 — 2026-10-25

- The Google client file picker opens on the Desktop.

## 1.2.0 — 2026-10-25

- **Library window** (bar → film icon, menu-bar icon → Library…, and after every recording): thumbnails, length, size, search, sort, filters (Today, This Week, On Drive, Shared), play, rename, show in Finder, move to Trash, multi-select, storage summary.
- **Google Drive (optional)**: connect once with Google sign-in, then upload, share and copy a link, stop sharing, update the Drive copy (same link), remove from Drive, or delete everywhere. Each recording shows its cloud status. Optional automatic upload of new recordings; uploads that fail are retried every minute. Bubblecast only gets access to the files it creates (drive.file).
- Much smaller videos: HEVC at about 3.5 Mbps instead of about 25 Mbps (a 3-minute video drops from about 620 MB to about 80 MB).
- Automatic voice level: speech is lifted towards a normal spoken-video level, room noise is kept below a ceiling and pauses are turned down, so the boost does not bring up background noise.
- The camera bubble remembers its position; the default is a medium circle at the bottom-right.
- "Save recordings to…" in the menu-bar menu. Pick a Google Drive, iCloud Drive or Dropbox folder and their desktop app uploads new recordings. Videos are written locally first and moved there when finished; if the folder is unavailable they are kept in ~/Movies/Bubblecast.

## 1.0.0 — 2026-10-25

First release.

- Record a chosen display with microphone audio to a local H.264 MP4 (1080p, 30 fps).
- Camera bubble (circle, rounded square, 4:3; S / M / L) that can switch to full-screen camera while recording.
- Control bar with screen, camera and microphone pickers, 3-2-1 countdown, timer and red menu-bar indicator.
- Camera settings popup with live preview, filters and macOS Video Effects for backgrounds.
- Global shortcuts: ⌥⇧R record, ⌥⇧M camera, ⌥⇧F full-screen camera.
- First-launch setup window for camera, microphone and screen recording permissions.
- Installer package that installs into Applications and opens the app.
