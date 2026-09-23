# Motion

Tokens live in `DesignSystem/OneFeedMark.swift` as `OneFeedMotion`. The comment says quiet paper motion, 200–350 ms, one low-bounce spring for decisions.

| Token | Value | Used for |
|---|---|---|
| press | 0.2s easeOut | Button scale 0.97, takeaway chip selection |
| dots | 0.2s easeInOut | Onboarding page dots |
| list | 0.3s easeInOut | Folder edit, some list updates |
| overlay | 0.3s easeOut | Covers, banners, unread count |
| reveal | 0.3s easeOut | Thumbnails, takeaway prompt, sheet growing when the field focuses |
| page | 0.35s easeInOut | Onboarding pages, reader mode switch |
| decision / success | spring 0.4s, bounce 0.12 | Decision curtain, add-source success, mark burst |
| holdBeforeDismiss | 180 ms skip, 320 ms read, 520 ms queue | Pause after the curtain, skipped when Reduce Motion is on or UI tests are running |

`card` (0.3s) and `cardTransition` are defined and never used. Delete them or use them. Do not add a third 300 ms ease.

There is no matched geometry between a row and the reader. The reader is a cover or a split. That is fine. Do not add a shared-element transition. It would fight the cover.

## What already feels right

- Press scale on primary, ink capsule, decision, card, and directory row styles. Scale stops at 1 when Reduce Motion is on.
- Decision curtain: plaster, mark, caption. The curtain itself snaps when Reduce Motion is on. Haptics: success for Queue and Done, a firmer impact for Skip.
- Takeaway chips: selection haptic, prompt crossfades, Reduce Motion turns those off. The sheet uses the system detent, not a custom spring.
- Onboarding page changes are gated on Reduce Motion.
- Launch cover and the source-refresh cover fade with `overlay`, and that path does check Reduce Motion.
- Inbox zero uses a short burst, then stops. It is rare, so a little delight is earned.

## What to change

### Gate the reader’s always-on animations

`ReaderView` attaches `.animation` to the decision value, extracting, summarizing, and the mode picker without reading Reduce Motion. The curtain respects the setting. The parent animation does not. Mode changes should be opacity or instant when Reduce Motion is on. Same for `RefreshProgressBanner`, star taps, Queue restore, and `ArticleActions` list updates.

Trigger: Reduce Motion is on. Property: opacity only, or no animation. Duration: none. Purpose: the setting the person already chose.

### Do not animate Save on the takeaway sheet

Save and Not now dismiss the system sheet, then the curtain plays. That order is the feedback. Do not add a checkmark animation inside the sheet. It would delay the curtain and teach people to wait twice.

### Press the reader bar

The iPhone bar items are plain buttons. They do not scale. The accessibility-size Done button does. Use the existing press style (0.97, 0.2s easeOut, none if Reduce Motion). Trigger: touch down. Element: the bar item. Property: scale. Purpose: the tap is acknowledged before the sheet or the curtain.

### One success pause

Add Source waits about 420 ms. Queue’s curtain waits 520 ms. Onboarding’s last page uses the queue hold. Pick the queue hold for “I kept this” and the read hold for “I finished”. Do not invent a 420 ms one-off in the next feature.

### Refresh should not be a full-screen fade

The cover fade is a real transition into an empty state. Prefer the banner. If a cover remains for a truly empty list, keep `overlay` at 0.3s easeOut, and skip it under Reduce Motion. Purpose: show that the old screen left. It should not play over a list that is still there.

### Haptics stay on the commit

Selection haptic when a takeaway choice is selected, not when it is cleared. Success haptic when Queue or Done commits, which is the curtain, not the sheet button. Do not haptic every chip redraw. Primary buttons already fire an impact on press. That is enough.

## Leave alone

- No bounce on chips, menus, or the mode picker. Bounce is only on the decision spring, and it is small (0.12).
- No looping motion except the mark pulse while something is actually loading. The pulse already pauses for Reduce Motion.
- Folder emoji selection can stay an instant dismiss. The sheet closing is the feedback.
- Numeric unread transitions can stay. They are small. Still honor Reduce Motion by skipping the numeric transition, not by adding a new one.
