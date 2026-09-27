---
name: repo-conventions
description: KMReader subsystem conventions and invariants — reader state boundaries, reading-progress sync, offline downloads and caching, browse and dashboard behavior, detail page structure, platform UI placement. Use when working on the reader (DIVINA/PDF/EPUB engines, navigation, position), progress sync or offline features, dashboard sections or cards, browse pages, detail pages, or platform-specific UI.
---

# Repo Conventions

Subsystem conventions and invariants for KMReader. `AGENTS.md` holds repo-wide rules; this file holds the per-subsystem boundaries. When a change alters one of these boundaries, update this file in the same change (AGENTS.md rule 20).

## Reader State Boundaries

### Reader Settings vs Session

- `ReaderSettingsSheet` is for persisted preferences only. Session-only options (e.g. page rotation) belong in the reader controls menu / platform command menu. Rotation is session-only, paged DIVINA modes only, never Webtoon.

### Position & Navigation

- `ReaderViewModel` owns the committed semantic position as a full `ReaderViewItem` plus its focused `ReaderPageID`.
- `navigationTarget` is reserved for explicit navigation commands; rebuilds restore from the committed position and adapter snapshots, never synthesize commands, and a later interactive commit supersedes any restoration anchor. When a command already resolves to the current position, clear `navigationTarget` synchronously before committing (committing first loops).
- Seamless cross-book navigation: the committed `ReaderPositionAnchor` is the source of truth; `.end` items retain their segment's final `ReaderPageID`; `currentBook`/`ReaderSession.book` follow the segment; `currentBookId` remains the whole-book load anchor.
- Split wide pages keep their committed side across layout rebuilds; propagate it via `ReaderPositionAnchor.preferredSplitPart` and `ReaderViewItem.preferredSplitPart(preserving:)` whenever adapters construct a new anchor.

### Page Curl & Cover Adapters

- Page Curl adapters must not publish a position while mounting or dismantling.
- Page Curl indices are local to one coordinator-owned immutable snapshot; cross update/preload/rotation/teardown boundaries by stable reader-item identity, never array indices or view tags.
- Programmatic turns keep their `setViewControllers` completion authoritative; `willTransitionTo` must not invalidate the in-flight transition token. Programmatic `setViewControllers` must never land while a pan gesture is active (`willTransitionTo` only fires once a curl starts); coordinators gate on the pan recognizers' live state and stash work until the pan ends, like `isTransitioning`.
- Cover adapters (`NativeCoverPageView`) never finalize a page-turn transition across an item-list rebuild; `teardown()` invalidates in-flight tokens, and a viewport size change cancels an in-flight drag.

### Scroll Engine

- `ScrollReaderEngine` restores anchors strictly by page identity across item-list rebuilds, carrying the pending position as a full `ReaderPositionAnchor` (never a bare `ReaderViewItem`). Unresolvable anchors are discarded (`nil`), never positionally substituted.

### Page Load Failure State

- DIVINA page image load failures are recorded in `ReaderPageLoadScheduler` as a typed `ReaderPageLoadFailure` per page (cancellation never counts as failure), cleared on success and surfaced through the page-presentation invalidation channel; `NativePageData.failure` (paged/scroll/curl) and the Webtoon cell error state render `failure.title` / `failure.detail` with a retry button. Retry goes through `ReaderViewModel.retryImageLoad(for:)` — never re-enter the load pipeline from view code directly.
- The failure value comes from the load pipeline itself: a server/HTTP status from the remote page fetch, a network error description, a local read failure from archive materialization (`OfflineManager.getOfflinePageImageURL` throws; the `try?` callers treat it as plain absence), or offline unavailability. View code never invents its own reason text.

### Next-Book Offline State

- In offline-first reading, `ReaderViewModel.nextBookOfflineState` is the single observable for the next book's offline readiness, rendered by end-page/footer UIs.
- The status row is a permanently reserved constant-height slot toggled by alpha — never `isHidden`, which would re-lay out the page; in streaming mode the slot collapses entirely.
- Adapters refresh end content only via the page-presentation invalidation channel. The next-segment preload trigger distance must stay ahead of the download, not just the page turn.

### Read List Continuation

