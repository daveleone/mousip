# Mousip

A macOS menu bar app: tilt your mouse's scroll wheel right or left to move to the next
or previous Space (virtual desktops and full-screen apps), like swiping on a Magic Mouse.

Built for the HP 480 Comfort Bluetooth Mouse, but it works with any mouse that reports
wheel tilt as horizontal scrolling (HID "AC Pan").

## How it works

1. A `CGEventTap` intercepts scroll events. Only **horizontal** events from notched
   scroll wheels (`isContinuous == 0`) are considered: trackpads and the Magic Mouse are left alone.
2. A burst of events from the same tilt counts as a single gesture
   (0.3 s pause between one gesture and the next).
3. For each gesture it posts the Mission Control shortcut "Move left/right a space"
   (⌃← / ⌃→ by default), read from `com.apple.symbolichotkeys`, so customized shortcuts are respected.
4. Handled horizontal events are consumed, so apps don't scroll sideways.
   With ⌥ (or ⇧) held, they pass through untouched.

## Building

The Command Line Tools (Swift 6) are enough; Xcode is not required.

```sh
./build.sh            # creates build/Mousip.app
./build.sh run        # build and launch
./build.sh install    # copy to /Applications and launch
```

On first launch macOS asks for the **Accessibility** permission
(System Settings › Privacy & Security › Accessibility). As soon as you grant it, the app activates on its own.

The signature is ad-hoc, so every rebuild invalidates the permission: `run` and `install` reset it
(`tccutil reset Accessibility com.mousip.app`) and the app asks again. To avoid granting it
every time, sign with a stable certificate: `SIGN_IDENTITY="Certificate name" ./build.sh install`.

## Menu

- **Enabled**: pauses or resumes.
- **Invert Direction**: for when tilting right takes you left.
- **Repeat While Wheel Is Held**: keeps switching Spaces every 0.45 s while the wheel is tilted.
- **Test Space Switch**: checks that the shortcut works without using the mouse.
- **Launch at Login**.
- **Debug Logging**: logs every scroll event. To read it:

  ```sh
  log stream --predicate 'subsystem == "com.mousip.app"'
  ```

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Nothing happens, the icon is grayed out | The Accessibility permission is missing, or the one from the previous build is still listed: remove it, add it again and restart the app. |
| "Test Space Switch" doesn't work | The "Move left/right a space" shortcuts are disabled (Keyboard › Keyboard Shortcuts › Mission Control). |
| A single tilt skips several Spaces | The mouse repeats the event at intervals longer than 0.3 s: increase `gestureGap` in `ScrollInterceptor.swift`. |
| The log never shows a non-zero `h=` | The mouse doesn't report tilt as horizontal scrolling (for example it sends buttons 4/5 instead). |

## Structure

- `Sources/Mousip/ScrollInterceptor.swift`: event tap, filtering and grouping into gestures
- `Sources/Mousip/SpaceSwitcher.swift`: reading and posting the Mission Control shortcut
- `Sources/Mousip/AppDelegate.swift`: menu bar icon, menu and permissions
- `Sources/Mousip/Settings.swift`: preferences (UserDefaults)
