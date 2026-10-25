<p align="center"><img src="docs/icon.png" width="128" alt="Bubblecast icon"></p>

<h1 align="center">Bubblecast</h1>

<p align="center">Record your screen with your camera in a bubble. Everything stays on your Mac.</p>

Bubblecast is a small, native macOS screen recorder. It records the screen you choose, your microphone, and your camera in a draggable bubble (or full screen), and saves an MP4 to your Mac. No account is needed and nothing leaves your Mac unless you connect Google Drive and upload a recording.

## Features

- **Screen + camera bubble**: record any display with your camera in a circle, rounded square or 4:3 bubble (S / M / L).
- **Full-screen camera**: switch between the bubble and a full-screen camera with one click, a double-click on the bubble, or ⌥⇧F, even while recording.
- **One control bar**: pick the screen, camera and microphone, then start. A 3-2-1 countdown, a pulsing timer and a red menu-bar icon show that you are recording.
- **Camera settings**: live preview, size, shape, filters (Warm, Cool, Mono, Bright, Vivid) and macOS Video Effects for background blur or replacement.
- **Private by design**: recordings go to `~/Movies/Bubblecast/<date>/<time>.mp4`, or a folder you choose, and nowhere else. The control bar never appears in the video.
- **Small files, clear voice**: HEVC video at about 3.5 Mbps (about 80 MB for 3 minutes) and an automatic voice level that keeps room noise down in pauses.
- **Cloud backup if you want it**: menu-bar icon → **Save recordings to…** and pick a folder inside Google Drive (with Google Drive for desktop), iCloud Drive or Dropbox.
- **Library**: every recording with a thumbnail, length, size and cloud status. Play, rename, search, sort, move to Trash.
- **Google Drive, optional**: connect once, then upload, share a link, stop sharing, update or remove a video from the Library. Bubblecast can only see the files it uploads.
- **Guided setup**: on first launch Bubblecast asks for every permission it needs, so recording never stops on a prompt.

## Requirements

- macOS 15 Sequoia or later (Apple silicon or Intel)
- A camera and microphone (built-in or external)

## Install

1. Download **`Bubblecast-<version>.pkg`** from the [latest release](../../releases/latest).
2. Double-click it and follow the installer. Bubblecast is installed into **Applications** and opens by itself.
3. The first time only, macOS may say it cannot check the developer, because the app is not notarized by Apple. Open **System Settings → Privacy & Security** and click **Open Anyway**, then run the installer again.

## First launch

Bubblecast opens a **Set up Bubblecast** window:

1. **Camera → Allow** and **Microphone → Allow**.
2. **Screen Recording → Allow**. System Settings opens; turn on **Bubblecast**.
3. Click **Restart Bubblecast** (macOS applies the screen permission only after a restart), then **Continue**.

You can open this window again from the menu-bar icon → **Permissions…**. Permissions are asked once per Mac and are kept across updates.

## Use

| Action | How |
|---|---|
| Start / stop recording | **Start recording** on the bar, or ⌥⇧R |
| Camera on / off | Camera menu on the bar, or ⌥⇧M |
| Full-screen camera | Double-click the bubble, the ⤢ button while recording, or ⌥⇧F |
| Camera size, shape, filter, background | ⚙︎ button next to the Camera menu |
| Hide the bar | × on the bar (click the Dock icon to bring it back) |
| Open recordings | Menu-bar icon → **Open recordings folder** |
| Change the save folder (e.g. Google Drive) | Menu-bar icon → **Save recordings to…** |
| Quit | ⌘Q, or menu-bar icon → **Quit** |

Only microphone audio is recorded (no system audio). The bubble is a real window on the recorded screen, so it stays inside that screen, and it remembers where you put it.

## Library and Google Drive

Open the Library from the film icon on the bar, the menu-bar icon → **Library…**, or after any recording. Right-click a recording for every action.

| Badge | Meaning |
|---|---|
| On this Mac | only local |
| Uploading 45% / Waiting to upload | upload in progress or paused (retried every minute) |
| On Drive | backed up, private |
| Shared | anyone with the link can view |
| Drive copy out of date | the local file changed after the upload; choose **Update on Drive** |
| Missing on Drive | the Drive copy was deleted in Drive |

**Connect Google Drive** (toolbar) opens Google sign-in in your browser once. Bubblecast asks only for the `drive.file` permission, so it can see only the files it creates, in a **Bubblecast** folder. The sign-in is stored in the macOS Keychain; **Disconnect** removes it. Uploads go to Drive; the local file always stays.

The first **Connect** asks for your Google OAuth client file (a "Desktop app" JSON from Google Cloud) and keeps it in the Keychain. Public releases contain no Google client; see [docs/google-drive-setup.md](docs/google-drive-setup.md) to create one.

## Uninstall

1. Quit Bubblecast and move **/Applications/Bubblecast.app** to the Trash.
2. Optional: remove it from **System Settings → Privacy & Security → Screen & System Audio Recording** (and Camera, Microphone) with the **−** button.
3. Your recordings stay in `~/Movies/Bubblecast` until you delete them.

## Build from source

Requires Xcode 16 or later (Swift 6, macOS 15 SDK).

```sh
git clone https://github.com/mehedisarkar2k/bubblecast.git
cd bubblecast
bash scripts/release.sh            # builds, signs and packages
open dist/Bubblecast-*.pkg         # install
```

- `scripts/build-app.sh` builds `.build/package/Bubblecast.app` and signs it with the first certificate it finds ("Developer ID Application", "Apple Development", or a self-signed "Bubblecast Dev"; override with `BUBBLECAST_SIGN_IDENTITY`). Without one it signs ad-hoc with a bundle-identifier requirement, so permissions still carry over between builds.
- `scripts/make-pkg.sh` makes the installer in `dist/`. It quits a running copy before installing and opens the app afterwards.
- `scripts/make-icon.swift` draws the app icon; `Resources/AppIcon.icns` is made from it with `sips` and `iconutil`.

## License

[MIT](LICENSE) © 2026 Mehedi Hasan Sarkar
