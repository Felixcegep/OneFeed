# OneFeed

**One article at a time.**

OneFeed is an iPhone and iPad RSS reader built around a single constraint: you can only focus on one article at a time. Instead of turning subscriptions into another overflowing inbox, it selects one article from sources you deliberately follow. Read it, save it, or skip it; the next article then takes its place.

## MVP

- Direct RSS and Atom subscriptions with website feed discovery
- FreshRSS connection through its Google Reader-compatible API
- One-current-article state machine with fair source rotation
- Internal, offline-capable reader
- Saved articles, history, and source management
- OPML import and export
- Opportunistic background refresh
- Home Screen and Lock Screen current-article widget
- Light/dark mode, Dynamic Type, VoiceOver labels, and Reduce Motion support
- Keychain-only FreshRSS credentials and no OneFeed account, analytics, ads, or unread counters

FreshRSS read and starred states map to Done and Save. Skip remains local to OneFeed so a preference made in this focused experience does not destructively alter the server’s read state.

## Product rule

OneFeed is not an inbox. There is no home timeline, unread badge, unread total, dashboard, category system, recommendation feed, streak, social layer, or engagement mechanic.

## Development

Open `MonoRss.xcodeproj` in Xcode 26.6 or later. The app targets iOS/iPadOS 26.5. The test targets contain pure state/parser/FreshRSS coverage and a deterministic UI screenshot tour seeded with `-uiTesting -inMemoryStore`.
