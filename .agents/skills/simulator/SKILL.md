---
name: simulator
description: Use when observing or driving an iOS simulator for KMReader debugging — screenshots, accessibility tree, tap/swipe/gestures, hardware buttons, orientation, and unified logs via baguette. Build and install go through the Makefile + xcrun simctl.
---

# simulator — iOS simulator interaction

`baguette` (brew, Apple Silicon + Xcode 26+) is a CLI for headless iOS simulator control: screen capture, host-HID input injection, accessibility tree, and log streaming.

## Boundaries

- baguette does **not** build or install apps. Keep the existing flow:
  `make build-ios`, then `xcrun simctl install <UDID> <app>` and `xcrun simctl launch <UDID> com.everpcpc.Komga` (`terminate` to stop).
- The target simulator UDID is persisted in `devices.json` (`ios_simulator`). Read it from there; `baguette list --json` shows boot state.

## Device Hub gotcha (read first)

A simulator booted by Xcode (e.g. after `make run-ios-sim`) has its input surface shadowed by Device Hub: taps/swipes ack `{"ok":true}` but land nowhere. Fix once per boot:

```bash
baguette heal --udid <UDID>   # restarts SpringBoard, ~4s
```

Booting with `baguette boot --udid <UDID>` (headless) avoids the problem entirely.

## Interaction loop

1. `baguette describe-ui --udid <UDID>` — AX tree as JSON. Every node has a `frame` in **device points**; compute the center and feed it straight into a tap. Add `--x <px> --y <py>` to hit-test one point instead.
2. Act: `tap` / `double-tap` / `swipe` / `pinch` / `pan` / `press --button home` / `type --text ...` / `paste --text ...` (paste handles unicode; `type` is US-ASCII only). To replace existing field text: double-tap the field to select its content, then `paste` — Cmd+V overwrites the selection.
3. Verify: `baguette screenshot --udid <UDID> -o /tmp/shot.png` and read the image. Re-capture after each action; on unexpected results retry once, then stop and report.

```bash
baguette tap   --udid <UDID> --x 122 --y 237 --width 402 --height 874
baguette swipe --udid <UDID> --start-x 340 --start-y 437 --end-x 60 --end-y 437 --width 402 --height 874
```

- Coordinates are device points, not pixels. The screen size in points is the root node's frame in `describe-ui` (e.g. 402×874 for iPhone 18 Pro); `--width`/`--height` must match it.
- CLI flags are kebab-case (`--start-x`, not the README's `--startX`). When in doubt, `<cmd> --help`.

## Logs

```bash
baguette logs --udid <UDID> --predicate 'subsystem == "com.everpcpc.kmreader"' --style compact
```

- The app logs to subsystem `com.everpcpc.kmreader` (see `AppLogger.swift`), categories `API`, `SSE`, `ReaderViewModel`, etc. `--bundle-id com.everpcpc.Komga` and `--level` also work.
- The stream is live-only (no history); start it before reproducing the issue, stop with ^C/`pkill -f "baguette logs"`.

## Extras

- `baguette orientation --udid <UDID> landscape-left` — rotate; `press --button lock` — lock.
- `baguette record --udid <UDID> --duration 10 -o /tmp/clip.mp4` — H.264 recording.
- `baguette serve` — web UI at http://localhost:8421/simulators (live stream, farm view, AX inspector). Useful for watching a long session; the CLI is enough for scripted checks.
