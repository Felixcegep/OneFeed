# Priorities

Clarity, then predictability, then recovery, then feedback. Visual polish is last because the materials are already decided.

## Quick wins

Small, local, and worth doing first.

1. Rename the takeaway sheet’s Skip to Not now. Hint: marks the article read without a note.
2. If the takeaway text or choice changed, save that draft when the sheet swipes away. Do not drop it.
3. After Skip or Not interested, show undo for a few seconds. No confirmation dialog.
4. VoiceOver: Queue becomes “In Queue” once the story is parked.
5. Pass Reduce Motion into the reader’s `.animation` modifiers and the other call sites in `05-motion.md`.
6. Give Add to Queue, the emoji sheet, and the Gemini key sheet the same large accessibility detent as Focus.
7. Let source titles and reader labels wrap at accessibility sizes, the way `ArticleRow` already does.
8. Make Mac Close and the reading menu a 44 pt hit target.
9. Use the existing press style on the iPhone reader bar.

## Larger improvements

These change a flow, not a label.

1. History: Put back in Queue, using the restore path Queue already has.
2. Not interested in the reading menu, and on the undo chip after Skip. Still not a sixth bar button.
3. Refresh stays inline unless the list is empty.
4. OPML import shows new vs already-present, then imports. The result alert states the count.
5. Search titles and takeaway sentences in Queue and History.
6. One pass on the words Queue, Done, Skip, Feed, and Library, using the table in `07-design-system.md`. Includes the FreshRSS footer and the Storage section header.
7. Remove or isolate `LibraryView` so Library stops meaning three things.

## Systemic problems

### One word, several jobs

Done, Skip, Save, and Library each mean more than one thing. People can learn a quiet app. They cannot learn an app where the same button does opposite things. Fix the vocabulary once, in the strings, instead of adding tooltips per screen.

### Frequent actions commit with no way back

Remove source, disconnect, and cloud replace all confirm. That is correct. They are rare. Skip, Not interested, and a swiped-away note are common, and they do not confirm and do not undo. The missing pattern is undo for reading actions. Do not spread confirmation dialogs into the reader.

### Accessibility and motion are implemented per screen

`ArticleRow`, Focus, and the takeaway sheet know about large type and Reduce Motion. The reader bar, source rows, Add to Queue, and several `.animation` modifiers do not. The fix is to copy the existing rule, not to design a new one. A new screen should be checked against `ArticleRow` and `ReaderFocusSheet` before it ships.

### The archive does not continue the task

Today and Queue tell you what to do next. History tells you what you did. After a mistake, or when a takeaway makes you want the story again, the next action is missing. Put back in Queue is the action that makes History part of the loop.

## Do not change

- The four-tab shell.
- The five-slot reader bar.
- The takeaway pause after Done. It is intentional. One sentence, keyboard stays down until the field is tapped, Not now is one tap.
- The four choices: Learned, Why, Connect, Use. They are memory prompts, not a mood picker. Stars stay separate.
- Plaster, paper, ink, serif for the sentence.
- Confirmation on remove source, disconnect, and cloud replace.
