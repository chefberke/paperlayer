# Paperlayer

A tiny native macOS menu bar app for tired eyes and empty desks. Pure Swift and AppKit, no Xcode project, no dependencies, under 700 lines.

## Features

### Eye breaks

Follows the 20-20-20 rule: after 20 minutes of active use, every screen dims for 20 seconds and asks you to look at something 20 feet (6 m) away and blink. Of the common screen-fatigue tips, regular breaks like this are the one with research behind them.

- Counts only active time. Idle for more than a minute does not count as work.
- Idle for 5 minutes counts as a natural break, so the timer restarts. Waking the Mac from sleep restarts it too.
- The break panel never steals focus, so typing and games keep their input. Click anywhere to skip.
- On by default. Toggle from the menu or with `⌃⌥P` from anywhere.

### Paper mode

A light matte paper texture over every screen, inspired by [Paperman](https://paperman.cc/). It softens glare and harsh contrast without shifting colors.

- Clicks and keys pass straight through to the apps below.
- Hidden from screenshots and screen sharing.
- Off by default. Toggle from the menu.

### Away mode

For leaving your desk without putting the Mac to sleep. The screen turns into Matrix rain with a bouncing EatBetter logo, DVD screensaver style, and a "Be right back" note with the time you left.

- The logo changes color every time it hits a wall.
- Keeps the display awake while it is on.
- All motion runs as Core Animation on the GPU, so the app itself stays near 0% CPU.
- Press any key or click to come back to the app you were using. Moving the mouse does not end it.
- Start it from the menu or with `⌃⌥B` from anywhere.

## Requirements

- macOS 13 or later on Apple silicon
- Xcode Command Line Tools (`xcode-select --install`)

## Build

```bash
./build.sh            # builds build/Paperlayer.app
./build.sh install    # also copies it to ~/Applications
open build/Paperlayer.app
```

The app lives in the menu bar as an eye icon and has no Dock icon. The icon looks dimmed when eye breaks are off.

## Tuning

There is no settings window on purpose. The numbers are constants at the top of the source files:

| What | Where |
| --- | --- |
| Work time, break length, idle limits | `Sources/Breaks.swift` |
| Paper texture strength (`coverage`) | `Sources/Overlay.swift` |
| Rain, logo size and speed | `Sources/Away.swift` |

## Layout

```
Sources/
  main.swift       menu bar item, menu and shortcuts
  Breaks.swift     20-20-20 timer and the break panel
  Overlay.swift    click-through paper windows
  Texture.swift    procedural paper texture
  Away.swift       away screen: rain, bouncing logo, note
  HotKey.swift     global shortcuts through Carbon, no Accessibility permission needed
  Settings.swift   the two on/off switches, stored in UserDefaults
Resources/
  eatbetter-logo.png
```