- Read list continuation is opt-in (`readListContinuationEnabled`, default off): `ReaderPresentationManager.present` resolves a nil read list context through `ReadListReadingService.ownerContext(forBookId:)`, so a book owned by a read list the user is reading continues in read-list order from any entry point; an explicit context (opened from that read list) always wins and works regardless of the setting.
- Every non-incognito session with a context records the entry point while the setting is on, including seamless cross-book moves (`updatePresentedBook` records only when the book id changes, not on refreshes of the same book).

## Sync, Offline & Caching

### Read Progress

- Read progress has a per-session recording threshold (`progressRecordingThreshold`, default 3, 0 = record immediately): page-change submissions and the close/background flush are withheld until the position moves at least that many pages from the session's first page per book, unless the page completes the book.
- All three engines gate on distance from the session start page (DIVINA per book id, PDF by page number, EPUB by global page index), so an accidental reader open never creates progress.
- Any path that pulls reading progress after coming online must first `await ProgressSyncService.syncPendingProgress` (it waits for an in-flight push), so a pull never overwrites newer offline-queued local progress.

### Downloads & Caches

- Cancelling a download removes its on-disk book directory; failed downloads keep partial content for resume.
- Clearing caches or server data goes through `CacheManager` and the GRDB stores only.

### Read List Reading State

- Read list reading state (`read_list_reading_states`) is user state, kept apart from the `KomgaReadList` server mirror.
- It syncs through Komga's per-user client settings, one key per read list (`kmreader.readlist.<lowercased id>`; keys must match Komga's lowercase namespace pattern), piggybacking on the reading-progress catch-up. Requires Komga 1.20.0+, the app's minimum server version.
- Reconcile pulls first and keeps, per read list, whichever change happened last on any device — a read or a stop (a stop records its time on its `isStopped` tombstone) — then pushes the local changes that won, so neither a pull nor an offline stop discards a newer change.
- Remote states are applied and pending changes pushed only while the sync's instance is still current; a server switch mid-sync drops the round.
- Only ordered read lists count as being read, including for Stop Reading, whatever another device synced.
- The local snapshot loads with each instance in `ContentView`'s per-instance startup task, independent of the network catch-up (which is offline-gated and debounced), so continuation works on offline launches and with On Deck hidden.
- While the setting is off, `ReadListReadingService` records, syncs, and resolves nothing and publishes an empty snapshot (no local reads or writes, no client-settings requests).

## Browse & Dashboard

### Pagination & Ordering

- Browse pages paginate with `PaginationState(pageSize: 50)`. Notification-driven refreshes revalidate the loaded window in place via `PaginationState.replaceItems`; full `pagination.reset()` is reserved for initial loads and explicit user actions.
- `.task`/`.task(id:)` re-runs when a view re-appears after a pushed navigation child pops back to it, so initial-load tasks (detail pages and their book/series list views) guard on a `loadedXxxId` state key and skip re-fires for the same id; returning from a child must not re-sync or reset pagination.
- User-facing metadata lists (authors, publishers, genres, tags, languages) sort with `Collection.localizedSorted()`; authors via `Author.sortedByRole()`. Never revert to raw `.sorted()`. (`MetadataIndex` encode keys and SQL clause ordering intentionally keep plain `.sorted()`.)
- Online ordering is server-side; the app-local pinned flag is invisible to the server, so online pages prepend pinned items and filter them out of the server stream.

### Dashboard Rows

- Dashboard progress sections always revalidate on `.readingProgress`; other sections skip unless browse options are progress-sensitive (`isSensitiveToReadingProgress`).
- Dashboard rows load through view models the row views own (`DashboardSectionViewModel`, `DashboardPinnedSectionViewModel`), never in a view `.task`: switching the split-view sidebar back to Home adds, removes, and re-adds the dashboard within milliseconds with its state kept, which cancels view-scoped loads mid-request.
- Appearing starts a load only when none has completed or is running (pinned rows refresh on every appear but join a running refresh for the same server); a reload supersedes a load in flight (newest wins) instead of being dropped. Do not reintroduce load-once flags or `isLoading` guards that drop a re-run.

### Pull-to-Refresh

