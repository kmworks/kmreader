<div align="center">

# KMReader

<div>
  <img src="icon.svg" alt="KMReader Icon" width="128" height="128">
</div>

**Native SwiftUI Komga client for iOS, macOS, and tvOS.**

[![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)](https://www.apple.com/ios/)
[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos/)
[![tvOS](https://img.shields.io/badge/tvOS-17.0+-blue.svg)](https://www.apple.com/tv/)
[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org/)
[![Xcode](https://img.shields.io/badge/Xcode-15.0+-blue.svg)](https://developer.apple.com/xcode/)

[![Download on the App Store](https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us)](https://apps.apple.com/app/id6755198424)

</div>

## Important Features

### Readers

- DIVINA reader on iOS, macOS, and tvOS with LTR, RTL, vertical, Webtoon, spreads, zoom, page curl on iOS, cover transitions, tap zone layout presets, keyboard support, per-page rotation, border cropping, preload profiles, and per-book preferences.
- EPUB reader on iOS/macOS with paged, scrolled, curl, or cover layouts, custom fonts, per-book theme and typography controls, dedicated EPUB behavior settings, status/footer overlays, multi-column reading, and nested table of contents.
- PDF reader on iOS/macOS with native PDF or DIVINA mode, search, table of contents, page jump, automatic or explicit page presentation modes, spread layouts, configurable render quality, and continuous reading options.
- Animated GIF and WebP pages play inline. Peek mode (progress-free reading), page image actions, persistent reader progress overlays, AI upscaling, and iOS Live Text are supported where available.

### Browse and Discovery

- Dashboard sections for Keep Reading, On Deck, Recently Added, Recently Updated, Read Lists in Progress, and pinned collections/read lists, with per-section card styles, cover-tinted horizontal cards, and quick offline actions for current or full book sections where supported.
- Ordered read lists can continue like series: books navigate in list order from any entry point, and per-list reading state syncs across devices.
- Browse Series, Books, Collections, and Read Lists with metadata filters including age rating and release year, all/any matching, saved filters, reading history, an adjustable pages-read heatmap, dashboard search access on larger layouts, optional unread-cover blur, and batch read-status updates from series pages.
- iPhone gets a dedicated Library tab for content-first browsing plus a focused Search tab.
- Local database storage keeps large libraries, dashboards, logs, downloaded content, and offline browsing responsive.
- Server-specific dashboard library scopes, refreshed widget payloads, Spotlight indexing for downloaded content, plus iOS widgets and Home Screen quick actions for Keep Reading, Search, and Downloads.

### Offline and Sync

- Download books for offline reading across DIVINA, EPUB, and PDF workflows, with optional offline-first reading that prepares local content before opening the reader.
- Per-series and per-read-list policies support manual, unread-only, unread + cleanup, and all-books downloads.
- Downloaded library sections show book counts alongside storage usage, sync missing covers for offline data, and support pull to refresh on iOS and macOS.
- Large downloads stream to disk, while CBZ, CBR, PDF, and supported EPUB offline flows keep source files available and prepare pages on demand.
- Progress and offline changes sync when reconnecting, with stale progress protection and automatic recovery from server outages when offline mode was entered automatically. Cache controls cover pages and thumbnails.
- iOS background downloads and Live Activities show reader progress, incognito status, download progress, and processing state.

### Multi-Server and Management

- Save multiple Komga servers, protect private servers with device authentication, and switch instantly.
- Sign in with username/password or API key, set up a brand-new Komga server right from the login screen, and manage Komga API keys inside the app.
- Admin tools cover metadata editing, library management, media analysis, missing posters, duplicate files/pages, task monitoring, and paginated log viewing, export, and clearing.

### Platform Highlights

- iOS/iPadOS: widgets, quick actions, Spotlight search, Dynamic Island Live Activities, background downloads, Live Text, and reader keyboard shortcuts.
- macOS: dedicated reader windows, menu bar reader actions, Spotlight search, keyboard shortcuts, and keyboard help.
- tvOS: remote-first DIVINA reading and TV-optimized browsing.

KMReader UI is localized in English, German, French, Japanese, Korean, Simplified Chinese, Traditional Chinese, Italian, Russian, and Spanish.

## Getting Started

### Prerequisites

- Komga 1.20.0+
- Xcode 15.0+
- iOS 17.0+, macOS 14.0+, tvOS 17.0+

### Build and run

```bash
git clone https://github.com/kmworks/kmreader.git
cd kmreader
open KMReader.xcodeproj
```

```bash
make build-ios
make build-macos
make build-tvos

make run-ios-sim
make run-macos
make run-tvos-sim
```

## Compatibility

- Komga API v1 and v2

## Community

- [Discord](https://discord.gg/komga-678794935368941569)

## Open Source Licenses

Third-party notices: [`OpenSourceLicenses.json`](KMReader/Resources/OpenSourceLicenses.json), also shown in the in-app licenses screen.
