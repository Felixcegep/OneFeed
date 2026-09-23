# Friction map

Friction is useful when it stops a mistake or makes a moment of attention. It is harmful when it repeats, hides the next step, or uses the same word for two outcomes.

## Harmful friction

### The takeaway sheet throws away a typed sentence

You open Done, write what you learned, and drag the sheet down because that is how iOS sheets close. The sentence is discarded. The article is still marked read. The pause was supposed to help memory. The gesture punishes the person who used it.

Fix: if the field or the choice changed, swiping should not silently drop it. Keep the draft on the article, or confirm only when there is unsaved text. Empty swipe can still finish as read.

### Skip means two things

On the reader, Skip sets the story aside and sends it to History as skipped. On the takeaway sheet, Skip marks it read. Someone who learns “Skip = I don’t want this” will tap the sheet’s Skip and archive the article as finished.

Fix: rename the sheet button to Not now. Leave Skip for the reader only.

### Not interested is hidden on the main path

On a normal iPhone bar it is a long-press on Skip. The accessibility layout shows it as its own button, which is the clearer design. The action changes what Today will offer later, and most people will never find it.

Fix: keep it off the five-slot bar, but after Skip show a one-line undo that includes “Not interested” as the stronger choice. Or surface it once, in the reading menu, with the same label.

### History is a dead end

Skipped and read stories can be reopened and nothing else. There is no path back to Queue or Today. The only recovery for “I skipped the wrong one” is to hope it is still in the feed and find it again.

Fix: row action, Put back in Queue. For Not interested, the source-level tools already exist. The article itself still needs a way back.

### Three “keep” languages

Queue (the button and the tab), Save (onboarding and FreshRSS sync copy), and stars (a rating that does not queue). Plus Library, which means a cloud file in one place, a retention setting in another, and an unused screen in a third.

Fix: say Queue everywhere the story is parked. Say stars only for the 1–5 rating. Reserve Library for the sync file, or stop using the word on the retention screen.

### Done means three things

Mark the article read. Close the Focus sheet. Finish editing a folder. The takeaway sheet correctly uses Save, not Done. Focus still uses Done for “close this panel”.

Fix: Focus and folder editing should say Close or a verb that is not the reading verb.

### Refresh blocks the screen

Today and Feed can put up a full-screen Updating cover. The person cannot keep reading the list they already have. The progress banner elsewhere is the better pattern.

Fix: keep the list on screen. Show the existing progress banner. Reserve a full-screen cover for first load when there is nothing to show.

### OPML import has no review

A file is applied immediately. You see a count afterward. A bad export, or a file that only merges folders, is hard to understand from an alert titled OneFeed.

Fix: a short review: N new sources, N already here, then Import. The alert title should say what happened (“Imported 12 sources”), not the app name.

### No article search

Sources can be searched. Stories cannot. After a few weeks of History and Queue, finding “that piece about nonces” means scrolling. The takeaway sentence makes this worse, because the sentence is the thing you would search for, and it is only visible on the row.

Fix: search on History and Queue that matches title and takeaway text. Not a new tab.

## Necessary friction

Keep these. The amount is about right.

| Action | What the app does | Verdict |
|---|---|---|
| Remove a source | Confirms, and says local articles go with it | Right |
| Remove an empty folder | Confirms | Right. Low stakes, but the folder name is the emoji key, so removing it is real |
| Disconnect FreshRSS | Confirms, and says local articles stay | Right |
| Stop using a cloud folder | Confirms, and does not delete the cloud file | Right |
| Cloud file conflict | Forces a choice: this device or the cloud file. Cloud is marked destructive | Right. Do not add a third “merge somehow” button |
| Summarize a video | Asks once, because it spends the API key | Right |
| Takeaway after Done | One sheet, one tap to leave, no keyboard until you tap the field | Right amount, if the draft is not lost on swipe |
| New folder name | Alert with Create and Cancel | Right |

Do not add confirmation dialogs to Queue, Skip, or Done. Those happen many times a day. Undo is the right protection.

## Missing intentional friction

### Skip and Not interested commit forever

One tap. No undo. Not interested also trains the library. A confirmation dialog would be too much. A few seconds of undo at the bottom of Today (“Skipped. Undo”) is the right weight. Not interested should use the same pattern, with a slightly longer window, because it also files the source in the set-aside log.

### Takeaway draft vs swipe

Covered above. The missing mechanism is: unsaved text is either kept or explicitly discarded. Not silently dropped.

### Queue is already safe

Remove from Queue exists. Do not add a dialog. Optional: the same undo chip, so you do not have to switch tabs to undo.

### Stars and the four choices

Two scoring systems on one article. Stars are a quiet menu. The four choices are a memory prompt (what you learned, why, what it connects to, what you will do). That split is good. Do not merge them into one rating. Do label them so a star never looks like the takeaway.

### First Done of the day

The sheet is the product teaching the habit. Missing piece is a single line under the title the first time: “One sentence is enough. Not now leaves it unread in your head, and marks the piece read.” People need to know Not now still finishes the article. If the button is renamed Not now, that sentence can be shorter.