- `.refreshable` closures must await the reload they trigger, so the refresh control dismisses onto settled content instead of racing in-flight view updates.
- Dashboard manual refreshes suspend in `DashboardRefreshCoordinator` until every rendered section acknowledges the command (section views register on appear/disappear).
- The Dashboard pull gesture leaves the toolbar untouched (`showsToolbarIndicator: false`): the refresh control is the gesture's own indicator, and swapping the trailing toolbar item mid-gesture stutters the pin/bounce-back animations. The toolbar spinner remains for menu- and code-triggered refreshes, which have no gesture. Pages whose reload can finish near-instantly (Dashboard, Offline) use `refreshableWithMinimumHold` so the control stays up for a minimum visible time instead of snapping back.
- On iPhone the Offline page pins its search bar (`navigationBarDrawer(displayMode: .always)`): in automatic mode the drawer's hide/reveal animation fights the refresh control during the pull. iPad/macOS keep `.automatic` — their search field lives in the toolbar and never conflicts.
- `OfflineView` awaits the browse view models it owns and shares with `OfflineSeriesBrowseView`/`OfflineBooksBrowseView`, whose `refreshBrowse()` re-runs the view model's current query; library-selection and account-switch reloads instead bump a `refreshTrigger` passed to those child views, so the reload runs through the child and captures the current `libraryIds` rather than replaying the view model's stale query.

### Read Lists in Progress

