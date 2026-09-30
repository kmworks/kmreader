---
name: simulator
description: Use when observing or driving an iOS simulator for KMReader debugging — screenshots, accessibility tree, tap/swipe/gestures, hardware buttons, orientation, and unified logs. Multi-step verified UI sequences go through the jevsim MCP tools when available, otherwise through baguette; baguette also covers observation, gestures, and logs. Build and install still go through the Makefile + xcrun simctl.
---

# simulator — iOS simulator interaction

`baguette` (brew, Apple Silicon + Xcode 26+) is a CLI for headless iOS simulator control: screen capture, host-HID input injection, accessibility tree, and log streaming.

## Tool routing: jevsim vs baguette

Multi-step verified UI sequences (navigate to a screen, exercise a form, reproduce a flow) go through the `jevsim_*` MCP tools: `jevsim_status` → `jevsim_inspect` → `jevsim_run_steps` (tap/type/scroll/wait/assert, each step with an `expect`). One call replaces many describe-ui/tap/screenshot round trips. If the `jevsim_*` tools are absent from the toolset or `jevsim_status` reports not connected, run those sequences through the baguette interaction loop below instead.

Stay on baguette for what jevsim cannot do:

- screenshots / visual verification — jevsim reads the AX tree only
- unified logs, recording, orientation, hardware buttons
- swipe/pinch/pan — jevsim has tap/scroll only
- non-ASCII text — jevsim iOS input is printable ASCII; use `baguette paste`

During a `jevsim_run_steps` call the simulator is reserved; finish it before any baguette interaction on the same device.

jevsim field notes (verified on this repo):

- If jevsim actions ack but nothing happens, Device Hub is shadowing its input: `kill -9` it (SIGTERM is ignored) and reboot the simulator headlessly, then retry. baguette taps use a different HID path and are unaffected, which can mask this.
- KMReader exposes SF-symbol identifiers on tabs and buttons (`house`, `gearshape`, `xmark`, …). Prefer exact `identifier` targets — they skip the Jev model (faster, fully local, and the only option when TYPESAFE_API_KEY is not configured).
- Expect on text unique to the destination screen: the dashboard stays in the AX tree behind the full-screen reader, so `gone "Keep Reading"` never fires after opening a book; reader-only markers like `"Keyboard Shortcuts"` work.
- Reader controls auto-hide — the first tap on the Close area only reveals them; the real close button carries identifier `xmark`.
- The Jev model abstains below 0.9 confidence (`low_probability`); inspect and re-describe, or use the element's identifier.

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
