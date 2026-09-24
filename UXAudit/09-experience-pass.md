# Experience pass

Running notes for the app-quality pass. Product identity stays plaster, paper, warm ink, and serif reading.

| Issue | Screen | Severity | Cause | Fix | Validation |
|---|---|---|---|---|---|
| Progress line overlaps rows and the large title on a fast scroll to the top | Today, Feed, Settings | Critical | The line was an `overlay` on the scrolling screen, above content and outside the scroll-edge contract | `safeAreaBar(edge: .top)` pins it to chrome. The fill is a clipped scale, not a `ProgressView` that animates its own width | Layout review. Needs a device pass for status-bar tap, pull to refresh, and backgrounding |
| Progress line jumps backward when refresh changes phase, and again when it finishes | Today, Feed | High | `begin` zeroed `completed` for sync. `finish` zeroed the fraction while the line was still visible | Later phases carry completed work. `displayedFraction` only increases. `finish` leaves the width in place so the line fades out | `RefreshProgressTests.aLaterPhaseDoesNotSnapTheLineBackward` |
| Line flashes for a very short refresh | Today, Feed, Settings | Medium | The line appeared on the same frame refresh started | The line waits 160ms and hides immediately if the task is cancelled | Code review. Needs a device pass |
| Pull to refresh on Today always started a second full refresh | Today | High | `refresh()` awaited the in-flight task and then started another | Joining a full refresh returns when that task finishes. A utility backfill still continues into a real refresh | Code review |
| Pull to refresh on Feed was ignored while a refresh was running | Feed | High | `guard !isRefreshing else { return }` | The second pull waits for the in-flight task | Code review |
| Empty Today showed a full-screen cover and a second pulsing mark | Today | Medium | Cover and caught-up view both animated | Cover owns the fade. The view underneath keeps a still mark | Code review |
| Cover fade animated the whole column | Today, Feed | Medium | `.animation` sat on the list, not the cover | Animation is on the cover `ZStack` only | Code review |
| Finishing a story that is not the current deck item left Today without a current story | Today | High | Deck sync wrote the item status and did not promote the next queued item | `ArticleActions` promotes the next stored queued item and updates the widget | Code review. Needs a deck test on a Mac with Xcode |
| Feed list had no hard top scroll edge | Feed | Medium | Folders omitted `oneFeedScrollEdge` | Same hard top edge as Today | Code review |
| Settings showed two progress lines while a page was pushing | Settings | Medium | Root and every pushed form attached the banner | Banner stays on the settings root | Code review |
| Sources empty actions and section titles used system chrome | Sources | Medium | `.borderedProminent` and string section titles | Ink capsule and `GallerySectionHeader` | Code review |
| Focus dot and Undo were short of 44pt | Reader, undo banner | Medium | Frames were 28pt and 36pt | Minimum 44pt height. The focus dot stays visually small | Code review |
| Primary buttons tapped a haptic on press and again on release | Shared buttons | Low | `sensoryFeedback` followed `isPressed` both ways | Haptic only when the press begins | Code review |
| Finished Today stayed empty after refresh found new stories | Today | High | `generateIfNeeded` returned the existing deck and did not fill open slots | When no story is still open, the same deck appends a new batch. An open story is left alone | `DailyDeckTests.finishedDeckRefillsWhenNewStoriesArrive` |
| Today hid the “already read” line Feed shows | Today | Medium | Rows did not read `ContentMemory.matchedConsumedAt` | Featured story and list rows show that caption | Code review |
| Thumbnails decoded the full image for a 64pt slot | Today, Queue, Feed | High | `AsyncImage` decoded the network bitmap at full size | `ThumbnailCache` downsamples with ImageIO and keeps 64 images | Code review |
| Each new story was compared with every stored vector | Today build | High | Classification scanned memories in other languages | Only the same language and embedding revision are scored | Code review |
| Search regrouped the feed on every keystroke | Feed, Queue, History | Medium | The field and the filter shared one string | The field stays live. The filter waits 180ms, and clears immediately | Code review |
| Reader alerts showed raw errors | Reader | Medium | `localizedDescription` included API text | Gemini copy stays. Other failures use one plain sentence | `RetentionAndExtractionTests.readerFailuresStayInPlainLanguage` |
| Asking about a video kept running after the sheet closed | Reader | Medium | The ask task was unstructured | The sheet cancels that task on disappear | Code review |
| Building Today loaded every article body and every vector | Today build | High | `prepare` fetched full articles and unpacked every memory | HTML stays a fault until a story is embedded. Vectors unpack only for the language being scored. Deck placement and captions skip vector blobs | Code review |
| Today hid other sources for the same story | Today | Medium | The deck keeps one slot and did not mention the rest | The row uses Feed’s “N more sources about this story” line. It does not expand those sources on Today | `SemanticDeckTests.oneStoryClusterFillsASingleTodaySlot` |
| Queue and import alerts showed system errors | Queue, Sources, Settings | Medium | `localizedDescription` included SwiftData and file-system text | App errors keep their sentence. Other failures use a short fallback. A dropped connection does not raise an alert | `RetentionAndExtractionTests.queueErrorsUseAppSentences` |
| The progress line reserved space while idle | Today, Feed, Settings | Medium | The top bar was always 2pt tall | The bar’s height is 0 until the line is actually shown | Code review |
| The in-app browser spinner sat on top of the page | Reader browser | Medium | A `ProgressView` overlay was pinned to the top of the web view | Loading uses the mark in the toolbar, so the page can scroll freely | Code review |

| The video summary prompt could return on the same visit | Reader | Medium | `.task` ran again and offered the dialog whenever the reader reappeared | The prompt is offered once per article. Starting a summary replaces one that is already running | Code review |
| Focus options used a fixed sheet height | Reader | Medium | The detent was locked at 340pt, and the mode chips were 36pt tall | The sheet uses medium and large detents, and each mode is at least 44pt | Code review |
| iPhone Close skipped the reader’s close callback | Reader | Medium | The toolbar called `dismiss()` while Mac called `onClose` | Both paths use `closeReader()`, so the list clears the open story | Code review |

## Still open

- Swiping the takeaway sheet closed still marks the article read. A changed note or choice is already kept as a draft.
- No Xcode on this machine, so the new tests have not been executed here. Scroll-to-top of the progress line still needs a device pass.
