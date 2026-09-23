# User flows

Each flow is entry → actions → decision → feedback → completion → next. Stuck points are where the next step is unclear or missing.

## Read today’s piece

Entry: tab Today, tap the featured story or a row. Mac may already be showing the reader.

Actions: read. Then Queue, Skip, Done, Share, or Browser. Not interested is a long-press on Skip, or a context menu.

Decision:

- Done opens the takeaway sheet before anything is marked read.
- Queue, Skip, and Not interested skip that sheet.

Feedback:

- Takeaway: four chips and a short field. Skip or empty Save writes nothing new. Save with a choice or a sentence stores it.
- Then the decision curtain (check, stack, or skip) and the reader closes.
- Today’s count drops. Clearing the deck plays a small burst and “You’re all caught up”.

Completion: the story leaves Today.

Next: the next Today row. On Mac the next story can open on its own. Queue is the place to find something you parked.

Stuck:

- Done always costs a sheet, even when you only wanted to mark it read. Skip on the sheet is one tap, so the cost is the appearance of the sheet, not a form. That pause is intentional.
- If you type a sentence and then drag the sheet down, the sentence is thrown away and the story is still marked read. The gesture feels like dismiss, but it commits the read and drops the draft.
- Skip and Not interested cannot be undone from History.
- A full-screen Updating cover blocks Today while sources refresh.

## Park something for later

Entry: Queue in the reader, swipe Queue on a list, or Queue tab → Add.

Actions: confirm nothing. Queue applies immediately. Add to Queue: paste, clipboard, file, or a feed row.

Feedback: reader curtain for a queued finish (longer hold, about 520 ms). Add to Queue dismisses the sheet on success. Errors stay inline (“That doesn’t look like a link.”, YouTube channel URLs are refused and told to be added as a source).

Completion: the item is on the Queue tab. State name in code is `saved`.

Next: open it from Queue whenever.

Stuck:

- The reader button is Queue. Onboarding says “Save stories in Queue”. FreshRSS settings say “Done and Save sync”. Stars are a third “I liked this” control. Three vocabularies for keeping something.
- Remove from Queue exists, so a mis-tap here is recoverable. Skip is not.

## Skip or set aside

Entry: Skip in the reader or on a swipe. Not interested is secondary: context menu, long-press, or the accessibility stack where it is a visible button.

Feedback: short curtain for skip. Not interested also writes a log entry. No confirmation, no undo toast.

Completion: History, status Skipped or Not interested. The story leaves Today and Feed.

Next: History → Not interested if you want to review what you set aside, archive that source, or take it out of Today. You cannot put the article itself back.

Stuck:

- Not interested is the taste signal the app wants, and it is the hardest finish action to find on iPhone.
- The takeaway sheet’s cancel button is also labeled Skip. That Skip does not skip the article. It finishes it as read. Same word, opposite outcome.

## Add a source

Entry: Feed → Add Source, Sources → +, Today empty state, or a shared URL.

Actions: paste URLs, choose Unfiled or a folder, optional New Folder, tap Add.

Feedback: “Adding…” then a short Added overlay (about 420 ms) and the sheet closes. Failures stay on the sheet, including a partial “Added X, Y failed.”

Completion: the source is in Feed. Stories show up after a refresh.

Next: open the folder, or wait for Today.

OPML is a different door: Settings → Import & Export → Import OPML. A file picker, then an alert. No preview of what will be added. Existing URLs only gain folders. A file that adds nothing can still look like success with a zero count.

## Reopen a finished story

Entry: Queue → History, or History inside Feed. Days, then a row.

Actions: read again. The same Done button opens the takeaway sheet, which is how you edit a sentence later.

Feedback: the note saves. The read/skipped state does not change, because History’s finish handler only closes the reader.

Completion: back on the list. The row can show the choice word and one line of the sentence.

Next: none offered. No restore, no “read again later”, no jump to the source beyond what the row already shows.

Stuck: people who skipped by accident land here and have nowhere to send the story back.

## Change a folder icon

Entry: tap the emoji on a folder row, or Change icon in the context menu. The rest of the row opens the folder.

Actions: sheet Folder icon. Tap a glyph. It saves and closes. Close leaves the old glyph.

Feedback: the list refreshes. No confirmation. Appropriate, because it is easy to change again.

## Connect an account

FreshRSS: Settings → Accounts & Sync → Connect. Server, username, API password. Errors stay on the sheet. Disconnect confirms and keeps local articles.

Cloud library: choose a folder or an existing `OneFeed.library.json`, or Google Drive. Sync can be manual or automatic. Stop using the folder confirms and does not delete the file. If both copies changed, the dialog is explicit: Keep this device, or Use cloud file (destructive).

Gemini: Settings → Video & AI, or the first time you summarize or ask. The key sheet is easy to miss if you never open a video.

## First launch

Three pages, Continue, then Start reading. Page 2 can defer FreshRSS. There is no way to jump straight to Today. The copy teaches Today, Queue, and Done in three sentences. It does not mention Skip, Not interested, folders, or the takeaway sheet. The takeaway is the first surprise after the first Done.
