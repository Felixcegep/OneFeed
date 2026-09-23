# Design system

Use what is in `DesignSystem/`. Do not add a parallel set of colors, fonts, or button styles.

## Materials

From `OneFeedTheme` and `OneFeedPalette`:

- Plaster is the canvas. Paper is the group, the reader, and the sheet.
- Ink is primary text and the selected chip. Graphite is secondary. Sand is the hairline and the unselected stroke.
- Accent is for the rare attention mark, not for titles or body.
- Sage is the Done color. Do not use accent for Done.
- Serif (`serifDisplay`, `serifBody`) is for reading and for the takeaway sentence. Sans is for chrome, rows, and buttons.
- Page padding is 20. Row corner radius is 10. Cards are 12. Capsules are for buttons, not for whole sections.
- Folders are identified by an emoji the person picked, not by a colored bar.

## Components to reuse

| Component | Use |
|---|---|
| `EmptyLibraryState` | Every empty list. Title, icon, one sentence, one or two actions |
| `ArticleRow` | Story rows. It already shows the takeaway line when one exists |
| `PrimaryActionStyle` | The one main button on a screen |
| `InkCapsuleStyle` / `DecisionActionStyle` | Compact reader actions |
| `DirectoryRowButtonStyle` | List rows that are buttons |
| `GallerySectionHeader` | Section titles. Graphite, readable, not tiny uppercase stone |
| `OneFeedReadingSplit` | List plus reader on Mac, cover on iPhone |
| `FolderEmojiPicker` | Any folder glyph change |
| `RefreshProgressBanner` | Refresh status that must not hide the list |
| `OneFeedDecisionCurtain` | The beat after Queue, Done, or Skip |

## Inconsistencies

- Reader bar items are plain buttons. The rest of the app uses the press styles above.
- Some empties go through `EmptyLibraryState`. Confirm new screens do too, including error screens that are actually empty lists.
- Alerts that report a result are titled “OneFeed”. The title should be the outcome.
- `LibraryView` is a second navigation model (Sources, History, Settings) that the tab bar replaced. Do not link it.
- Stars (`ArticleRatingControl`) and takeaway choices are both “how I felt” unless the words stay apart. See finding 13.
- Button label Done is used for finishing an article, closing Focus, and leaving folder edit mode.

## Terminology to standardize

| Say this | Do not also say |
|---|---|
| Queue | Save, when you mean the waiting list |
| Done | as the reading verb only |
| Not now | on the takeaway sheet, instead of Skip |
| Skip | only for setting a story aside |
| Not interested | the same string in the menu, the log, and History |
| Feed | the tab of folders and stories |
| Sources | the manage screen |
| Folder | a group of sources |
| Today | the daily deck |

FreshRSS sync can mention that Queue matches the remote star. Say that in the settings footer. Do not rename the tab to Save.

## Spacing rule already in the product

Space between sections is larger than space between rows. Paper groups sit on plaster. Do not switch a screen to a full-bleed list with hairline separators unless that screen already works that way.

## What not to add

- A new typeface.
- A card around every row.
- A floating action button.
- A fifth tab.
- A sixth reader action.
- Shadows as a way to show hierarchy. Paper on plaster is the hierarchy.
