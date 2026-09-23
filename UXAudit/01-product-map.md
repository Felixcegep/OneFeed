# Product map

Shell: `App/AppShell.swift`. Compact width is a tab bar. Wide width is a sidebar titled OneFeed. Same four destinations either way (`App/AppTab.swift`).

```
Today
Queue
Feed
Settings
```

There is no global search. Source search lives inside Sources (“Folders or sources”).

`Features/Library/LibraryView.swift` is an older screen titled Library (Sources, History, Settings). It is not in the tab bar. Ignore it when describing the shipping navigation, but know the word Library still appears in Settings → Storage.

## Today

`Features/Current/CurrentView.swift`

- List of today’s remaining stories. First row is a featured card. The rest are rows.
- Sections in the list: Up next, Also today.
- Empty with no sources: add a source.
- Empty when the deck is finished: “You’re all caught up”, with Refresh.
- Toolbar refresh. A full-screen cover can say Updating while sources refresh.
- Tap a story: reader, full screen on iPhone, split on Mac.
- Mac can open the next story by itself after you finish one.
- Swipe and context menu on a row can Queue, Done, Skip, or Not interested without opening the reader.

## Queue

`Features/Saved/SavedView.swift`. The type is still named Saved. The screen title is Queue.

- Waiting items, including a video subsection (“Recently saved”).
- Empty: “Nothing waiting”, actions Open Today and Add to Queue.
- Add sheet: paste a link, paste clipboard, import PDF or EPUB, or pick a story already in the feed (`AddToQueueView.swift`).
- History is a navigation link from this screen.
- Remove from Queue puts an item back. Stars (1–5) are a separate rating on the row menu.

## Feed

`Features/Browse/FoldersView.swift`. Title: Feed.

- Your sources, grouped in folders. Each folder has a user-picked emoji. Tap the emoji to change it. Tap the row to open the folder.
- Manage sources opens `SourcesView`.
- Add Source from the toolbar and from empty states.
- Librarian (books icon) opens the experimental Gemini tool. The settings screen for the same tool is titled Experimental.
- A folder’s story list is `FeedStreamView` / the collection column. History can also be reached from the feed stream.
- Empty folders and empty story lists use `EmptyLibraryState`.

## Sources

`Features/Sources/SourcesView.swift`. Reached from Feed, not a tab.

- Search folders and sources.
- Add Source sheet: paste one or many URLs, pick a folder or create one, Add.
- Per source: pause (Included in Feed / Paused), folders, remove.
- Menu: Restore all seeded sources.
- Remove source confirms: “Remove this source and its locally stored articles?”
- Remove empty folder confirms: “Remove empty folder?”

## Reader

`Features/Reader/ReaderView.swift`. Opened from Today, Queue, Feed, and History.

iPhone bar, five slots, no sixth icon:

1. Queue
2. Skip (long-press or context menu: Not interested)
3. Done (emphasized)
4. Share
5. Browser

Mac bar: Queue and Skip on the left, Done in the center, Share and Browser on the right.

Close leaves the article unchanged.

At large accessibility sizes the bar stacks: Done is a full-width primary button, then Queue, Skip, Not interested. Share and Browser move into the reading menu.

Done does not finish immediately. It opens `ReadingTakeawaySheet` (“What stayed with you?”). Skip on that sheet, or an empty Save, finishes as read and keeps any note already stored. A choice or a sentence is saved, then the article is marked read. Swiping the sheet away also marks it read.

After the sheet closes, a short decision curtain plays (about 320 ms for read, 180 ms for skip, 520 ms for queue), then the reader closes.

Other reader UI:

- Mode picker: Reader / Website (or Summary / Video, PDF / page).
- Reading menu: Focus, font, text size, and for YouTube, summarize or ask.
- Focus sheet (`ReaderFocusSheet`).
- Video summarize confirmation.
- Gemini API key sheet if summarize or ask needs a key.
- Video chat sheet (`VideoChatSheet`).
- In-app browser (`ArticleBrowserView`).
- PDF pane when the item is a PDF.

## History

`Features/History/HistoryView.swift`. Reached from Queue and from Feed. Not a tab.

- Days of read and skipped articles.
- Link to Not interested (“Set aside, grouped by source”).
- Empty: “No history yet. Read and skipped pieces appear here quietly.”
- Opening an article shows the reader. Finishing here only closes the reader. It does not change read or skipped state. A takeaway typed here is still saved onto the article.
- There is no “put this back in Queue” or “put this back in Today”.

Not interested screen (`NotInterestedView`): grouped by source. Can delete an entry, archive a source, or take a source out of Today. Removing a source confirms.

## Settings

`Features/Settings/SettingsView.swift`

- Reading: font, text size, focus mode. A preview of the type.
- Accounts & Sync: FreshRSS (connect, sync, disconnect with confirmation). iCloud folder or Google Drive library file (choose folder, choose file, manual or automatic sync, stop using folder with confirmation, conflict dialog if both sides changed).
- Storage, section header Library: how long to keep articles (3 days through Forever). Queue items are kept.
- Video & AI: Gemini API key, Experimental librarian.
- Import & Export: OPML in and out.
- About: edition.

## Onboarding

`Features/Onboarding/OnboardingView.swift`. Three pages. No skip-all.

1. “Today, one piece.” Queue is mentioned as the place you save stories.
2. “Your RSS collection.” Continue, or “I’ll connect FreshRSS later”.
3. “Read. Watch. Continue.” Start reading. A short mark animation, then the shell.

## Sheets, alerts, and dialogs

| Surface | Trigger | Role |
|---|---|---|
| Takeaway sheet | Done in the reader | One sentence and one of four choices, then finish |
| Focus sheet | Reading menu | How the focus highlight follows the text |
| Add Source | Today, Feed, Sources, share | Paste feeds |
| Add to Queue | Queue | Link, file, or existing story |
| Folder icon | Tap emoji | Pick a glyph, applies immediately |
| New folder alert | Add source or sources | Name, then Create |
| Video summarize dialog | Opening a YouTube item that has no summary | Summarize or Not now |
| Gemini key sheet | Summarize or ask without a key | Save key |
| Video chat | Ask on a video | Chat about that video |
| Remove source | Sources | Confirms, deletes local articles |
| Remove empty folder | Sources | Confirms |
| Disconnect FreshRSS | Settings | Confirms, local articles stay |
| Stop using folder | Cloud library | Confirms, does not delete the cloud file |
| Cloud conflict | Sync | Keep this device, or use cloud file |
| OPML result | Settings | Alert titled OneFeed with the count or the error |
| Reader and queue errors | Failed update or summary | Alert, OK |

## How a story moves

```
Ingest → Today deck or Feed list
Done → History (read) + optional takeaway
Queue → Queue tab (state saved)
Skip → History (skipped)
Not interested → History (skipped) + Not interested log
Close → stays where it was
```

Stars do not move the story. They are a 1–5 rating stored on the article and shown as ★ in the row. The four takeaway choices (Learned, Why, Connect, Use) are separate and are not stars.