- Read lists continue like series: only ordered read lists with reading state and a book to continue with take part (a book in progress, or once a book is finished the next unread one, searching forward from the last book read).
- They surface only in their own `readListsInProgress` dashboard section, first by default, driven directly by `ReadListReadingService.continuations`; On Deck and Keep Reading stay Komga-native, never merged or filtered.
- `ReadListsInProgressSectionView` renders one card per list, most recently read first, with no pagination or detail page; the header links to the read lists browse page.
- Cards follow the section's card kind. `ReadListContinuationHorizontalCardView` is the default: it shares Keep Reading's horizontal-card look (solid card fill, trailing accessories) rather than copying it, and its text column follows the horizontal-card contract — semibold title line (the list's name), primary book line, secondary progress line.
- `ReadListContinuationCardView` renders large/small, with the list's name in the series slot, cover-only when small.
- Both share `ReadListContinuationContextMenu`, `ReadListContinuationProgressText`, and `ReaderActions.open(continuation:)`.
- The library scope hides a card by its continuation book's library without changing which book a list resolves to.
- The section is opt-in: it is not in `DashboardSection.defaultSections`, the setting's toggle (`SettingsReadListContinuationToggle`) adds and removes it, `DashboardSection.isAvailable` hides it from the settings lists and Reset while off, and `DashboardView` renders it only while on.
- While off, ordered, non-empty read list pages show `ReadListContinuationHintView` pointing to the setting, injected through the detail view's `actions` slot.

### Section Downloads

- Dashboard section offline downloads live only on the section detail page (`DashboardSectionDetailView`), as a single download menu (toolbar on iOS/macOS, inline on tvOS) shown for `supportsDownloadLatest` sections: every such section offers queueing the latest 20 books, and Keep Reading / On Deck (`supportsDownloadAll`) additionally offer queueing the whole section page by page. The Dashboard home toolbar carries no download actions.

### Cards

- Card sizes are fixed per platform, calibrated against Apple Books (`LayoutConfig`); there is no user-adjustable grid density.
- Card text styles and the corner badge size are not fixed: they scale with the card width via `LayoutConfig.cardTitleTextStyle`/`cardSecondaryTextStyle`/`cardTertiaryTextStyle`/`cardBadgeSize`, and card views receive their width (`cardWidth`, defaulting to `gridCardWidth`) rather than a style flag.
- Large and small grid cards share the `GridCardView` skeleton (cover with badge and optional text overlay, progress bar row, text block), which owns the card preferences; each card supplies only its badge, menu, and status line.
- Dashboard sections render one of three card kinds: `large` (fresh content showcase: on deck, recently released/added books, recently updated series), `small` (library activity/history: recently added series, recently read books), `horizontal` (Keep Reading books, read lists in progress, pinned read lists/collections).
- `DashboardSection.cardKind` is only the default — the user can override any books/series section, and read lists in progress, from the menu at the trailing edge of its header row (`DashboardCardKindMenu`, shared by the section views; books sections and read lists in progress, whose cards are each list's next book, offer large/small/horizontal, recently added books large/small only, series sections large/small; pinned sections stay horizontal-only), persisted in `DashboardConfiguration.cardKindOverrides` (overrides that are no longer offered are ignored). The menu itself can be hidden via the Dashboard settings toggle (`showDashboardCardKindMenu`, on by default); hiding it keeps the chosen overrides in effect.
- Section list edits in Settings (show, hide, reorder, Reset) change only `sections`, keeping the overrides and the library selection; 6.4's Keep Reading toggle (`dashboardHorizontalBookCards`) is carried over once at launch (off → Keep Reading `large`).
- Small cards are cover-only (`coverOnly`): every text line truncates at that width and stops carrying information, and card text overlay mode never renders on them.
- Cover corner badges are gated on `thumbnailShowUnreadIndicator`: series cards show the unread count, book cards show a completed checkmark — books have no unread dot.
- On horizontal cards the text column distributes vertical slack evenly across every gap (above the title, between the lines, below the bottom bar; the title keeps a 4pt minimum above the series line): a two-line title fills the card (title flush to the top, bottom bar flush to the bottom), while a one-line title spreads the freed space across all gaps instead of letting one area go empty. Lines follow Apple Books ordering — semibold title on top, series line under it, meta (progress/status) at the bottom — and step down in size (`LayoutConfig.horizontalCardFontSize` for the title, −1 for the series line, −2 for meta); the cover height matches the resulting four-line text column so the card is no taller than its text. The title and series line use the primary color (the title turns secondary once completed); only the bottom bar is secondary. Horizontal cards sit on a cover-tinted background, Apple Books style: the cover's average color, brightness-clamped so white text stays readable without the card going pitch black (`ThumbnailTintColorCache`, loaded per card via `ThumbnailTint`, which also reloads on `.thumbnailDidRefresh`); until the tint resolves the card falls back to the `cardBackground` color asset with the adaptive colors above. On the tint all text is white — title full white (70% once completed), series line 85%, bottom bar and accessories 70%; cover and text form one button (one tvOS focus target), while the trailing accessories stay separate targets, Apple Books style — a passive download status indicator (only while pending, downloaded, or failed) and an `EllipsisMenuButton` mirroring the card's context menu, both at `LayoutConfig.horizontalCardAccessoryIconSize`.
- Book cards open the reader directly on tap — grid cards, list rows, and horizontal cards alike; the book detail page (oneshot detail for oneshots) is reached through the context menu's Details entry (`Book.navDestination`), which leads the menu alongside Peek (incognito) and series navigation. Series cards navigate to their detail page on tap.

## Detail Pages

- Detail page header zones follow the measured content width: hero, action card, and timestamps center below `LayoutConfig.detailWideLayoutMinimumWidth` (960pt) and lead above it, driven by the `detailHeroCentered` environment value injected by each content view (each measures its own width via `onGeometryChange`; wide two-column rails inject `true`); the content sections below (summary, chips, media information, membership sections) always stay leading. Pages follow a fixed hierarchy: hero (cover with title, author chips, and quiet `DetailMetadataRow` facts), a `DetailActionCard` grouping reading state with primary actions (the page's single focal point; the series continue-reading button and `SeriesDownloadActionsSection` are injected by `SeriesDetailView` through the content view's `actions` slot), summary, `DetailChipFlowSection` chips for relational metadata (genres/tags/publisher/external links), headline sections (alternate titles, media information, membership sections like `BookReadListsSection`/`SeriesCollectionsSection`).
- On book detail pages (book and oneshot) the hero's series title is the series navigation — a plain icon + title + chevron `NavigationLink` styled like the dashboard section headers, hidden when the page is presented in a sheet (the sheet's own book/series toggle covers it); there is no View Series button. The action block leads with a prominent capsule Read button on its own row — full width in centered layouts, a fixed 480pt width when leading — a single-line caption mirroring the series continue-reading caption (Read, or Resume Reading while the book is in progress, followed by the reading progress Page X · Y% or the page count) — with Peek and the download toggle as a secondary row beneath; the whole block centers below the detail wide-layout minimum width and leads above it (where the download status chip sits at the trailing edge of the card's state line).
- Headline-section titles are plain `Text(...).font(.headline)` in primary color with no icon; an icon-tinted secondary header reads as another row of the section above. Membership sections render nothing while empty and carry their own top padding to separate from the block above.
- Alternate titles render through the shared `SeriesAlternateTitlesView` (series detail in both layouts, and the oneshot detail page); more than 2 entries collapse behind a Show More/Show Less toggle. Membership sections (`BookReadListsSection` on book/oneshot pages, `SeriesCollectionsSection` on series/oneshot pages) likewise collapse beyond 3 entries. The toggle is the shared `ExpandToggleButton`, also used by `ExpandableSummaryView`.
- `DetailTimestampsView` sits directly under the `DetailActionCard` (ReadList/Collection cards carry the count line — `ReadListBookCountView`/`CollectionBookCountView` — with `ReadListDownloadActionsSection` injected through the read list content view's `actions` slot).
- Chips use `DetailChip`: a small neutral capsule with no per-field colors; hero creator chips (publisher/authors) and external-link chips render with `glassEffect` on iOS/macOS/tvOS 26+ (falling back to a quiet secondary fill on older OS), while genre/tag chips always use the secondary fill (`glass: false`); icons only where they carry meaning (author role, external link).
- State color appears only as text: green/orange/red and `MediaStatus.detailColor`/series `statusColor` in the action card; static metadata stays secondary.
- The scrolling content always carries `.padding(.vertical)` (horizontal padding stays per-section); in the wide two-column layout each column's `ScrollView` content pads itself.
- Detail-page ScrollViews use an eager `VStack`, never `LazyVStack`: the only lazy content is the books/series list, which carries its own lazy containers, and a `LazyVStack` transiently misplaces children during animated section updates.

## Platform UI Placement

### Tabs & Navigation Entries

- Series continue-reading accessory: `tabViewBottomAccessory(isEnabled:)` in `PhoneTabView` (iOS 26.1+ only), modifier permanently attached with `isEnabled` toggling visibility; other platforms use the inline `SeriesReadingActionButton`. Do not reintroduce the floating `safeAreaInset` bar. The reading target is resolved from the local projection first (presented as the page appears) and only confirmed against the server after the detail sync, so the bar never pops in late with fallback content.
- iPhone has no Server tab: the current-server card plus Management/Account entries live in `SettingsView` on iPhone only; iPad/tvOS keep the full `ServerView`.
- iPhone Library tab root is `LibraryBrowseView`; its scope is the global dashboard selection (no tab-local store). `LibraryScopeToolbarButton` is the shared leading button (explicit `HStack` icon + `Text`, sheet/list owned by the parent view), always shown at tab roots regardless of library count; a single library is titled with its name.
- `NavDestination.browseLibrary` carries its `LibrarySelection` in the destination value; do not reintroduce side channels into `BrowseView`.
- Reading stats entry lives on the Dashboard (toolbar menu item on iOS/macOS, header button on tvOS), pushing `NavDestination.settingsReadingStats`.

### Detail Heroes & Wide Layouts

- Detail page heroes (Series/Book/OneShot/ReadList/Collection) share `DetailHeroView`: in centered mode a 180pt cover stacks above the centered info block; otherwise the cover sits beside the leading info block at `PlatformHelper.detailThumbnailWidth`. The mode comes from the `detailHeroCentered` environment value — never read `horizontalSizeClass` inside shared hero subviews.
- Action card contents (book-count line, reading/download action rows, state lines) and the `DetailTimestampsView` row follow the same value; in centered mode the card itself is capped at 480pt and centered, otherwise it stretches full width.
- All chip rows (hero creator row, genres, tags, links) go through the single data-driven `DetailChipFlow` component; do not add per-field chip containers. It is the one component used both inside and outside the hero, so each content view scopes its `detailHeroCentered` injection to the header zone (hero + action card + timestamps, wrapped in one `Group`): the flow centers inside the hero and stays leading in the sections below.
- Series detail uses the two-column layout only while the detail column is at least `LayoutConfig.detailWideLayoutMinimumWidth` (960pt) wide (`usesWideLayout`: measured width via `onGeometryChange`; iPad additionally requires regular size class, macOS decides by window width alone). The wide shell is the shared `DetailWideLayoutView` (Series/ReadList/Collection detail pages all compose it); each page passes its own rail content and right column.
- `DetailWideLayoutView` owns the two-column shell: the left rail takes the golden-ratio slice of the detail column (width/φ² ≈ 38.2%, floored at 340pt) and carries identity plus about-info (series: 240pt cover, hero info, action card capped at 400pt, timestamps, summary, chips, alternate titles; read list/collection: cover, hero info, count action card, timestamps), while the right column flows collections and the books/series list. Rail and column are independent `ScrollView`s so the rail never scrolls away with the list.
- The rail's scroll bounds extend `railEffectMargin` (12pt) into the empty space around the rail — `contentMargins(.horizontal, railEffectMargin, for: .scrollContent)`, with leading padding and column spacing shrunk by the same amount so the visual grid is unchanged. Glass chips render their rim highlight only with a few points of room outside the capsule; flush against the scroll bounds the rim is clipped away. Do not use `scrollClipDisabled()` on the rail: vertical scrolling then paints content past the rail's top/bottom bounds.
- Narrower columns (iPad portrait with a docked sidebar, iPad mini portrait, narrow macOS windows, compact widths, tvOS) keep the single-column `SeriesDetailContentView`.
- Both layouts compose the same extracted section views (`SeriesHeroInfoView`, `SeriesBookCountView`, `SeriesSummaryView`, `SeriesDetailChipsView`, `SeriesAlternateTitlesView`).

### Layout Toggle & Chip Rows

- Browse layout switching (grid ↔ list) lives in `LayoutModeToggleButton`, a single icon button rendered at the front of the filter chip row (the chip-row views take an optional `layoutMode` binding); pages without a chip row place the same button above the content (e.g. `DashboardSectionDetailView`).
- Chip rows are always full-width leading-aligned — on detail pages (series/read list/collection) the selection-mode button sits trailing — so the toggle aligns with the content below; do not wrap the row in a `Spacer`-pushed trailing cluster.
- The toggle matches chip height through a blank caption-weight text line (icon glyphs alone render shorter). Do not reintroduce toolbar layout pickers.

### Toolbar

- Toolbar trailing policy: at most one trailing toolbar button per content page (two only when a primary action sits next to the single ellipsis menu, e.g. Dashboard search). Everything else lives inside the ellipsis menu; sheet/alert presentations from menu items must go through `deferMenuActionPresentation`.
- When a trailing menu would hold only filter actions (BrowseView, OfflineView), it is expanded into trailing icon buttons instead: Filter always, plus Saved Filters for series/books content. Detail pages carry no Filter/Saved Filters menu entries; the filter chip row owns those entry points.
- Toolbar button ordering: conditional buttons go on the inside of a trailing group (closer to the title); unconditional buttons hold the outer edge, so the edge position never shifts when the condition toggles (BrowseView/OfflineView keep Filter at the edge, Saved Filters inside).

### Settings Pages

- Settings pages: top-level groups are Reader / Display / Server (iPhone only) / Behavior / Advanced / About.
- Settings shared by all readers (DIVINA, EPUB, PDF) live in the Reader group's first entry, `SettingsSection.reading` (`ReaderPreferencesView`) — never in the DIVINA-only `ReaderSettingsSheet` or the per-reader preference pages; reading-session feature toggles (Keep Screen Awake, Reader Live Activity) live there too, as do the offline-reading preference toggles (Offline-first Reading, Auto Delete Read Books, in the page's first section). The read list continuation toggle (`SettingsReadListContinuationToggle`) lives there as well, in the page's Read Lists section: it is a reading behavior (entry-point resolution, recording, sync) whose dashboard section is a side effect.
- `SettingsSystemFeaturesView` keeps Handoff only and is not linked on tvOS; new pages register a `SettingsSection` case and use `SettingsBadgeRow`/`SettingsSectionRow` entries.
