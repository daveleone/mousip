<div align="center">

<img src="Resources/icon.png" width="160" alt="Mousip icon">

# Mousip

**Switch Spaces with your mouse's tilt wheel, like swiping on a Magic Mouse.**

[![Build](https://github.com/daveleone/mousip/actions/workflows/release.yml/badge.svg)](https://github.com/daveleone/mousip/actions/workflows/release.yml)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![No Xcode required](https://img.shields.io/badge/Xcode-not%20required-6A3DF0)
![Menu bar app](https://img.shields.io/badge/lives%20in-the%20menu%20bar-2B5BFF)

</div>

---

Mousip is a tiny menu bar app for mice with a tilting scroll wheel. Tilt the wheel right or left
and you move to the next or previous Space: desktops and full-screen apps alike.
Optionally, a middle click on an empty spot opens Mission Control.

Built for the **HP 480 Comfort Bluetooth Mouse**, it works with any mouse that reports wheel tilt
as horizontal scrolling (HID "AC Pan").

## ✨ Features

- **Tilt to switch Spaces.** One tilt is one Space, however many events the mouse sends.
- **Middle click for Mission Control** *(optional).* Only on empty spots: middle clicks on links,
  tabs, buttons and text keep working as usual.
- **Your shortcuts, respected.** Mousip posts the system "Move left/right a space" shortcuts,
  reading your custom bindings if you changed them.
- **Trackpads and Magic Mouse untouched.** Only notched scroll wheels are intercepted.
- **Sideways scrolling on demand.** Hold <kbd>⌥</kbd> while tilting to scroll horizontally as usual.

## 🚀 Install

Paste this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/daveleone/mousip/main/scripts/install.sh | sh
```

It downloads the [latest release](https://github.com/daveleone/mousip/releases/latest), installs it in
`/Applications` and launches it. Run it again to update. No Gatekeeper prompt: files downloaded with
`curl` aren't quarantined the way browser downloads are.

On first launch macOS asks for the **Accessibility** permission
(System Settings › Privacy & Security › Accessibility). As soon as you grant it, Mousip turns on by itself.

<details>
<summary>Prefer downloading the DMG from the browser?</summary>

Grab `Mousip.dmg` from the [releases page](https://github.com/daveleone/mousip/releases/latest) and drag
Mousip to Applications. Unless the release is notarized, macOS will say it can't verify the developer
the first time: open **System Settings › Privacy & Security**, scroll down and click **Open Anyway**.
Or clear the quarantine flag yourself:

```sh
xattr -dr com.apple.quarantine /Applications/Mousip.app
```

</details>

## 🛠️ Build from source

You only need the Command Line Tools (Swift 6), not Xcode.

| Command | What it does |
| --- | --- |
| `./build.sh` | Builds `build/Mousip.app` |
| `./build.sh run` | Builds and launches from `build/` |
| `./build.sh install` | Builds, copies to `/Applications` and launches |
| `scripts/package.sh` | Packs the built app into `build/Mousip.zip` and `build/Mousip.dmg` |

> [!NOTE]
> Local builds are signed ad-hoc, so every rebuild invalidates the Accessibility permission:
> `run` and `install` reset it (`tccutil reset Accessibility com.mousip.app`) and the app asks again.
> To keep it across rebuilds, sign with a stable certificate:
> `SIGN_IDENTITY="Certificate name" ./build.sh install`.

## 🖱️ The menu

Click the Mousip icon (three side-by-side panels) in the menu bar.

| Item | |
| --- | --- |
| **Enabled** | Pauses or resumes everything. The icon turns gray while paused. |
| **Invert Direction** | For when tilting right takes you left. |
| **Repeat While Held** | Keeps switching Spaces every 0.45 s while the wheel stays tilted. |
| **Middle Click for Mission Control** | Opens Mission Control on a middle click on an empty spot. Off by default. |
| **Launch at Login** | Starts Mousip when you log in. |

If something needs your attention (missing permission, disabled shortcuts) a ⚠︎ item at the top
takes you straight to the right settings page.

**Hold <kbd>⌥</kbd> while opening the menu** for the extras:

- **Test** › Space Left / Space Right / Mission Control: checks the shortcuts without the mouse.
- **Debug Logging**: logs every scroll event and every middle click target. To read it:

  ```sh
  log stream --predicate 'subsystem == "com.mousip.app"'
  ```

## 🪟 Middle click for Mission Control

A middle click often means something: open a link in a new tab, close a tab, paste in a terminal.
So Mousip looks at the cursor and asks the Accessibility API what's under it, and steps in only if it's empty space:

| Under the cursor | Middle click |
| --- | --- |
| Anything showing the pointing-hand cursor (links, in any browser) | Passed to the app as usual |
| Link, tab, button, menu, Dock icon, text field | Passed to the app as usual |
| Page background, plain text, window background, desktop | Opens Mission Control |
| Anything, with <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>⌥</kbd> or <kbd>⌃</kbd> held | Passed to the app as usual |
| An app that doesn't answer | Passed to the app as usual |

Middle **drags** (panning a canvas in Figma, Blender, maps…) are recognized after a few points of
movement and replayed to the app, so they keep working.

> [!TIP]
> Chrome doesn't expose web pages to Accessibility unless a screen reader is running, so to Mousip
> a link there looks like an empty area. That's why the pointing-hand cursor is checked first:
> it works in every browser and web app without slowing them down.

## ⚙️ How it works

1. A `CGEventTap` intercepts scroll events. Only **horizontal** events from notched
   scroll wheels (`isContinuous == 0`) are considered: trackpads and the Magic Mouse are left alone.
2. A burst of events from the same tilt counts as a single gesture
   (0.3 s pause between one gesture and the next).
3. For each gesture it posts the Mission Control shortcut "Move left/right a space"
   (<kbd>⌃←</kbd> / <kbd>⌃→</kbd> by default), read from `com.apple.symbolichotkeys`.
4. Handled horizontal events are consumed, so apps don't scroll sideways.
   With <kbd>⌥</kbd> (or <kbd>⇧</kbd>) held, they pass through untouched.
5. A second tap watches the middle button. On press it checks whether the cursor is the pointing hand
   (`NSCursor.currentSystem`), then hit-tests the element under the cursor
   (`AXUIElementCopyElementAtPosition`) and walks up its ancestors looking for something clickable.
   If there's nothing, it swallows the click and opens Mission Control on release
   (by launching `Mission Control.app`, so it works whatever shortcut is assigned to it).

## 🩺 Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Nothing happens, the icon is grayed out | The Accessibility permission is missing, or the one from the previous build is still listed: remove it, add it again and restart the app. |
| "Test" doesn't switch Spaces | The "Move left/right a space" shortcuts are disabled (Keyboard › Keyboard Shortcuts › Mission Control). |
| A single tilt skips several Spaces | The mouse repeats the event at intervals longer than 0.3 s: increase `gestureGap` in `ScrollInterceptor.swift`. |
| The log never shows a non-zero `h=` | The mouse doesn't report tilt as horizontal scrolling (for example it sends buttons 4/5 instead). |
| A middle click on a link opens Mission Control | The link doesn't show the pointing hand and isn't exposed to Accessibility. Enable Debug Logging to see the cursor and the element roles under it, and add the missing role to `interactiveRoles` in `MiddleClickInterceptor.swift`. |
| A middle click on an empty spot does nothing | The app didn't answer in time, or the spot is inside a clickable element: check the log. |

## 🗂️ Project structure

```
Sources/Mousip/
├── AppDelegate.swift             menu bar icon, menu and permissions
├── EventTap.swift                shared CGEventTap wrapper
├── ScrollInterceptor.swift       tilt filtering and grouping into gestures
├── MiddleClickInterceptor.swift  middle click → Mission Control (cursor + Accessibility checks)
├── SpaceSwitcher.swift           reading and posting the system shortcuts
└── Settings.swift                preferences (UserDefaults)
Resources/
├── AppIcon.icns, icon.png        generated by scripts/make-icon.swift
└── Info.plist
scripts/
├── install.sh                    one-line installer (downloads the latest release)
├── package.sh                    zip + DMG of the built app
└── make-icon.swift               draws the app icon
.github/workflows/release.yml     CI build, signing, notarization and releases
```

To redraw the icon after editing `scripts/make-icon.swift`:

```sh
swift scripts/make-icon.swift
```
