# Accessibility

The app already does a lot of this in the reading list and the reader. The gaps are places that did not get the same rule.

## What is in good shape

- `ArticleRow` combines children for VoiceOver, drops line limits at accessibility sizes, hides the decorative “now reading” bar, and says the row opens the article.
- Folder emoji button has a label, a hint, and a 44 pt target. The picker marks the selected glyph.
- Toolbar refresh swaps to an “Updating” label instead of a silent spinner.
- The decision curtain has an accessibility label for the outcome, and it respects Reduce Motion.
- Takeaway chips have the word as the label, the prompt as the hint, and a selected trait. The emoji is hidden from VoiceOver.
- Focus sheet and takeaway sheet grow to a large detent at accessibility sizes.
- Star control: one button per star, selected trait, group label.
- Refresh banner is a live region when it is on screen.
- Onboarding says “Page N of 3”.
- Many icon toolbar buttons have accessibility labels (Add source, Librarian, reading options, Close).

## Gaps to fix

These match findings 8–12 in `04-findings.md`.

1. Reduce Motion is not consulted by the reader’s `.animation` modifiers, the refresh banner, star taps, or some list mutations. Fix the call sites. Do not add motion elsewhere until this is true.
2. Source rows, folder edit rows, reader bar captions, and takeaway chip labels use `lineLimit(1)` with no accessibility-size escape. `ArticleRow` already has the escape. Use it.
3. The settings reading preview limits lines more at accessibility sizes than at normal sizes. That is backwards.
4. Add to Queue, the folder emoji sheet, and the Gemini key sheet use fixed medium and large detents. Focus and the takeaway sheet do not. Match those.
5. Mac Close and the reading menu are 28×28. The iPhone focus control is 44 wide and 28 tall. Hit targets should be at least 44×44 even if the glyph stays small.
6. Queue’s VoiceOver label does not change when the icon fills. Say “In Queue” after it is parked.
7. Folder expand and collapse hides the chevron and does not expose expanded or collapsed as a value.

## Contrast and color

Ink on paper and ink on plaster are the text pairs. Graphite is secondary. Sand is for rules and unselected strokes, not for body text. Status is not color alone on History (the words Read, Skipped, Not interested are there). The Queue filled icon is the exception: pair it with a label change, not a new color.

Do not introduce a second accent for the four takeaway choices. Selected is ink fill and plaster text, same as Focus chips. Unselected is paper, ink text, sand stroke.

## Dynamic Type

The reader bar already restacks at accessibility sizes: Done becomes a full-width button, and Not interested becomes visible. Keep that. Do not solve clipping by shrinking type.

The takeaway field is a vertical text field, two to four lines, serif. The prompt above it is the question. The placeholder is “In your own words”. That split is correct for VoiceOver because the field’s accessibility label is the prompt, not the placeholder.

## Keyboard and pointer

Mac uses the same reader actions. Close must stay a button, not only a gesture. Sheets use the system dismiss. Do not add a custom drag that the keyboard cannot reach. Skip and Save are toolbar buttons, so they are in the keyboard focus order.

## Reduced motion, again

When it is on: no slide, no scale, no spring on the curtain, no particle burst, no hold-before-dismiss delay. Opacity changes that explain a mode switch can stay under 200 ms. Haptics can stay on commit. They are not vestibular.
