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

## Still open

- Today does not top up an exhausted daily deck when refresh finds new stories. `generateIfNeeded` keeps the existing deck for the calendar day.
- Today rows do not show Feed’s “more sources” or “already read” captions. The deck already keeps one story per cluster.
- Swiping the takeaway sheet closed still marks the article read. That matches Done → optional note. A draft is not saved on swipe.
- `SemanticMemoryPass` still fetches the whole library on the ingest actor during “Building today.”
- Article thumbnails still decode full images for 64pt slots.
- Search filters on every keystroke. The work is in memory, not a network call.
- No Xcode on this machine, so the new progress test has not been executed here.
