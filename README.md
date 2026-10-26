# Quitty

On macOS, clicking the red ✕ only closes the window. The app keeps running in the background (the dot under its Dock icon). Quitty changes that: **when you close an app's last window, Quitty quits the app**, just like ⌘Q.

- Minimizing (yellow button) and hiding (⌘H) **don't** quit the app, because its windows still exist.
- Quitting works like ⌘Q, so apps still ask you to save unsaved changes.
- Finder is never quit, and neither are menu bar apps (apps without a Dock icon).
- You can add your own exceptions from the menu, e.g. Music or Spotify, so they keep playing without a window.
- Apps get a few seconds of protection after launch, so a splash screen closing doesn't quit them before the main window opens.

Requires macOS 13 (Ventura) or later. Runs natively on Apple Silicon and Intel.

## Download

**[⬇ Download Quitty.zip](https://github.com/KubaCh7/quitty-macos/releases/latest/download/Quitty.zip)** (latest release)

All versions are on the [Releases](https://github.com/KubaCh7/quitty-macos/releases) page.

1. Unzip it and move `Quitty.app` to your **Applications** folder.
2. Quitty isn't signed with an Apple Developer certificate, so macOS blocks it the first time you open it. Right-click the app and choose **Open**, or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Quitty.app
   ```
3. Grant Accessibility access (see below).

## Accessibility permission

Quitty needs Accessibility access to see when you close other apps' windows:

**System Settings → Privacy & Security → Accessibility →** turn on **Quitty**.

macOS asks for this when Quitty starts. Quitty starts working as soon as you turn the switch on, without a restart.

> After updating or rebuilding Quitty, macOS may stop recognizing it because its signature changed. If that happens, remove Quitty from the Accessibility list (the "−" button) and add it again.

## Menu

Click the ✕ icon in the menu bar:

| Item | What it does |
|---|---|
| Quit apps when their last window closes | Turns Quitty on or off |
| Never quit | Pick apps Quitty should leave alone, or add one from Applications |
| Launch at login | Starts Quitty when you log in |
| Quit Quitty | Quits Quitty itself |

The icon is grayed out when Quitty is turned off or doesn't have Accessibility access.

## Building from source

You need Xcode or the Command Line Tools (`xcode-select --install`):

```sh
git clone https://github.com/KubaCh7/quitty-macos.git
cd quitty-macos
./scripts/build-app.sh
cp -R build/Quitty.app /Applications/
open /Applications/Quitty.app
```

`UNIVERSAL=1 ./scripts/build-app.sh` builds for both Apple Silicon and Intel (needs full Xcode).

## Publishing a release

Push a tag that starts with `v`. GitHub Actions builds the app and attaches `Quitty.zip` to a new release:

```sh
git tag v1.0.0
git push origin v1.0.0
```

## How it works

Quitty lives in the menu bar and uses the Accessibility API (`AXObserver`) to watch the windows of every running app. When a window disappears, Quitty waits 0.6 s, because some apps briefly destroy and recreate windows (for example when entering full screen). Then it checks the app's window list again. If the list is empty, Quitty calls `terminate()`, which is the same as choosing Quit.

The code is in `Sources/Quitty/`:

- `AppWatcher.swift` watches the windows of one app.
- `QuitController.swift` keeps track of running apps and decides whether to quit one.
- `AppDelegate.swift` handles the menu bar item and the Accessibility permission.
- `Settings.swift` stores preferences and exceptions.
