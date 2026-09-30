# AGENTS.md

Rules that must not be violated when working in this repository. For architecture and feature details, read the code. Subsystem conventions and invariants live in the `repo-conventions` skill (`.agents/skills/repo-conventions/SKILL.md`) — load it when working on the reader, sync/offline, dashboard, detail pages, or platform UI placement.

## Project

**KMReader** is a native SwiftUI client for [Komga](https://github.com/gotson/komga). iOS 17+ / macOS 14+ / tvOS 17+, Swift 6, Xcode 15+. There are no XCTest targets: validate with builds and manual testing.

## Commands

All builds run through the Makefile (wrapping `misc/xcode.py`); never invoke `xcodebuild` directly.

```bash
make build          # build all platforms (preferred validation)
make build-ios      # platform-specific; run sequentially, never in parallel
make build-macos    #   (xcodebuild shares one DerivedData database)
make build-tvos
make run-ios-sim / make run-macos / make run-tvos-sim   # run (device choice persisted in devices.json)
make format         # format code after editing
make localize       # update localizations; ./misc/translate.py list|update for keys
make bump / make minor / make major   # version management
```

Never edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in `project.pbxproj` by hand. Run `make bump` only when the user explicitly asks; the bump commit then rides along in the feature/fix PR, not a separate PR.

After changing code: `make format`, then `make build`. Simulator interaction and debugging go through `baguette` (see the `baguette` skill): filter logs with subsystem `com.everpcpc.kmreader` (categories `API`, `SSE`, `ReaderViewModel`).

## Coding Conventions

1. **Comments**: minimal, English only; no issue/PR numbers (link issues in the PR description instead).
2. **Git-facing text**: commit messages, PR titles/bodies, and review comments are always in English.
3. **UI frameworks**: SwiftUI, UIKit, and AppKit are all acceptable; pick per feature and platform.
4. **No inline `Binding`**.
5. **No `confirmationDialog`**.
6. **One type per file**.
7. **State**: `@Observable`, never `ObservableObject`.
8. **Preferences**: `@AppStorage` in views, `AppConfig` elsewhere; `UserDefaults` only inside `AppConfig.swift`.
9. No stored variables in view bodies; avoid computed-property clutter there too.
10. In-reader settings sheets stay compact; full settings pages may carry description text.
11. Platform differences via `PlatformHelper` and `#if os(...)`.
12. UIKit/AppKit interop in either direction is fine; be explicit about dependency injection and verify environment/data propagation across hosting boundaries.
13. **Banned**: non-optional object-style environment dependencies (`@Environment(SomeType.self)`, `@EnvironmentObject`). Pass objects via initializers, context structs, or action closures; use non-object custom `EnvironmentKey`s when needed.
14. **Banned**: `@unchecked Sendable`, `nonisolated(unsafe)`, `unsafeBitCast`, other `unsafe*` escape hatches. Redesign instead.
15. Do not store async/throwing/`@Sendable` closures in SwiftUI `View` value types (iOS 17 AttributeGraph crash risk); use concrete command types or passed-in services.
16. **Animation boundaries**: local implicit `.animation(..., value:)` only for micro-interactions (press/hover/selected states); explicit `withAnimation {}` for navigation, presentation, content, and pagination changes. No broad/root `.animation` on containers rendering lists.
17. No patch-style fixes for structural problems; no compensating flags/delays/counters around a broken ownership boundary. Refactor toward the stable architecture.
18. End-state quality beats diff size; do not fear rewriting a subsystem when that is the cleaner design.
19. Temporary compatibility layers must say why they exist and what replaces them; treat them as debt.
20. When a change alters a lifetime, ownership, persistence, navigation, platform, reader-mode, or UI-placement boundary, update the conventions in the same change: `AGENTS.md` for repo-wide rules, the `repo-conventions` skill for subsystem boundaries.
21. No hand-rolled fallback shims for newer OS APIs; gate features to the OS version that supports them natively.
22. **No force casts** (`as!`), especially on GRDB `Row` subscripts; use the generic converting subscript (`let date: Date = row["created_date"]`) or `as?` with a fallback.
23. Never render an empty `HStack`/`VStack`; put the condition around the stack itself so nothing renders when there is no content.
24. Lazy containers (`LazyVStack`/`LazyHStack`/`LazyVGrid`) only for genuinely unbounded content (paginated or otherwise huge lists); eager stacks everywhere else — lazy stacks cache child frames and misplace children during animated layout updates.
25. Plain-style buttons and links (`.buttonStyle(.plain)`, text-or-label-only) must declare `.contentShape(Rectangle())` (or an equivalent hit shape) **on the content inside the button's label** so the whole frame is tappable; without it only the glyphs respond. `.contentShape` applied outside on the button itself has no effect on hit-testing, regardless of button style.

Additional patterns:

- Pass shared object dependencies explicitly at split/tab roots, `NavigationStack` roots, sheets, full-screen covers, scene boundaries, and any `UIHostingController`/`NSHostingController` boundary; do not assume environment inheritance survives snapshot/rotation/scene transitions.
- SSE callbacks are single-assignment closures; implement dispatchers when multiple components need the same event.
- New API endpoints belong in the appropriate service; keep request-building out of views.
- Dashboard/library selections persist via `LibraryManager` and related managers.
- All logging goes through `AppLogger` (OSLog subsystems/categories); user-visible errors through `ErrorManager.shared` (`notify` for transient success).
- The Xcode project uses folder references (not groups); adding/removing files does not require editing `project.pbxproj`.
- Translate all supported languages (see `misc/translate.py`); reference `../komga/komga-webui/src/locales/` when available.
- When building JSON strings for storage or cache keys, use `JSONSerialization` with `sortedKeys` for stable raw values.
- Colors that only vary between light and dark mode belong in `Assets.xcassets` as color sets with light/dark appearances, referenced as `Color.<name>` — not `colorScheme` branching in views. Assets also carry alpha and can encode gradient-stop pairs (start/end as two assets), so a flipped gradient still needs no branch. Reserve `colorScheme` reads for layout or logic differences; clusters of one-off decorative tints serving a single view may stay local when converting would mean many single-use assets.
- SF Symbol fill/outline duality is a rendering concern, not data: models and enums expose the base (outline) symbol name, and the site that knows its rendering context applies `.symbolVariant(.fill)` (e.g. white-on-cover icons). Do not thread hardcoded `*.fill` names or parallel filled-name parameters through view APIs. Exception: an icon that renders filled in every context is part of the status's identity, not a rendering choice — models may return the `.fill` name directly (e.g. `checkmark.icloud.fill`, `exclamationmark.circle.fill` in download statuses).

## GRDB Migration Discipline

Runtime GRDB migrations in `LocalDatabase` are immutable once committed.

- Never mutate an already-registered migration (e.g. `create_runtime_schema_v1`, `00002_add_protected_server_flag`) or its helpers; they are the frozen baseline.
- Any table shape change is a new numbered migration after the latest one; fresh installs run baseline + all later migrations in order.
- New persisted field: update the record model and `CodingKeys`, then add a migration backfilling a safe default.
- Validate both upgrade and fresh-install paths.
