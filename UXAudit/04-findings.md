# Findings

Severity is Critical, High, Medium, or Low. Critical means people lose work or cannot recover a normal action. Nothing here is Critical in the sense of data loss across the library. The draft-loss case is the closest.

## 1. Swiping the takeaway sheet drops the sentence

- Location: `Features/Reader/ReadingTakeawaySheet.swift`, dismissed from `ReaderView.beginFinishRead`.
- Current behavior: Skip, empty Save, and swipe all dismiss the sheet and then mark the article read. Only Save with a choice or text writes the takeaway.
- Problem: a filled-in sheet is discarded by the system dismiss gesture.
- Why it is friction: the person did the hard part (recall) and lost it to a habitual swipe.
- User impact: the memory note is gone. The article still leaves Today, so they may not notice until History.
- Recommended change: if the text or choice differs from what is stored, keep that draft on the article before dismiss. Empty swipe still finishes as read.
- Expected result: the gesture finishes reading without deleting what they wrote.
- Severity: High
- Type: Missing friction

## 2. Skip on the takeaway sheet marks the article read

- Location: takeaway toolbar button “Skip”. Reader bar button “Skip”.
- Current behavior: sheet Skip completes Done. Reader Skip sets state skipped.
- Problem: one label, two outcomes.
- Why it is friction: the word was learned on the reader bar minutes earlier.
- User impact: a story they meant to set aside is filed as read.
- Recommended change: sheet button label Not now. Accessibility hint: “Marks this article read without a note.”
- Expected result: Skip always means set aside.
- Severity: High
- Type: Content / terminology

## 3. No undo for Skip or Not interested

- Location: reader bar, list swipes, `ArticleActions`.
- Current behavior: both apply immediately. History can show them. It cannot restore them. Not interested can be deleted from its log, which does not return the article to Today.
- Problem: irreversible, high-frequency actions with no recovery.
- Why it is friction: mistakes are normal when the control sits next to Done.
- User impact: a mis-tap removes the story from the daily set.
- Recommended change: a short undo at the bottom of Today and Feed after Skip or Not interested. Prefer undo over a confirmation dialog. Queue already has Remove from Queue. It can share the undo chip.
- Expected result: accidents take one tap to reverse. Deliberate skips stay one tap.
- Severity: High
- Type: Missing friction

## 4. Queue, Save, stars, and Library name the same ideas differently

- Location: tab Queue, onboarding “Save stories in Queue”, FreshRSS footer “Done and Save sync”, star menus, Settings section Library, unused `LibraryView`.
- Current behavior: parked stories are Queue in the tab and Saved in code, sync copy, and some section headers. Stars do not park anything. Library is the cloud file, the retention section, and a screen that is not in the tab bar.
- Problem: the person cannot predict which control keeps a story.
- Why it is friction: the same outcome is described with the verb from a different product (FreshRSS stars).
- User impact: people star something and expect it in Queue, or they look for Library in the tab bar.
- Recommended change: user-facing copy says Queue for parked items. Stars stay a rating. The retention section should not be titled Library. Leave `LibraryView` unused or delete it so it cannot be linked later under a third meaning.
- Expected result: one noun for the waiting list.
- Severity: High
- Type: Content / terminology

## 5. Not interested is undiscoverable on the iPhone bar

- Location: `ReaderView` context menu on Skip. Visible only in the accessibility-size stack.
- Current behavior: long-press Skip, or a list context menu.
- Problem: the action that trains the library is the one with no visible label on the primary bar.
- Why it is friction: hidden controls do not get used, so the set-aside log stays empty and Today does not get better.
- User impact: people mash Skip instead, and lose the grouping by source.
- Recommended change: do not add a sixth bar icon. Put Not interested in the reading menu with the same words as the context menu, and offer it on the undo chip after Skip.
- Expected result: the action is findable without crowding Done.
- Severity: Medium
- Type: Discoverability

## 6. History cannot send a story back

- Location: `HistoryView`. Finish handler ignores the new state.
- Current behavior: reopen, edit a takeaway, close. No queue action.
- Problem: the archive has no forward action.
- Why it is friction: the recovery path for finding 3 ends at a row you can only re-read.
- User impact: skipped stories are stuck unless the person hunts the original feed.
- Recommended change: swipe or menu, Put back in Queue. It should call the same restore path Queue already uses.
- Expected result: History is a place you can act, not only look.
- Severity: Medium
- Type: Workflow

## 7. Refresh replaces the list with a cover

- Location: `CurrentView`, `FoldersView`, `OneFeedLoadingCover`.
- Current behavior: a full-screen updating state. `RefreshProgressBanner` already knows how to show inline progress.
- Problem: existing stories disappear while new ones load.
- Why it is friction: the app feels slower and blocks the thing the person opened the tab to do.
- User impact: they wait on a cover instead of reading what is already there.
- Recommended change: inline banner. Full-screen cover only when the list is empty.
- Expected result: refresh feels like an update, not a navigation.
- Severity: Medium
- Type: Performance

## 8. Reader animations ignore Reduce Motion

- Location: `ReaderView` animations on decision, extracting, summarizing, and mode. Also `RefreshProgressBanner`, `ArticleRatingControl`, `SavedView.restore`, `ArticleActions` list animation.
- Current behavior: the curtain itself respects Reduce Motion. The parent `.animation` modifiers do not. Several list updates always animate.
- Problem: the setting does not cover the reading surface, which is where motion is most visible.
- Why it is friction: vestibular settings are not optional polish.
- User impact: mode switches and the decision overlay still move when the person asked them not to.
- Recommended change: one helper, already the pattern in button styles: if Reduce Motion, animation is nil. Use it on those call sites. Haptics on press can stay. Large moves cannot.
- Expected result: Reduce Motion means opacity or an instant change on those screens.
- Severity: Medium
- Type: Accessibility

