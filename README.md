# Quitty

On macOS, clicking the red ✕ only closes the window. The app keeps running in the background (the dot under its Dock icon). Quitty changes that: **when you close an app's last window, Quitty quits the app**, just like ⌘Q.

- Minimizing (yellow button), full screen and zoom (green button) and hiding (⌘H) **don't** quit the app, because its windows still exist.
- Quitting works like ⌘Q, so apps still ask you to save unsaved changes.
- Finder is never quit, and neither are menu bar apps (apps without a Dock icon).
- You can add your own exceptions from the menu, e.g. Music or Spotify, so they keep playing without a window.
- Apps get a few seconds of protection after launch, so a splash screen closing doesn't quit them before the main window opens.
- Quitty updates itself from GitHub Releases.
- The menu bar panel and update window use Liquid Glass on macOS 26 Tahoe. On macOS 12–15 they fall back to standard translucent materials.

Requires macOS 12 (Monterey) or later. Runs natively on Apple Silicon and Intel.

## Download

**[⬇ Download Quitty.dmg](https://github.com/KubaCh7/quitty-macos/releases/latest/download/Quitty.dmg)** (latest release)

All versions are on the [Releases](https://github.com/KubaCh7/quitty-macos/releases) page.

1. Open `Quitty.dmg` and drag **Quitty** onto the **Applications** folder in the window that appears.
2. Open Quitty from Applications. It isn't signed with an Apple Developer certificate, so macOS blocks it the first time:
   - macOS 15 and later: open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Quitty.
   - macOS 12–14: right-click Quitty, choose **Open**, then **Open** again.

   Or run `xattr -dr com.apple.quarantine /Applications/Quitty.app` in Terminal.
3. Grant Accessibility access (see below).

If you open Quitty from the disk image or from Downloads instead, it offers to move itself to Applications and ejects the disk image afterwards.

## Accessibility permission

Quitty needs Accessibility access to see when you close other apps' windows:

**System Settings → Privacy & Security → Accessibility →** turn on **Quitty**.

macOS asks for this when Quitty starts. Quitty starts working as soon as you turn the switch on, without a restart.

> **Quitty is switched on in Accessibility but still says it needs access?** macOS is holding a stale entry from an older copy, which is common with v1.0.0. Click **Already on? Reset** in the Quitty panel, then turn Quitty on again in System Settings. You can do the same in Terminal with `tccutil reset Accessibility com.kubach7.quitty`.

## The Quitty panel

Click the ✕ icon in the menu bar to open the panel:

- **Switch at the top:** turns Quitty on or off.
- **Never quit:** a switch for every running app. Turn one on to keep that app running without windows. **Add App…** picks an app from Applications.
- **Launch at login** and **Check for updates automatically.**
- **Updates:** shows whether a newer version exists. **Check** asks GitHub right away.
- **Quit Quitty** (⌘Q).

The icon is filled while Quitty is active and outlined when it is paused or doesn't have Accessibility access.

## Updates

Quitty checks GitHub Releases once a day (and a few seconds after it starts). When a newer version is out, a window shows the release notes:

- **Install and Relaunch** downloads `Quitty.zip`, replaces the app in place and starts the new version.
- **Later** closes the window. The update stays available in the panel.
- **Skip This Version** stops automatic checks from offering that version again.

Quitty needs to run from a folder it can write to, such as Applications. If macOS runs it from a temporary location (this happens to apps opened straight from Downloads), the update asks you to move Quitty to Applications first.

Version 1.0.0 doesn't have the updater, so download 1.1.0 or later manually once. After that, updates install from inside the app.

## Building from source

You need Xcode or the Command Line Tools (`xcode-select --install`):

```sh
git clone https://github.com/KubaCh7/quitty-macos.git
cd quitty-macos
./scripts/build-app.sh
cp -R build/Quitty.app /Applications/
open /Applications/Quitty.app
```

`UNIVERSAL=1 ./scripts/build-app.sh` builds for both Apple Silicon and Intel (needs full Xcode). `./scripts/build-dmg.sh` then packs `build/Quitty.dmg`. The icon and the disk image background are drawn by `scripts/make-assets.py`.

## Publishing a release

Bump `CFBundleShortVersionString` in `Resources/Info.plist` and push to the default branch. GitHub Actions builds the app and publishes `Quitty.dmg` and `Quitty.zip` as release `v<version>`. Pushes that keep the same version don't create a new release.

You can also push a tag that starts with `v` (for example `git tag v1.0.1 && git push origin v1.0.1`).

## How it works

Quitty lives in the menu bar and uses the Accessibility API (`AXObserver`) to watch the windows of every running app. When a window closes, Quitty reads the app's window list and confirms it once more about 0.2 s later, because some apps briefly swap one window for another. If no windows are left, Quitty calls `terminate()`, which is the same as choosing Quit.

What counts as an open window:

- Normal windows and dialogs, including ones on other Spaces, minimized windows and full screen windows.
- Windows of other types (Steam's windows are like this) count only while they are visible on screen.
- Floating palettes never count.

After a window moves or resizes, or after you switch Spaces, Quitty waits 1.5 s before quitting anything. Entering full screen or zooming empties an app's window list for a moment, and this pause keeps the app from being quit.

Some apps don't send every Accessibility notification, so Quitty also checks the frontmost app's windows every 0.3 s.

The code is in `Sources/Quitty/`:

- `AppWatcher.swift` watches the windows of one app.
- `QuitController.swift` keeps track of running apps and decides whether to quit one.
- `AppModel.swift` holds the panel's state, the Accessibility permission and the exceptions.
- `Updater.swift` checks GitHub Releases and installs updates.
- `Views/` contains the SwiftUI panel, the update window and the Liquid Glass helpers.
- `Settings.swift` stores preferences.