## 9. Large type clips names and reader labels

- Location: folder edit rows and source rows (`lineLimit` with no accessibility escape). Reader bar captions `lineLimit(1)`. Takeaway chip labels `lineLimit(1)` with a scale factor. Settings reading preview caps lines at accessibility sizes, which is the reverse of `ArticleRow`.
- Current behavior: `ArticleRow` already drops the line limit when the type size is an accessibility size. These other rows do not.
- Problem: the component that got the rule is not the rule.
- Why it is friction: titles and button names are how you tell sources apart.
- User impact: truncated source names and a reader bar whose captions collide or clip.
- Recommended change: same escape `ArticleRow` uses. The reader bar already stacks at accessibility sizes. Keep that, and do not ellipsize the stacked labels.
- Expected result: large text wraps instead of disappearing.
- Severity: Medium
- Type: Accessibility

## 10. Some sheets do not grow for large type

- Location: `AddToQueueView`, `FolderEmojiPicker`, Gemini key sheet. Fixed medium and large detents.
- Current behavior: Focus and the takeaway sheet switch to a large detent for accessibility sizes. These three do not.
- Problem: the same form pattern was implemented twice.
- Why it is friction: the field and the buttons end up under the keyboard or below the fold.
- User impact: adding a link or picking an emoji is harder at the type size the person chose.
- Recommended change: copy the detent rule from `ReaderFocusSheet`.
- Expected result: those sheets open tall enough to scroll the whole form.
- Severity: Medium
- Type: Accessibility

## 11. Mac reader chrome is 28 points

- Location: Mac `readerTopBar` Close and reading-options control, frames 28×28. The focus dot on iPhone is 44×28.
- Current behavior: iPhone toolbar buttons are closer to 44. These are not.
- Problem: the hit target is the glyph, not the padding around it.
- Why it is friction: pointer users still mis-hit small toolbar buttons, and iPad pointer or touch uses the same reader.
- User impact: Close and the reading menu are fiddly.
- Recommended change: 44×44 hit area, glyph can stay visually small.
- Expected result: the controls match the iPhone bar.
- Severity: Low
- Type: Accessibility

## 12. VoiceOver does not hear that Queue is already on

- Location: reader Queue item. Filled icon when `decision == .saved`. Label stays “Queue”.
- Current behavior: sighted users see a filled stack. VoiceOver hears the same word as before.
- Problem: state is color and weight of the icon only.
- Why it is friction: the action’s outcome is invisible to the reader user.
- User impact: they cannot tell the tap landed until the curtain, and the curtain may be reduced.
- Recommended change: label “In Queue” once the state is saved, hint unchanged.
- Expected result: the state change is spoken.
- Severity: Low
- Type: Accessibility

## 13. Two scores on one story

- Location: star menu on rows. Four takeaway choices after Done.
- Current behavior: both can be set. They sync differently (stars stay on device; the takeaway is in the library file).
- Problem: nothing in the UI says they are different questions.
- Why it is friction: “how good was it” and “what will I remember” get mixed.
- User impact: people use stars as a note, or ignore the sentence because they already starred it.
- Recommended change: leave both. In the takeaway sheet, do not show stars. In the row menu, keep Rate as the star label. History already shows the sentence. That is enough if the words stay distinct.
- Expected result: no merged widget. Less confusion because they never appear on the same screen as equal choices.
- Severity: Low
- Type: Content / terminology

## 14. OPML applies, then explains

- Location: Settings → Import OPML.
- Current behavior: parse and insert, then an alert titled OneFeed.
- Problem: no preview, generic title, a zero-import file is hard to tell from success.
- Why it is friction: import is rare and high impact. A surprise folder list is expensive to undo by hand.
- User impact: a wrong file changes the source library before the person can stop it.
- Recommended change: show new vs already-present counts, then Import. Title the result with the count.
- Expected result: import is a review, not a surprise. This is appropriate friction for a bulk change.
- Severity: Medium
- Type: Missing friction

## 15. Experimental librarian has two names

- Location: Feed toolbar accessibility label Librarian. Settings row Experimental librarian. Screen title Experimental.
- Current behavior: three labels for one tool that also needs a Gemini key.
- Problem: it sounds unfinished in one place and like a feature in another.
- Why it is friction: low, because it is optional. It still breaks the rule that one object has one name.
- User impact: someone who opens it from Feed does not recognize the settings row that configures it.
- Recommended change: one name. If it is not ready for the toolbar, remove the toolbar entry and leave it in Settings.
- Expected result: one door, one title.
- Severity: Low
- Type: Content / terminology

## 16. iPhone reader bar does not press in

- Location: `readerBarItem` uses a plain button. `PrimaryActionStyle` and `InkCapsuleStyle` scale to 0.97 and are skipped when Reduce Motion is on.
- Current behavior: the accessibility-size Done button presses in. The five standard icons do not.
- Problem: the most-used controls are the ones without press feedback. The curtain arrives late, after the takeaway sheet, so Done feels like it did nothing until the sheet appears. Queue and Skip feel flat until the curtain.
- Why it is friction: the tap and the result are separated.
- User impact: double taps, especially on Done, which now presents a sheet and ignores a second tap only after `showingTakeaway` is set.
- Recommended change: use the existing press style on the bar items. Present the sheet immediately, which already happens. Do not add a second animation on top of the sheet.
- Expected result: the finger gets a response on touch-down. The sheet or the curtain is the commit.
- Severity: Low
- Type: Interaction
