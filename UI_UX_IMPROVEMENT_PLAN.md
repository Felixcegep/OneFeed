# OneFeed UI and UX improvement plan

Date: September 15, 2026  
Status: Recommendations only. No application changes made for this report.

Start with the [priority map](#3-priority-map), then the [detailed changes](#5-detailed-changes). The [visual specification](#6-shared-visual-specification), [research references](#7-external-references-borrow-the-useful-behavior), [implementation sequence](#9-implementation-sequence), and [validation plan](#10-validation-plan-for-later-implementation) make this document usable as an implementation brief.

For choosing which model does each task, use the [model assignment and execution order](#3a-model-assignment-and-execution-order). It separates difficult behavior changes from small presentation edits without changing the UX IDs below.

## 1. Direction

OneFeed should feel like opening a small, personal reading room: one clear starting point, readable content, a quiet place to keep something for later, and permission to stop. Its strongest assets are its warm palette, serif editorial typography, restrained branding, local library, and deliberate daily selection. Keep those.

The largest improvements are not more decoration. They are clearer article boundaries, one meaning for each destination, predictable reading actions, and accurate feedback about what was saved, finished, loaded, or synced.

The README defines the baseline: **one article at a time; no home timeline, unread totals, dashboard, recommendation feed, streaks, or engagement mechanics**. Current code partly diverges from that baseline. This plan restores the principle while retaining Feed as an optional place for deliberate browsing and Queue as the user's own saved collection. Existing source folders remain organizational tools; do not introduce algorithmic categories or new discovery machinery.

### Scope and evidence

- **Visual evidence:** the Queue screenshot supplied in this conversation. It shows the earlier grouped layout, before the preceding Queue card edit.
- **Code evidence:** all feature screens and view models, app routing, shared design components, platform helpers, widget UI, and the domain/service paths that determine user-visible state. Supporting networking, parsing, storage, and tests were inspected selectively for their UX consequences. This is an app-wide UX code review, not a line-by-line security or correctness audit of every implementation file.
- **Research:** current official product pages and documentation, an inspected official Reeder screenshot, Apple guidance, and relevant installed design skills.
- **Not performed:** simulator launch, app launch, new application screenshots, device interaction, VoiceOver testing, performance profiling, builds, or tests. Existing repository screenshot tours were not treated as current evidence.
- **Confidence labels:** `Visual` means visible in the supplied image; `Code` means directly established by implementation; `Risk` means a predicted interaction that needs device validation; `Proposal` means a design choice, not a demonstrated defect.
- Source line numbers refer to this working tree at review time. Symbols are supplied where they are a more durable locator.

The preceding Queue change already adds individual paper surfaces, 1-point outlines, 10-point combined row gaps, semantic row fonts, separate metadata, and trailing thumbnails in `SavedView.swift`. Do not implement that same fix again. Review its rendered result later and extend the useful pattern deliberately.

## 2. Preserve these strengths

1. Keep native tab navigation, lists, sheets, context menus, and swipe actions. They provide useful interaction conventions without requiring custom gestures.
2. Keep warm adaptive paper colors and SF/New York system typography. No gradient rebrand, generic dashboard, oversized promotional illustrations, or competing accent colors.
3. Keep Today finite. `DailyDeckService.generateIfNeeded` currently caps selection at ten and returns the same deck for that day. Ten is a ceiling, not a goal users must complete.
4. Keep Queue user-controlled and separate from unread ingestion. The internal `.queued` state is **not** the user-facing Queue; `.saved` is.
5. Keep Close non-destructive. Closing an article should not mark it read or skip it.
6. Keep explicit clipboard access, cached readable content, OPML portability, optional sync, and optional AI.
7. Keep real article images when useful; let text-only stories look complete without artificial illustrations.
8. Keep the already useful empty-state components, source filtering options, and inline source-add progress.

## 3. Priority map

P0 = repair trust or preserve user intent before cosmetic work. P1 = core usability/accessibility. P2 = refinement after the first two groups. Effort is relative: S = localized view/copy change; M = several views or state paths; L = domain/sync/migration work. These are not time estimates.

| ID | Priority | Change | Effort |
| --- | --- | --- | --- |
| UX01 | P0 | Make Today, Queue, and synced article state agree | L |
| UX02 | P0 | Make History reader actions truthful | M |
| UX03 | P0 | Protect saved stories when sources/catalogs change | L |
| UX04 | P0 | Report persistence and refresh outcomes accurately | M |
| UX05 | P1 | Give Today one primary reading choice | M |
| UX06 | P1 | Remove duplicate meanings and unread pressure from navigation | M |
| UX07 | P1 | Standardize article boundaries and metadata | M |
| UX08 | P1 | Fix typography scaling and text contrast | M |
| UX09 | P1 | Simplify and contextualize reader actions | M |
| UX10 | P1 | Preserve reading position and explain loading/fallback states | L |
| UX11 | P1 | Add reliable Undo and recovery | L |
| UX12 | P1 | Make onboarding actually establish a reading library | M |
| UX13 | P1 | Make Queue additions quick, explicit, and recognizable | M |
| UX14 | P1 | Make source setup and batch failures recoverable | M |
| UX15 | P1 | Align source settings with actual filtering behavior | M |
| UX16 | P1 | Give empty states distinct meanings | M |
| UX17 | P1 | Simplify Settings and explain sync consequences | M |
| UX18 | P1 | Make widgets open the story they show | M |
| UX19 | P1 | Fix touch targets and accessibility semantics | M |
| UX20 | P2 | Remove repetitive blocking motion | M |
| UX21 | P2 | Make video/audio reading purposeful; keep AI optional | M |
| UX22 | P2 | Restore deliberate search without adding a discovery feed | M |
| UX23 | P2 | Make iPad/macOS layouts and chrome scale properly | M |
| UX24 | P2 | Make copy, settings previews, and visual states consistent | S–M |

## 3a. Model assignment and execution order

**Recommended division: Astra for architecture and difficult correctness; Sol for substantial implementation; Grok 4.6 for precisely specified, bounded edits.** If you prefer just two tiers, combine Astra and Sol into **large model** and use Grok 4.6 for the small work packages below.

These assignments are engineering judgments about this repository, not a benchmark ranking of the models. “Grok 4.6” is retained as your chosen small-task model label; its exact availability, price, and comparative performance were not verified. OpenAI describes Astra as suited to complex reasoning and coding; the particular Astra/Sol split here is a suggested workflow, not an official capability boundary. [Official model catalog](https://developers.openai.com/api/docs/models).

Choose by **ambiguity, coupled state, and consequences of a mistake**, not line count. A three-line sync change can require more reasoning than rebuilding a whole settings layout. Task priority and model tier are independent: a small accessibility fix can still be urgent.

### Tier A — Astra preferred; Sol is the large-model alternative

Keep design, implementation, and behavior-test ownership together for these tasks. Do not have a large model merely sketch a state machine and leave a smaller model to infer its missing cases.

| Order within tier | Task | Why it needs the strongest reasoning | Required handoff/result |
| --- | --- | --- | --- |
| A1 | **UX01 — Unified article/deck/sync state** | Multiple representations, remote precedence, stale snapshots, and competing current-item selection | Transition truth table; one concrete transition path; tests for every entry point and sync round trip |
| A2 | **UX03 — Preserve saved stories during source/catalog changes** | Cascade deletion, remote failure, source attribution, upgrade behavior, and existing-user data | Explicit preservation/removal rules; migration implications; failure and catalog-upgrade tests |
| A3 | **UX11 — Undo across local and remote changes** | Must reverse one action without reversing later actions or corrupting queued remote mutations | Inverse-action contract; offline/online Undo tests; persistent recovery path |
| A4 | **UX10 — Reader continuity and loading model** | WebView lifecycle, changing HTML, typography, async extraction, anchors, and durable save-before-enrichment | Content-state model; position restoration; managed enrichment; focused failure tests |
| A5 | **UX17 — Sync conflict, recovery, and retention behavior** | What is replaced versus merged, reliable backups, retention policy, and truthful UI promises | Agreed backend semantics and recovery tests before implementing the settings presentation |

A3 depends on A1. A5's source-preservation implications must agree with A2. A4 owns the background-enrichment behavior used by UX13. Do not implement conflicting versions of those mechanisms in separate tasks.

### Tier B — Sol preferred; Astra if the task expands into unresolved architecture

These tasks need a capable coding model but usually do not need a fresh architectural investigation after Tier A establishes the contracts. Start with normal/balanced reasoning where configurable; increase it for a demonstrated difficult failure or unresolved state interaction, not automatically for every UI edit.

| Task | Exact responsibility for Sol | Dependency / boundary |
| --- | --- | --- |
| **UX02** History actions | Implement real reader capabilities, state-changing callbacks, and session protection | UX01; coordinate with UX09 so they share one capability model |
| **UX04** Outcome feedback | Structured refresh results, persistence failures, truthful timestamps, coalesced-call results | Coordinate transition-result contract with UX01 |
| **UX05** Today | Single-story composition and intentional finite-day flow | UX01 and UX16; Grok may apply final approved layout constants |
| **UX07** Article hierarchy | Design shared content/container responsibilities; migrate active callers without breaking gestures | Preserve prior Queue fix; Grok may do final bounded styling afterward |
| **UX08** Typography | Semantic font migration, HTML/native consistency, Dynamic Type reflow, preference compatibility | Establish tokens once; do not give a small model a global search-and-replace |
| **UX09** Reader actions | Context-dependent action bar, browser simplification, accessible layout | UX01–02; plan alongside UX10 to avoid overlapping reader rewrites |
| **UX12** Onboarding | Real setup flows, completion/cancellation ownership, optional source selection | UX03 and UX16; preserve existing libraries |
| **UX13** Queue additions | Paste/submit behavior, duplicate results, cancellation, feedback, ordering | UX01 and UX10 enrichment contract; escalate new persistence-field/migration decisions to Astra |
| **UX14** Source additions | Partial success, retaining failed input, deduplication, cancellation | UX03 removal policy is separate; keep the addition flow focused |
| **UX15** Source controls | Shared filter eligibility across local/FreshRSS; accurate pause semantics | UX01 and UX03; labels follow the agreed behavior |
| **UX16** Empty states | Distinguish no sources, load failure, no eligible items, and completed deck | UX01 and UX04; first empty-deck eligibility is domain behavior, not just copy |
| **UX18** Widget routing | Resolve exact article IDs across cold/warm launch and render per-family widgets | UX01; escalate lifecycle/routing redesign if required |
| **UX19** Accessibility | VoiceOver actions, focus restoration, semantic HTML, announcements | UX07–09 and UX11 for the respective interactions; target-size-only work can go to Grok |
| **UX20** Motion | Remove pre-commit success and artificial waits safely; handle tasks and Reduce Motion | UX04 and UX09–11; a small model can adjust tokens after lifecycle is correct |
| **UX21** Media/AI | Explicit summary initiation, attribution, failure states, media-aware actions | UX09–10; no new player or AI service |
| **UX22** Search | Scoped search in the active screens, correct empty states and return position | UX06–07; reuse only relevant logic from dormant screens |
| **UX23** Adaptive layout | Safe-area ownership, sheet/window adaptation, keyboard/platform behavior | UX07–09 and settings structure; do not guess insets from one screenshot |

For UX17, Astra owns the behavior contract; Sol can subsequently build the Settings navigation, status summaries, and conflict-review presentation against that contract.

### Tier C — Grok 4.6: small, explicit implementation packages

Do **not** give a smaller model “improve all accessibility” or “finish UX17.” Give it one package with a file allowlist, exact values/copy, and a clear stopping point. These are intentionally narrower than several UX recommendations.

| Package | Related task | Exact small-model scope | Ready when |
| --- | --- | --- | --- |
| C1 | **UX24** | Replace the specified metaphors with the approved plain-language copy; keep existing actions/state unchanged | Can start now for purely descriptive copy; defer sync/retention/pause claims until behavior is settled |
| C2 | **UX06** | Reorder existing phone tabs and Mac sidebar items to Today, Queue, Feed, Settings; retain `.today` initial selection | Can start now; no new routes or persistence |
| C3 | **UX06** | Remove displayed unread counts, label the existing collection Latest, rename the date-filtered shortcut Published today if retained | Navigation choice is settled; change UI labels, not raw state values or filtering predicates |
| C4 | **UX07** | Apply the agreed 12-point corners, 16-point padding, 10-point gaps, and clipped pressed fill to the selected shared card component | Sol has established the component and callers; avoid redoing the existing Queue patch |
| C5 | **UX08** | Replace a supplied list of small-text stone usages with graphite; apply already-measured link-text tokens | Sol has defined semantic tokens and listed the exact call sites |
| C6 | **UX19** | Increase the existing emoji button hit region to ≥44 × 44; change the emoji grid to adaptive cells with minimum 44-point width | Can start now in `FolderEmojiPicker.swift`; no changes to selection persistence |
| C7 | **UX20** | Apply approved press/fade timing values and remove a specifically identified decorative effect | Sol has removed persistence delays and settled Reduce Motion/lifecycle handling |
| C8 | **UX24** | Read app version/build from bundle metadata; rename font labels Serif/Sans serif/Monospaced without changing raw preference keys | Can start now; missing metadata needs a harmless display fallback |
| C9 | **UX17 / UX24** | Apply backend-specific disconnect labels and approved helper text in the existing settings views | Astra/Sol have settled actual disconnect/merge/retention behavior |
| C10 | **UX18** | Adjust widget labels, metadata hierarchy, and type styling in the already-separated family views | Sol has completed exact-ID routing and family-specific layout |

**Keep UX24's live appearance preview with Sol** if it requires shared reader rendering or live WebView updates. The small-model assignment covers static copy, labels, and bundle version display only. Similarly, the UX06 Add Source unification and any navigation-state changes belong with Sol; C2–C3 are presentation-only portions.

### Execution order that avoids paying twice

This order refines section 9 for model handoffs. Recommendations retain their original IDs; a large UX item may have a core pass and a later presentation pass.

1. **Astra: UX01.** Establish the transition contract and tests first. Sol's UX04 result model should use that contract.
2. **Astra: UX03. Sol: UX04.** Separate changes for saved-content preservation and trustworthy outcomes; integrate before dependent flows.
3. **Sol: UX02 + UX09 capability foundation, then UX16. Astra: UX11.** History and Undo use the same transition rules; do not invent separate recovery logic.
4. **Astra: UX10 and the behavioral part of UX17.** Establish reader continuity, enrichment, retention, and conflict recovery contracts. Finish each bounded change before starting a broad screen rewrite.
5. **Sol: UX05–08 presentation/system work and UX09 reader composition.** Set shared visual/type rules once; then hand off C2–C5 where still needed.
6. **Sol: UX12–15, UX17 presentation, and UX18.** Deliver complete setup, save, source, settings, and widget journeys against the foundations.
7. **Sol: UX19–23 remaining behavior/adaptation. Grok: C7, C9–C10, plus remaining UX24 copy.** Integrate visual polish in small, reviewable changes.
8. **Sol: integrated UI/code consistency review. Astra: focused review of state, sync, deletion, Undo, and recovery invariants.** Use the existing acceptance matrix; do not ask Astra to re-audit every label or corner radius.

C1, C2, C6, and C8 can be useful early quick wins before step 1, provided no concurrent task owns the same files. This is a work order for model sessions, not an instruction to run parallel agents. Keep the user's no-simulator constraint unless they explicitly change it; report visual/device checks as outstanding instead of claiming they passed.

### Handoff prompts

**For Astra / a large-model foundation task:**

> Implement UX[ID] from UI_UX_IMPROVEMENT_PLAN.md only. Read its cited code paths and relevant tests. Establish the state/behavior contract, implement the complete bounded change, and cover its failure cases with focused tests. Preserve existing user changes and OneFeed's philosophy. Do not launch the simulator. If a test requires it, leave that check unrun and report it. List the resulting interfaces/contracts that dependent tasks should use. Do not implement the rest of the plan.

**For Sol / a substantial UI flow:**

> Implement UX[ID] using the completed foundation contracts: [symbols/commit or handoff]. Follow the visual specification and acceptance criteria in UI_UX_IMPROVEMENT_PLAN.md. Scope is [screens/files]. Preserve existing state behavior unless this task explicitly changes it. Do not launch the simulator. Verify what is possible without it and report remaining device checks. Escalate unresolved persistence, deletion, sync-precedence, or migration decisions rather than inventing a second mechanism.

**For Grok 4.6 / a small package:**

> Implement package C[number] from section 3a of UI_UX_IMPROVEMENT_PLAN.md only. Allowed files: [exact paths]. Apply these exact changes: [copy/values/call sites]. Preserve actions, state transitions, raw preference keys, and existing user edits. Do not refactor unrelated code, add dependencies, or launch the simulator. Stop and report if this requires a domain, sync, routing, persistence, or migration change. Check the diff and available non-simulator validation; state what was not verified.

### When to switch up a tier

Switch from the small-task model to Sol when the task needs a new shared component contract, adaptive layout decisions across multiple screens, async cancellation, or navigation/presentation ownership. Switch to Astra when the uncertainty involves data preservation, multiple sources of truth, sync precedence, migration, or Undo across remote changes. A failing test that exposes one of these issues is a reason to escalate; a simple typo or compiler diagnostic is not.

The cost-saving pattern is **large model resolves the difficult contract → bounded implementation → small model applies exact finishing work → targeted integration review**. Do not pay a strong model to re-explore the whole app for every minor edit, and do not make a smaller model reconstruct architectural intent from a one-line task.

## 4. Target information architecture

| Destination | User's question | Proposed contents | Keep out |
| --- | --- | --- | --- |
| Today | “What can I read now?” | One current story; Read, Add to Queue, Skip; quiet explanation of the daily selection | Expanded article backlog, unread totals, completion targets |
| Queue | “What did I choose to keep?” | Saved stories, clear item boundaries, Add link, search, recent-first order | Automatic recommendations, fake FIFO claims, urgency badges |
| Feed | “What are my sources publishing?” | Source folders and optional Latest collection; search; visible Manage Sources access | Another destination called Today, prominent unread counters |
| Settings | “How does this work for me?” | Reading, Sources & Import, Sync, Storage, optional Video Summaries, About | A long wall of account forms on the first settings screen |
| History, secondary | “Where did that story go?” | Read/skipped stories, search, restore/requeue | Progress charts, ratings as a task, streaks |

Proposal: order tabs **Today, Queue, Feed, Settings**, retaining Today as the initial selection. Mirror this order on macOS. This puts the product promise first without removing deliberate browsing. If preserving existing muscle memory is more important for an established release, stage tab reordering separately from the behavior fixes.

## 5. Detailed changes

### UX01 — One action must update every representation of a story

**Evidence: Code.** `DailyDeckService.swift:75` (`advance`) changes both deck-item status and article state. `ArticleQueueService.swift` changes article state without updating the associated `DailyDeckItem`. `ArticleActions.swift:6` uses that second path. `CurrentViewModel.swift:97` explicitly updates a deck item only for some reader completions; Today swipe actions bypass it. `DailyDeckService.remainingArticles` filters deck-item status, not article state.

There are two additional conflicts: `DailyDeckService.fetchCandidates` excludes read/skipped articles but can include saved articles; generating a deck then changes selected articles to current/queued. `FreshRSSSyncService.swift:263` maps a starred remote item to `.saved` before considering read state, while `ArticleStateTests.readingALaterArticleLeavesTheQueueButKeepsStarred` explicitly preserves the star on Done. A finished queued story can therefore return to Queue when the remote read-and-starred snapshot is applied.

**Change precisely:**

1. Establish one transition operation used by Today, swipe/context actions, Queue, History, widget-related selection, and sync reconciliation. Update article, matching deck item, completion timestamp, remote mutation intent, and widget snapshot together.
2. Exclude `.saved`, `.read`, and `.skipped` from automatic daily selection. Do not make a saved story disappear from Queue by selecting it for Today.
3. Reconcile stale deck items before presenting Today. An item terminal elsewhere must not reappear as unfinished.
4. Specify the remote truth table explicitly: unread+starred may enter Queue; read+starred remains read and starred; skipped stays local unless the user explicitly restores it. Confirm this against the existing FreshRSS tests before changing precedence.
5. Reload Today on relevant library changes and scene/day transitions, not just first configuration. Do not move the reader's active article while it is open.

**Acceptance:** save/skip/finish the current story through every entry point; Today, Queue, History, and widget agree after navigation, relaunch, and FreshRSS sync. A saved story remains saved across daily generation. Advancing another story cannot create two independent “current” selections. Add state-transition tests before changing this behavior.

### UX02 — History must not offer actions it silently discards

**Evidence: Code.** [HistoryView.swift](OneFeed/Features/History/HistoryView.swift):42 creates the normal reader but its completion callback ignores the selected state and only dismisses. The reader can display “Queued” even though nothing was queued.

**Change precisely:** introduce a reader context/capability model rather than presenting every action for every article. In History, show **Add to Queue** and **Close**; show **Mark unread** in More only if its destination and sync behavior are implemented. Do not offer Skip as though rereading creates a new daily decision. Route Add to Queue through UX01, then refresh History. Use the same active-reading-session protection as the other reader owners so cloud updates cannot alter a live reading session.

**Acceptance:** open a read story from History, add it to Queue, and find exactly one saved item after reopening the app. Close leaves the original state unchanged. No success message can be shown for a discarded action.

### UX03 — Source management must not unexpectedly erase kept reading

**Evidence: Code.** `Feed.swift:27` uses cascade deletion for articles. `SourcesView.swift:288` confirms source/article removal, then dismisses before an asynchronous removal. `SourceDetailViewModel.remove` deletes locally even when remote unsubscribe fails; its `presentedError` is not displayed by `SourceDetailView`. `FeedSeedService.apply` realigns existing titles/folders and removes retired sources. `OneFeedApp.swift` invokes catalog application on version changes and retired-source cleanup on other launches.

**Change precisely:**

- Default **Remove source** means stop following, preserve saved/starred stories, and preserve their source-name/domain attribution by snapshotting it before unlinking the feed. Explain this in the confirmation.
- Keep destructive deletion of saved content a distinct, explicitly labeled option with exact affected counts. Do not overload unsubscribe.
- On remote failure, keep the source visible with Retry, or explicitly represent “Removal pending.” Do not imply the remote subscription was removed.
- Let the presentation owner handle dismissal and post-dismiss cleanup; an unstructured task after `dismiss()` is not proof the transition has ended.
- Turn “Restore all seeded sources” into an opt-in catalog chooser. Preserve user-renamed/reorganized subscriptions. Retiring a recommendation must not delete a user's subscription or its articles.
- For catalog updates, offer **New suggested sources available** inside Sources, without automatically subscribing or reorganizing.

**Acceptance:** removing a feed with two queued stories preserves those two stories and their attribution. Failed remote removal has a visible recovery path. Upgrading the catalog preserves the user's folder choices and saved articles. Cover all three with service tests.

### UX04 — Success feedback must describe success, not merely an attempt

**Evidence: Code.** `ArticleActions.swift:17` swallows persistence errors. `BrowseRefresh.swift:44` advances `lastRefreshedAt` regardless of refresh error. `BackgroundRefreshCoordinator.refresh` catches failures and still writes `lastSuccessfulRefresh`. Transient failures are suppressed by `RefreshFailure`, which can be reasonable for background work but leaves explicit user requests without an explanation.

**Change precisely:** return a structured outcome from refresh: complete, partial, offline/unavailable, cancelled. Track last attempt separately from last successful content update. Present:

| Outcome | Copy | Action |
| --- | --- | --- |
| Complete | “Updated just now” | None |
| Partial | “Some sources couldn’t update” | View details / Retry failed |
| Offline, cached content available | “Offline · showing saved content” | Retry |
| Initial load failed | “Couldn’t load your sources” | Retry / Manage sources |
| Cancelled | No error message | None |
| Article save failed | “Couldn’t save this change” | Retry; keep original state |

Only show completion feedback after local persistence succeeds. For optional remote sync, say **Saved on this device · sync pending** when that distinction matters. Keep background transient failures quiet until they affect an explicit task. Existing content stays visible while refreshing.

**Acceptance:** airplane mode cannot produce a new successful-update timestamp; partial failures do not blank the list; failed article persistence does not display “Done.” Coalesced refresh callers receive the actual shared result rather than assuming their closure ran.

### UX05 — Make Today deliver on “one article at a time”

**Evidence: Code + Proposal.** `CurrentView.swift:35` expands “Also today” under the featured story; the subtitle displays remaining count. `DailyDeckService` already supports a current item and finite deck.

**Change precisely:** show one featured story with source, full title, useful excerpt, and reading/video duration. Place an explicit **Read article** or **Watch video** action below it, with quieter **Add to Queue** and **Skip** actions. The story surface may also open it, but do not rely on the surface alone to teach the interaction. Do not nest buttons inside a tappable card button; use sibling controls in a containing view.

Remove the expanded “Also today” list from the default screen. If manual selection is valuable, put **Browse today’s selection** behind a secondary disclosure/action; it must not dominate the first screen. Replace “N remaining” with a date or “A small selection from your sources.” The finite set is a limit on attention, not a checklist.

At the end, show **That’s all for today** and “Your next selection will be ready tomorrow.” Make **Open Queue** optional and secondary. Do not make Refresh the prominent next action: the frozen deck will not refill, and a large Refresh button encourages repeated checking.

**Acceptance:** at normal text size, the initial screen has one unambiguous reading choice. At accessibility sizes it scrolls naturally. Finishing returns to the next choice without automatically opening another article. An exhausted day stays exhausted after refresh.

### UX06 — Give destinations one meaning

**Evidence: Code.** `AppRootView.swift:45` places Queue before Today. `FoldersView.swift:48` contains All Unread and another Today destination; that Today is calendar-date filtering, unlike the finite daily selection. Folder rows display unread counts. Sources and History are hidden in More. Today's “Add Source” opens a Sources directory, whereas Feed's equivalent opens the actual add form.

**Change precisely:** implement the target navigation in section 4. Rename Feed's All Unread to **Latest** if retaining that collection, remove numeric unread counts, and remove the second Today shortcut. If date filtering is retained, call it **Published today**, placed inside Latest filters. Use source counts where they explain a folder's contents; do not substitute a different form of unread badge.

Provide **Manage sources** as a clearly labeled Feed entry, and History as a secondary Queue toolbar menu item plus a Settings link. Keep toolbar density modest: Add and More are enough when pull-to-refresh is available. Make every Add Source entry open the same AddSource flow.

**Acceptance:** a new user can explain Today versus Feed versus Queue. Every Add Source command opens the same task. No badge or folder count implies an obligation to clear the library.

### UX07 — Give stories clear boundaries and a consistent reading hierarchy

**Evidence: Visual + Code.** The supplied screenshot shows four article entries inside one rounded surface, no separators, irregular perceived vertical gaps, and a long source string competing with the title. `OneFeedTheme.articleListRow():501` still hides separators and supplies one paper background in Today, collection, and History rows. Queue now has a local fix in `SavedView.swift:153` and `queueCardSurface():254`.

**Change precisely:**

1. Keep the Queue's new independent card treatment: 12-point corners, 16-point inner padding, 10-point clear gap, 1-point sand outline, no decorative shadow. Ensure the full card follows its rounded shape when pressed; the current generic button style can paint a rectangular pressed background around it.
2. Put a reusable article-content component in the design system, with two containers: **saved card** for Queue and **compact list row with visible separators** for Feed/History. Do not turn every settings or directory row into a card.
3. Order content consistently: title; source; duration and date. Title uses semantic headline, source subheadline, details caption. Keep metadata smaller but readable. Show History status separately so it cannot be truncated off the end of a long metadata line.
4. Keep thumbnails trailing, top-aligned, 64 × 64 points for compact cards, with 10-point corners. Omit absent thumbnails without reserving an empty column. At accessibility sizes omit the decorative thumbnail to preserve text width.
5. Queue: maximum three title lines at standard sizes, unlimited at accessibility sizes; source up to two lines. The featured Today story always shows its full title. The current Queue row has unlimited titles at every size: assess exceptionally long titles before adopting it everywhere.
6. Compact Feed/History rows: 16-point horizontal and 12-point vertical padding; separator aligned to the text inset; content-driven height. No blanket spacer or image-height reservation for text-only stories.
7. Use `article.feed?.title`, then a cleaned URL host, then **Saved link** as source fallback. Never show the literal placeholder “Source.” Offer user-editable titles for saved links when metadata is poor; do not guess what “Don” was intended to mean from the screenshot.

For Queue, replace **Up next** with **Recently added** unless a real user-managed next-item order is implemented. `SavedViewModel.reload` sorts newest save first; it is not FIFO. Keep the featured saved item compact, using the same content grammar, so a random last-saved video does not become an oversized mandatory-looking hero. Prefer one recent-first list with a Video/Podcast label per item over three tiny media sections for a five-item collection. Add media filters only when useful for a larger collection.

**Acceptance:** the supplied five-item composition is understandable without thumbnails; every card has a visible start/end in light and dark mode; long titles, long source names, missing images, and 200% text scaling preserve hierarchy. Validate the earlier Queue edit before further changes.

### UX08 — Make readability scale across the whole app

**Evidence: Code + calculated token contrast.** `OneFeedTheme.swift:44–55` uses fixed-size system font factories. Many headers, row titles, button labels, and metadata rely on these. Queue's new semantic fonts are an improvement, but shared rows remain fixed. Reader body text already scales through `UIFontMetrics` in `AppPreferences.swift`; preserve that support.

Approximate sRGB contrast computed from the declared light-mode hex equivalents, not sampled from a device:

The 4.5:1 ordinary-text target below uses [W3C's contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) as a readability benchmark. This token calculation is not a claim of full native-app accessibility compliance.

| Pair | Ratio | Consequence |
| --- | --- | --- |
| Ink on paper | 14.29:1 | Strong primary text; retain |
| Graphite on paper | 7.57:1 | Use for source and meaningful metadata |
| Stone on paper | 3.76:1 | Too weak for small normal text at a 4.5:1 target |
| Terracotta on paper | 2.97:1 | Do not use unchanged for ordinary reader link text |
| Paper against plaster | 1.04:1 | Background difference alone does not define cards |
| Sand against paper | 1.42:1 | Decorative outline only; strengthen in Increased Contrast |

**Change precisely:** replace numerical UI font factories at content call sites with semantic roles. Keep serif display personality through a scaled serif title style. Use graphite for small source labels, bylines, and meaningful counts. Introduce a darker light-mode **linkText** token with measured contrast of at least 4.5:1 and retain underlines; preserve terracotta for branding and appropriate larger glyphs. A starting candidate is the existing `accentPressed` family, but measure the final token on each actual surface. Apply the same semantic colors to reader HTML.

Reader typography proposal: standard base body 18 points, compact 16, large 21, still scaled by system size; line height 1.55–1.65; horizontal inset 20 on phone; comfortable maximum reading measure about 34–36em on large screens. These are OneFeed starting specifications, not claims about competitor measurements. Preserve stored size preference identifiers or migrate deliberately.

**Acceptance:** all meaningful UI text enlarges with Dynamic Type; controls reflow instead of shrinking copy. Verify AA text contrast in both schemes and Increased Contrast, including links and error copy. Thin decorative borders need not independently satisfy text contrast, but essential focus/selection indicators must remain distinguishable.

### UX09 — Reduce reader choices and make them context-aware

**Evidence: Code.** `ReaderView.swift:150` has five equal bottom slots: Queue, Skip, Done, Share, Browser. Website is also a segmented mode at the top; Browser opens another internal web presentation. Fixed 11-point captions and shrinking behavior make the strip especially fragile at large text sizes.

**Change precisely:** bottom bar contains **Add to Queue**, **Skip**, and emphasized **Done** for a Today/Feed article. Move Share and **Open in Safari/default browser** to the top trailing menu. Keep a labeled Text/Website mode control only when both modes are usable; avoid a second embedded browser under a different name.

In Queue, replace Add to Queue with a noninteractive **In Queue** state or omit it. Offer **Remove from Queue** in More, not as another ambiguous save action. In History use UX02's capability set. At accessibility sizes use a full-width Done button and a second row for the other available actions; do not squeeze three labels into narrow slots.

Close always means no state change. Done means finish and return to the originating screen. Skip means leave the daily/unread choice and retain recovery in History. No automatic advance into a new full article.

**Acceptance:** a user can distinguish closing from completing. The same action has the same result from all entry points. Large text never produces “Don e,” clipped captions, or unlabeled glyph-only decisions.

### UX10 — Preserve the reading session through content and appearance updates

**Evidence: Code + Risk.** `ReaderWebContent` reloads HTML with `.task(id: html)` at `ReaderView.swift:543`. Extraction and typography changes can change that HTML. `.id(dynamicTypeSize)` recreates the reader view. No persisted reading-position field is present. `initialMode` sends articles without cached HTML directly to Website even while extraction runs, and website panes expose loading but no explicit failed-navigation state.

**Change precisely:**

- Persist a reading anchor per article and mode. Prefer a paragraph/element anchor plus within-element offset; use proportional position only as fallback. Restore after layout completes, and preserve position when fonts or extracted content change.
- Update presentation styles without reloading the whole article where possible. If reloading is necessary, capture and restore the anchor. Ensure a resumed article does not flash its top before restoration.
- For text articles, start with readable cached text or a labeled **Preparing article…** state. Offer **Open website** immediately; do not wait behind a forced animation.
- Track content state explicitly: cached excerpt, full text available, extraction failed, website loading, website failed. Do not infer complete offline readiness from a nonempty `readableHTML` string.
- When extraction fails, keep the excerpt and show **Full text couldn’t load · Retry / Open website**. Show failed website navigation with Retry and external-browser fallback.
- Save a pasted link locally before slow enrichment. `QueueLinkService.add` currently awaits metadata before insertion. Fetch metadata in a managed background operation and keep the saved item usable if enrichment fails.
- Use honest offline copy: cached text can be read offline; remote images/video may still need a connection. A URLCache allocation is not a guarantee that every saved item is downloaded.

**Acceptance:** scrolling halfway, changing type size, closing/reopening, and receiving late extraction results keeps the same passage visible. No network yields cached content or a specific recovery state. A failed metadata request does not prevent saving a valid link.

### UX11 — Make fast actions forgiving

**Evidence: Code.** Full-swipe Done/Queue actions exist in `ArticleActions.swift` and SavedView, but no Undo path was found. History provides no working restore behavior through its current reader callback.

**Change precisely:** after a successful action, show a compact confirmation above the safe-area controls: **Added to Queue · Undo**, **Marked done · Undo**, or **Skipped · Undo**. Keep it visible for approximately six seconds; extend/pause expiration while assistive focus is on it. Preserve a durable recovery path in History so recovery never depends solely on a timer.

Undo must restore the prior article state, timestamp, star intent, deck position/status, and current selection through UX01. Record the inverse remote mutation when the original already synced. Do not equate undoing Done with unstar: those are independent dimensions. Do not roll back unrelated later actions or newer remote changes; resolve the single targeted action. Until reliable Undo exists, disable full-swipe commitment for actions whose recovery is incomplete.

**Acceptance:** accidental full swipe can be reversed locally and after a sync round trip. Offline Undo does not replay the wrong final state when reconnected. VoiceOver users have sufficient time and a non-timed fallback.

### UX12 — Replace explanatory onboarding with a useful first step

**Evidence: Code.** `OnboardingView` has three copy pages. “I’ll connect FreshRSS later” advances just like Continue; no connection happens there. `OneFeedApp` automatically applies the entire seed catalog before onboarding is completed. This conflicts with deliberately chosen sources and makes the first library less personal.

**Change precisely:**

1. One welcome screen: **One article at a time.** Supporting copy: “Read something worth your attention. Keep the rest for later.” Primary **Choose sources**; secondary **I already use FreshRSS**; tertiary **Not now**.
2. Reuse the real Add Source/connect flows. Offer an optional, clearly labeled starter selection with individual checkboxes and none silently selected. Bulk OPML import belongs behind **Import subscriptions**.
3. After one source succeeds, offer **Start reading** with the first usable story, without waiting for every source to finish. A failed first fetch should say **Source added; stories couldn’t load yet** and provide Retry.
4. Store onboarding completion according to a deliberate finish/skip action. A dismissed setup sub-sheet should return to onboarding, not silently mark all setup complete.

Preserve existing users' libraries during this change; automatic seeding removal is not authorization to delete subscriptions already created.

**Acceptance:** clean-install tests cover add-source, FreshRSS, import, skip, cancel, and failure. A user can reach their own content without reading three screens of metaphor or inheriting unwanted feeds.

### UX13 — Make Add to Queue's promise obvious

**Evidence: Code + Visual.** `AddToQueueView.swift:91` pastes and immediately calls `addLink`; the visible label only says “Paste copied link.” Suggestions are the first eight unread stories without search. URL fallbacks can produce “Watch”; saved links lack a feed source, causing the featured card to display “Source.”

**Change precisely:** make Paste populate the input and let **Add to Queue** commit. If retaining one-tap submission, label it **Paste and add**. Use a permanent **Article or video link** label and example placeholder. Display inline validation by the field, not only at the bottom of a potentially long Form. Explicit Cancel while adding must either cancel the operation or say the item will finish saving; `.interactiveDismissDisabled` alone does not handle the Cancel button.

Save immediately with domain attribution, then enrich the title and image. Use **Already in Queue** for a duplicate and keep its original order unless the user explicitly chooses to move it. `QueueLinkService.park` currently changes the completion timestamp of an already-saved item. Introduce `savedAt` if saved order must be independent of read completion.

Keep a few optional **From your sources** suggestions, with **Find a story** leading to deliberate search. Do not build a recommendation feed inside the add sheet. On success dismiss to Queue and show the new item/confirmation without scrolling away from an active reading task.

**Acceptance:** Paste behavior matches its label; invalid input remains editable; offline save works; duplicates are explained; raw YouTube `watch` paths are not presented as confidently extracted titles.

### UX14 — Preserve failed source inputs and simplify the common add path

**Evidence: Code.** `AddSourceView` starts with a 4–10-line URL field and folder section. `AddSourceViewModel.add` clears `addressList` even after partial success and reports only the first three failures. Cancel remains active during additions.

**Change precisely:** default to a one-source form: labeled website/feed field, optional Folder, Add. Put multi-line input behind **Add several sources**; continue accepting pasted line breaks by switching to batch mode. Use an explicit batch submit button rather than assigning “Go” to a field where Return is also needed for another URL.

Retain failed inputs in the field, display each failed source with a reason, and offer **Retry failed**. Report “3 added · 2 need attention” inline; do not cover partial failure with a full-screen success overlay. Keep succeeded entries deduplicated on retry. Choose and implement one cancellation contract: cancel remaining requests while preserving completed additions, then report how many were added.

Show **New folder name required** when New Folder is selected with no name. Do not silently add to Unfiled. After success, return to the containing source list and update it immediately.

**Acceptance:** with five inputs and two failures, only the failed two remain for retry. Cancellation stops future additions and does not claim nothing happened. Existing source detection is explicit and non-destructive.

### UX15 — Source toggles must match what the user sees

**Evidence: Code.** `SourceDetailView` shows Included in Feed, Included in Today, Include videos, and Include Shorts for every source. Local ingestion uses filter rules; `FeedFolderGrouping.openArticles` does not filter by `feed.isEnabled`. FreshRSS upsert does not apply the same local `FeedService.insert` filtering path. Recent articles are rendered with `ArticleRow` but are not buttons.

**Change precisely:** rename the master control **Follow this source** or **Fetch new stories**, depending on the exact supported behavior. If paused sources' existing stories stay visible, say “Stops fetching new stories; existing stories stay available.” Do not label that behavior Included in Feed. Disable dependent Today controls with an explanation when following is off. Only show video/Shorts controls for relevant sources.

Apply a shared eligibility policy to local and FreshRSS content where the UI promises the same filter. State whether blocked words affect only future imports or also current visible stories; choose future imports as the conservative default and label it. Provide a small preview of matching recent titles before excluding existing content. Make Recent rows open their stories, or use a visibly noninteractive preview style.

Move icon customization to an explicit Edit/Change icon action so tapping a folder's leading icon usually navigates to the folder instead of opening an unrelated task. Preserve customization through the existing context menu.

**Acceptance:** local and FreshRSS sources honor equivalent controls; toggles cannot imply impossible combinations; paused behavior is explained; no row looks actionable but does nothing.

### UX16 — Empty, finished, loading, and failed are different states

**Evidence: Code.** `CurrentView.caughtUp` combines refreshing, just-cleared, no-feeds, and no-stories conditions. An already-created empty daily deck is returned unchanged by `generateIfNeeded`. “Tomorrow, a new hanging” and a Refresh CTA can appear without explaining why no story is eligible.

| State | Proposed message | Primary action |
| --- | --- | --- |
| No followed sources | “Choose something to read” / “Add a website or connect your subscriptions.” | Add source |
| First fetch | “Finding your first story…” | No fake progress button; keep cancellation/navigation available |
| Sources exist, fetch failed | “Your sources couldn’t update” | Retry |
| Sources exist, none eligible for Today | “Nothing for Today yet” / explain source inclusion or publication window | Manage sources |
| Daily set completed | “That’s all for today” / “Your next selection arrives tomorrow.” | No prominent replenishment action |
| Empty Queue | “Nothing saved for later” | Add a link; Open Today secondary |
| Empty search | “No matching stories” | Clear search |
| Empty folder | “No recent stories in this folder” | View sources |

Permit a first empty daily deck to become populated after successful initial source setup when no story has yet been presented. Preserve the frozen-day rule after a reading selection has begun. Keep this distinction in domain tests rather than working around it with refresh buttons.

**Acceptance:** every state can be reached with deterministic fixtures. No success/finished copy is displayed for a fetch failure or an unconfigured library.

### UX17 — Settings should explain choices before exposing machinery

**Evidence: Code.** `SettingsView` combines reader controls, retention, folder/file/Drive setup, a raw Gemini key, FreshRSS account actions, import/export, seed restoration, and About in one Form. Drive uses “Stop Using Folder.” Conflict buttons say “Keep this device” and “Use cloud file” with little comparative information. Recovery copies exist in `LibrarySyncService.writeRecoveryCopy` but errors are ignored and the recovery is not surfaced.

**Change precisely:** Settings root becomes a short list of destinations with summaries:

- Reading — “Serif · Standard” plus a small sample on the detail page.
- Sources & Import — Manage sources, Import subscriptions, Export subscriptions, optional starter catalog.
- Sync — status summary, FreshRSS, then library sync; explain their different roles.
- Storage — retention and offline-content explanation.
- Video summaries — “Off” or “Configured,” key management one level deeper.
- About — app/version information and concise philosophy.

For library sync, explain **Sync reading state across devices** before offering iCloud folder, Google Drive, and Advanced → existing file. Name the active backend in actions: **Disconnect Google Drive** versus **Stop using this folder**. Retain the accurate reassurance that unlinking does not delete the cloud file.

For a conflict, present a dedicated review sheet with both versions' timestamps and available source/saved-item counts. Describe which side will be replaced or merged according to the actual reconciler; do not promise a full replacement if `LibraryMerge.apply` preserves local-only records. Provide Cancel. Verify and surface a recoverable local snapshot before applying a destructive choice; backup failure must be visible.

**Retention mismatch:** Settings says only unread articles expire, but `ArticleRetentionService.purge` selects all old non-saved, non-starred articles, including read/skipped; it also protects IDs from all deck items, not only today's. Decide the intended policy before polishing the wording. Recommended: keep Queue indefinitely, retain History metadata, and expire old unkept content according to a clearly described rule. Use a preview such as “This will remove downloaded content for N stories” only when that is what the implementation actually does.

**Acceptance:** users can distinguish source-server sync from library-file sync. Disconnect labels identify the right service. A retention setting never promises protection that the purge code does not provide. Recovery exists and works before its UI claims it does.

### UX18 — A widget is a promise to open a specific story

**Evidence: Code.** `MonoRssWidget.swift` embeds `onefeed://reader/<UUID>`. `CurrentView.swift:77` ignores that UUID and opens `viewModel.currentArticle`. `AppRootView.handleIncomingURL` handles subscriptions but does not explicitly select Today and resolve reader links. Inline widgets reuse a vertical layout containing “NEXT” plus another line.

**Change precisely:** centralize reader deep links in the root router. Parse the article ID, select the appropriate destination, wait for the model to be ready, and open that exact stored article. If no longer present, show **This story is no longer available** with Open Today. Do not silently substitute another story.

Create dedicated layouts for inline, rectangular, small, and medium widget families. Inline should be a single compact label such as **Read: [title]**, constrained by the family. Use media-aware duration language, not universal reading minutes. Keep no unread totals or urgency badge.

**Acceptance:** test cold and warm launches from Queue/Settings, stale IDs, saved stories, and no current story. The story opened matches the widget, or an explicit unavailable state is shown.

### UX19 — Fix the small interaction details that exclude people

**Evidence: Code.** `FolderEmojiButton` is 36 × 36 points. `FolderEmojiPicker` forces eight columns: on a 375-point screen with 40 points of horizontal padding and seven 6-point gaps, each cell is about 36.6 points wide. The 44-point height does not fix width. Several operations are only exposed by swipes/context menus. `OneFeedMarkPulse` wraps a mark hidden from accessibility; verify that the intended updating label remains exposed.

**Change precisely:**

- Use at least 44 × 44-point touch regions. Make the emoji grid adaptive with a minimum 44-point item width and 6–8-point gaps; fewer columns at large type sizes.
- Expose named accessibility actions for Add to Queue, Done, Skip, and restore on article rows, in addition to native swipe actions. Keep one combined article announcement: title, source, type, duration, status.
- Announce successful save, error, and completion once after the result. Do not announce each progress increment or merely change a hidden glyph's label.
- Preserve focus predictably after removing an item; focus the next item or the empty-state heading, not the toolbar by accident.
- Reader HTML should include appropriate language/direction metadata, main/article structure, heading hierarchy, and meaningful image alternatives where available. Preserve text selection and native links.
- Keep visual icons redundant with text. Pair errors with specific text and recovery; color alone is insufficient.
- Honor Reduce Motion, Increased Contrast, and Reduce Transparency. Prefer native chrome's adaptations over manually reproducing glass.

**Acceptance:** complete save/read/restore/add-source flows using VoiceOver and Switch Control; navigate macOS with keyboard alone; verify largest Dynamic Type without clipped actions. These are future manual acceptance checks, not checks completed during this review.

### UX20 — Motion should acknowledge actions without delaying them

**Evidence: Code.** `OneFeedMotion.holdBeforeDismiss` waits 180ms for Skip, 320ms for Done, and 520ms for Queue. `ReaderView.finish` waits before calling persistence through `onFinish`; a success curtain and haptic begin first. The test launch argument bypasses the delay, so current screenshot tests do not reproduce normal timing. Source addition has another 420ms pause. Some parent animations do not consult Reduce Motion even though child marks do.

| Before | After | Why |
| --- | --- | --- |
| Full-screen Queue/Done/Skip curtain before persistence | Commit locally first; dismiss with native transition; show compact result/Undo on the originating screen | Success must be true; repeated decisions should not block reading |
| 520ms hold and particles on ordinary saves | No artificial hold and no particles for repeated saves | Saved reading is a routine action, not an achievement |
| 200ms press scale on every directory row | Immediate pressed fill; release fade 100–160ms; retain 0.97 scale only for a prominent standalone button if useful | Keep repeated list navigation quiet and responsive |
| 350–400ms broad page/decision animation | Restrict custom state fades to 150–200ms; leave native sheet/navigation timing to the system | Avoid animating unrelated layout and content |
| Parent `.animation` independent of Reduce Motion | Gate movement at the owner; static state or short opacity change under Reduce Motion | Child-only guards do not cover parent transitions |

**Motion-review verdict:** block reuse of the current blocking success-curtain pattern in the redesign. This is a code-level timing/purpose finding, not a claim that dropped frames were observed. Do not apply web compositor rules mechanically to SwiftUI's native List layout.

Only two additional motion opportunities survive the restraint check:

| Location | Purpose | Frequency | Exact proposal | Reduced Motion |
| --- | --- | --- | --- | --- |
| New result/Undo banner after UX11 | State indication; makes an action's result legible | Occasional | Opacity 0→1, 160ms, cubic Bézier (0.23, 1, 0.32, 1); no slide or scale | Static appearance or 100ms opacity |
| Reader excerpt-to-full-text state after UX10 | Prevent a jarring content replacement | Occasional | Preserve anchor first; fade only status text over 160ms with the same curve; never animate article paragraphs | Instant replacement of status |

Rejected: staggered article entrances (moves material being scanned); parallax hero imagery (distracts from reading); tab bounces (frequent navigation); completion confetti (creates productivity pressure); custom sheet physics (native behavior already solves it).

**Acceptance:** feedback does not delay persistence or the next task; fast repeated actions cannot double-commit; reduced-motion users get all outcome information without movement. Review on real hardware later, including ordinary launches without `-uiTesting`.

### UX21 — Make media behavior explicit and summaries optional

**Evidence: Code.** Videos initially open Website. The reader automatically offers a summary dialog for each eligible, not-yet-declined video. Summaries occupy an independently scrolling region capped at 160 points. Reader options mix typography with the video summary command. Podcast/music items exist in the domain, but there is no dedicated audio-player flow in these screens.

**Change precisely:** label the main task **Watch video** or **Listen at source** as appropriate. Do not imply an offline player exists. For videos, place **Generate summary** in More or a collapsed section below the main content; never interrupt opening with a prompt. On explicit first use, disclose that the video link is sent to Google, then request the key if needed.

Show generated content under **AI summary · Gemini** with an Expand/Collapse control and Retry when generation fails. Avoid two simultaneous narrow scroll panes. Keep typography settings for text, media commands for media, and clear failure messages near their action. Do not use the AI summary as an unlabeled editorial excerpt elsewhere; `Article.displayExcerpt` currently prefers `aiSummary`.

**Acceptance:** opening a video immediately supports watching without a summary prompt. Summary attribution remains visible when expanded and in any preview. Audio items have a working external playback destination or an honest unavailable state.

### UX22 — Search should recover something intentional

**Evidence: Code.** Search exists in `FeedStreamView`, but no construction of that view was found in the active app routing. Queue, ArticleCollectionView, History, and Sources have no equivalent search.

**Change precisely:** add native search to Queue and History for title/source, and to Sources for name/domain. Add search to active Feed collections, reusing the matching logic from the dormant stream where appropriate. Preserve the current collection's scope; don't search the internet or inject recommendations. Debounce only if measurement shows expensive matching; do not slow a small local list unnecessarily. Keep empty-query and no-match states separate.

Do not revive the entire dormant FeedStream screen just to recover its search. Mark `FeedStreamView` and `LibraryView` as not currently routed in implementation planning so future agents do not polish the wrong screen.

**Acceptance:** find a saved article with a long title by source name; clear search without losing the original scroll position; search History includes both Read and Skipped states.

### UX23 — Remove blanket spacing and make larger screens intentional

**Evidence: Code.** `oneFeedGroupedListStyle` adds 96 points of bottom inset. Settings adds its own 96 points, a 72-point empty section, and receives 88-point floating-tab clearance at the root. These layers create excess blank space risk. `oneFeedMacSheetCanvas` fixes sheets at 760 × 720 while the app permits a 560-point minimum window height. iPad uses the same tab/detail structure as phone.

**Change precisely:** give each screen one owner for bottom safe-area clearance. First remove the duplicate empty settings section and redundant root clearance; then measure what native TabView already reserves before selecting any additional inset. Do not replace three magic numbers with a fourth global constant.

Use content-width limits on regular-width screens: article lists about 680–760 points centered within available space; reader measure constrained by typography rather than full window width. Make modal dimensions adapt to actual available bounds, with scrolling for longer forms. Keep Today one story on iPad; do not fill space with a dashboard or multi-column reading cards.

On macOS, retain the sidebar, add useful discoverable keyboard commands for Add to Queue and Find, and ensure Close/Escape works. Use platform-default navigation and menus instead of carrying every iPhone bottom-bar decision unchanged.

**Acceptance:** last rows remain reachable above the tab bar with a modest trailing margin; no huge blank settings footer; narrow iPad multitasking and short Mac windows do not clip sheet actions. Use screenshots/device checks later to set final dimensions.

### UX24 — Tighten copy and make appearance changes predictable

**Evidence: Code.** Gallery metaphors recur in onboarding/loading/completion. Save/Queue/Park and Piece/Story/Article are mixed. Settings says “Done and Save sync” although the UI says Queue. Reader preferences are bare pickers, and metadata styling differs among shared rows, Queue, HTML, and widgets.

| Current wording | Recommended wording | Reason |
| --- | --- | --- |
| “Today is the hanging” | “A small daily selection from your sources” | Explains the product without decoding a metaphor |
| “Hanging the room…” | “Updating your sources…” | Describes ongoing work |
| “The room is still.” | “That’s all for today.” | Communicates completion clearly |
| “Park a story” | “Save a story to Queue” | Matches navigation |
| “Done and Save sync” | “Done marks a story read in FreshRSS. Add to Queue stars it. Skip stays in OneFeed.” | Gives exact consequences |
| “Source” for a pasted link | URL domain, otherwise “Saved link” | Real attribution rather than a placeholder |
| “Restore all seeded sources” | “Choose starter sources” | Describes a user task, not implementation |
| “Stop Using Folder” for Drive | “Disconnect Google Drive” | Identifies the actual connection |

Keep editorial warmth in the app identity and article typography. Use plain language for actions and error recovery. Rename reader font choices to **Serif**, **Sans serif**, and **Monospaced**, and show a short live reading sample in Reading settings. Apply changes immediately without moving the current reading position. Pull the About version/build from bundle metadata instead of hardcoding Edition 1.0.

**Acceptance:** the same concept has one public label across onboarding, reader, Queue, Settings, widget, and accessibility text. Preference changes show their effect before the user leaves the settings page.

## 6. Shared visual specification

These are proposed OneFeed design tokens, not inferred screenshot measurements. Keep existing token names when they already express the same purpose.

| Element | Specification |
| --- | --- |
| Page canvas | Existing adaptive plaster |
| Article surface | Existing adaptive paper, opaque; content does not use glass |
| Primary text | Existing ink |
| Secondary meaningful text | Existing graphite |
| Decorative tertiary content | Stone; never rely on it for small critical copy in light mode |
| Accent | Terracotta for brand/action emphasis; separate accessible reader-link color |
| Spacing scale | 4, 8, 12, 16, 20, 24, 32 points |
| Phone page inset | 20 points, unless a native list already supplies equivalent margins |
| Queue card | 12-point corner radius, 16-point padding, 10-point inter-card gap, 1-point outline |
| Dense list rows | 16-point horizontal / 12-point vertical padding; visible inset separator; no outer card per settings row |
| Section title | Semantic subheadline/semibold; 8 points to content; 24 points between conceptual sections |
| Article title | Semantic headline; serif scaled title for the featured Today story only |
| Source / details | Subheadline / caption; graphite; separate lines when necessary |
| Thumbnail | 64 × 64, trailing/top aligned, 10-point corners; decorative and omitted at accessibility sizes |
| Featured media | Real image; bounded aspect-aware crop; do not reserve 248 points for a failed image |
| Buttons | Semantic body weight; touch region ≥44 × 44; primary action height at least 50 and allowed to grow |
| Pressed state | Warm fill inside the same rounded boundary; no rectangular flash outside card |
| Chrome | Native navigation/tab materials; no extra glass layers on article content |
| Focus/selection | Explicit accessible outline or native focus indicator; never depend on near-identical paper colors |

Shared component responsibilities:

- `ArticleSummaryContent`: title, source fallback, media kind, duration/date, optional history status, thumbnail policy, accessibility summary.
- `SavedArticleCard`: card container and touch target, composing that content.
- `ArticleListRow`: dense native-list container with separator, composing that content.
- `FeaturedStory`: Today-specific hierarchy and full title; do not make every saved story a hero.
- `ActionResultBanner`: success/error/Undo feedback, exposed after a real outcome.
- `ReadingAppearance`: one semantic source for native controls, HTML colors/type, and preview content.

These names describe intended responsibilities; do not create an abstract component framework before the first concrete screen needs it.

## 7. External references: borrow the useful behavior

Research checked September 15, 2026. Product documentation establishes described features; only the Reeder image below was visually inspected as a useful external layout reference. No competitor app was interactively tested.

### Reeder — reduce obligation; distinguish content units

Reeder's official page describes replacing unread counts with synchronized timeline position. Its official promotional screenshot visibly separates entries using a selected surface/dividers, distinguishes source from story text, and uses trailing media. Borrow the lack of unread pressure and clear content grouping. OneFeed should retain a finite Today selection instead of adopting Reeder's unified timeline, social content, shared feeds, or multiple bookmark taxonomies. These are different product models. [Official product description](https://www.reeder.app/) · [Inspected official image](https://www.reeder.app/reboot/screen.png).

### Instapaper — put reading comfort within reach

Instapaper's documentation describes an Aa control for font, size, theme, width, and line height. Borrow immediate typography control and clear reading-first organization. OneFeed already has font/size settings; improve their readability, preview, and position preservation before adding more options. Do not add a large theme library, highlights workflow, or speed-reading feature just because another reader has them. [Read & Manage](https://www.instapaper.com/docs/getting-started/first-article) · [Reading documentation](https://www.instapaper.com/docs/read).

### Readwise Reader — distinguish a daily selection from the full library

Its Daily Digest combines Feed and saved-for-later material to aid triage and rediscovery. Borrow the clear distinction between a deliberately scoped daily surface and the larger library. For OneFeed, keep source selection deterministic and protect manually saved Queue items rather than silently recycling them. Do not copy digest reminders, icon badges, email engagement, or a power-reader dashboard. [Official Daily Digest documentation](https://docs.readwise.io/reader/docs/faqs/daily-digest).

### Bear — coherent reading appearance

Bear's official material describes a read-only mode for focused reading and coherent themes across the writing experience. Borrow the discipline of making all reading surfaces agree. Keep OneFeed's own cream/ink/terracotta colors and native font families. The installed reverse-engineered Bear spec was consulted as secondary inspiration, not treated as verified measurements or authoritative accessibility advice. Its fixed-size-label advice should not override Apple's Dynamic Type guidance. [Official read-only-mode announcement](https://blog.bear.app/2025/02/bear-2-3-11-update-read-only-mode-new-themes-and-more/) · [Official theme explanation](https://bear.app/faq/about-free-and-pro-themes-in-bear/).

### Apple — readable, adaptable, predictable controls

Apple's design guidance supports sufficient contrast, aligned content, touch targets of at least 44 × 44 points, and layouts fitted to the device. Dynamic Type guidance supports text and layout that adapt together. Use these as platform constraints, not a reason to replace OneFeed's visual identity. [UI Design Dos and Don'ts](https://developer.apple.com/design/tips/) · [Dynamic Type](https://developer.apple.com/documentation/SwiftUI/DynamicTypeSize) · [Typography detail](https://developer.apple.com/videos/play/wwdc2020/10175/).

Apple-authored local references consulted: `SwiftUI-WebKit-Integration.md`, `SwiftUI-New-Toolbar-Features.md`, and `SwiftUI-Implementing-Liquid-Glass-Design.md` from the installed `swiftui-skills/docs` directory. They ground the recommendations to keep native WebView/navigation behavior and native chrome rather than inventing a parallel browser or glass system. API details must still be compiled against this project's SDK during implementation.

### Reference search that did not earn a recommendation

UI Radar's public [UIZZE](https://uizze.com) search returned an ElevenReader entry whose inspected image was decorative launch artwork, not a usable reading/queue screen. An exact Instapaper retry returned no results. Those references were rejected; no layout claim is based on their metadata. No competitor logos, artwork, distinctive brand assets, or literal identity should be copied.

## 8. Screenshot-specific visual review

Only three visual findings are warranted from the supplied Queue image:

| Observation | User impact | Concrete response |
| --- | --- | --- |
| Several articles share one paper block without separators | Start/end boundaries require interpreting whitespace | Keep the earlier individual-card fix; extend a consistent boundary rule to remaining article lists (UX07) |
| Long source text sits close to the article title and reading/date information | It competes with the title and hides useful metadata in crowded rows | Separate title, source, and details with semantic type roles; use domain fallback (UX07–08) |
| The lone thumbnail produces a different text starting edge from the text-only entries | Scanning jumps horizontally | Consistent leading text alignment with trailing thumbnails; no empty image placeholders (UX07) |

The screenshot does not establish whether a toolbar overlaps incorrectly during scrolling, whether controls fail, or how dark mode looks. It also predates the current Queue edit. Do not invent those findings or assign a generic “AI-looking” score. The problem is identifiable grouping and hierarchy, not lack of visual novelty. The optional [UI Slop Score tool](https://uizze.com/tools/ui-slop-score) can support a future rendered review, but is not a substitute for the acceptance checks here.

## 9. Implementation sequence

### Phase A — Preserve intent and repair trust

Implement UX01–04 first. Then implement Undo (UX11), reader contexts (UX02/09), and accurate empty states (UX16). These establish a dependable action model for the visual redesign. Review source/catalog deletion changes separately because they alter data behavior.

Deliverable: every visible action produces the advertised persisted state; saved articles survive unrelated source changes; errors and success are truthful.

### Phase B — Make the daily experience immediately legible

Implement Today/navigation (UX05–06), shared row hierarchy (UX07), typography/contrast (UX08), and touch/accessibility fixes (UX19). Keep the current Queue card work as a starting point, not a task to redo. Implement one representative shared row before migrating all callers.

Deliverable: one obvious Today choice; consistent card/list boundaries; readable controls at every supported text size.

### Phase C — Finish the important journeys

Implement reader continuity (UX10), onboarding (UX12), Queue/source addition (UX13–15), Settings/sync (UX17), and widget routing (UX18). Update source/link copy and test deterministic failures along the way.

Deliverable: first use, daily reading, saving, recovery, and returning later form a complete experience.

### Phase D — Refine without expanding the product

Implement motion restraint (UX20), media/AI organization (UX21), deliberate search (UX22), adaptive layouts (UX23), and final language consistency (UX24). Do not add new services, social surfaces, recommendation models, or engagement metrics.

Deliverable: a calm, coherent application across phone, tablet, and desktop.

## 10. Validation plan for later implementation

No checks in this section were run for this report. Existing tests are useful scaffolding, not proof these proposed interactions work.

### Behavior tests

| Scenario | Required outcome | Existing test home |
| --- | --- | --- |
| Save/skip/done through Today card, swipe, reader, Feed, Queue | One consistent state across article, deck, widget, and remote intent | `DailyDeckTests`, `ArticleStateTests`, `SwiftDataFreshRSSSyncTests` |
| Read-and-starred remote snapshot after finishing a Queue item | Remains completed; does not re-enter Queue | `SwiftDataFreshRSSSyncTests` |
| Daily generation with saved candidates | Saved stories stay in Queue | `DailyDeckTests` |
| History Add to Queue | Persists and is visible after relaunch | `ArticleStateTests` plus UI flow |
| Undo before/after remote flush and while offline | Correct final local/remote state without reversing unrelated actions | `OfflineMutationTests`, `FreshRSSTests` |
| Empty first deck followed by successful subscription | Can produce first selection; completed deck does not refill | `DailyDeckTests` |
| Partial add-source failure and cancellation | Failed inputs retained; successes not duplicated | source-service tests and UI flow |
| Metadata timeout / duplicate pasted link | Link persists; feedback and ordering correct | `QueueLinkServiceTests` |
| Source removal / catalog version update | Saved articles and user organization protected | `FeedSeedTests`, source-service tests |
| Retention with read/skipped/saved/starred/historical-deck stories | Agreed policy matches Settings copy | `RetentionAndExtractionTests` |
| Partial/offline refresh | No false last-success timestamp | `RefreshProgressTests` and refresh-service tests |
| Cloud conflict recovery | A usable backup exists before a destructive operation claims protection | `LibrarySyncServiceDriveTests`, `CloudFileReconcilerTests` |
| Widget deep link from cold/warm app | Opens exact ID or explicit unavailable state | UI routing tests |

### Visual and accessibility matrix

- Small supported iPhone width, typical iPhone, landscape, iPad split-screen, short macOS window.
- Light, dark, Increased Contrast, Reduce Transparency, Reduce Motion.
- Standard text, largest standard text, largest accessibility text; long English titles, French UI copy, and RTL content if supported.
- One item, five mixed items matching the supplied screenshot, long collection, all text-only, failed images, long source names, unknown duration, invalid/expired link.
- Each screen: loading, populated, empty, partial failure, full failure, offline, successful completion, cancelled action.
- Keyboard shown in Add Source/Add to Queue; return from a sheet without unexpected data changes.
- VoiceOver reading order, named actions, announcements, and focus after deletion/Undo.
- Reader: cached excerpt, extracted full article, long code block/table, large image, paywall/failed extraction, video website, audio external link, summary error.

Use screenshot fixtures for layout checks; use service tests for state correctness; use real interaction for focus, gestures, cancellation, and reading-position restoration. Do not infer those behaviors from screenshots.

### Lightweight usability checks

Ask a few readers to perform these tasks without coaching: read today's story; save it for tomorrow; recover an accidental Done; paste a link; find a previously read story; pause a source; explain what syncs. Record confusion, mis-taps, failed task completion, and whether the labels predict the outcome. Do not add analytics, session-time goals, or engagement targets to run this exercise.

## 11. Coverage and skill notes

### App surface coverage

| Area | Files/symbols reviewed | Main recommendations |
| --- | --- | --- |
| Root and startup | `AppRootView`, `OneFeedApp`, `IncomingFeedURL` | UX06, UX12, UX18, UX23 |
| Today | `CurrentView`, `CurrentViewModel`, `DailyDeckService`, deck models | UX01, UX05, UX16 |
| Queue | `SavedView`, `SavedViewModel`, `AddToQueueView`, `QueueLinkService`, `ArticleQueueService` | UX01, UX07, UX11, UX13 |
| Feed and folders | `FoldersView`, `ArticleCollectionView`, `FeedStreamView`, `BrowseRefresh`, `ArticleActions`, `FeedFolderGrouping` | UX04, UX06–07, UX15, UX22 |
| Reader | `ReaderView`, `ReaderViewModel`, `ReaderHTML`, `ArticleBrowserView`, extraction policy/service, article display fields | UX08–10, UX19–21 |
| History | `HistoryView`, `HistoryViewModel` | UX02, UX11, UX22 |
| Onboarding | `OnboardingView`, `OnboardingViewModel`, seed application paths | UX12, UX24 |
| Sources | `SourcesView`, folder/detail/add subviews, all source view models, `Feed`, seed service | UX03, UX14–15 |
| Settings and sync | `SettingsView`, `SettingsViewModel`, FreshRSS/Gemini forms, `CloudLibrarySettingsSection`, retention, cloud conflict/recovery and mutation paths | UX03–04, UX17, UX24 |
| Shared design/platform | `OneFeedTheme`, `OneFeedMark`/motion, `OneFeedCelebration`, `RefreshProgressBanner`, `FolderEmojiPicker`, `PlatformSupport`, `AppPreferences` | UX07–08, UX19–20, UX23 |
| Widget | `MonoRssWidget`, `WidgetSnapshotStore` | UX01, UX18 |
| Dormant navigation surfaces | `LibraryView`, active-call-site search for `FeedStreamView` | UX22; avoid spending effort on unreachable screens |
| Supporting code | RSS/YouTube classification, filtering, metadata/extraction; FreshRSS mutations/upsert; library document/merge/reconciler; Drive setup; OPML; background refresh | Reviewed for user-facing promises, failures, and persistence; no claim of exhaustive backend audit |
| Tests | UI tour and relevant state/deck/retention/link/sync test suites | Validation gaps in section 10; no tests executed |

### Skills applied and boundaries

- **iOS Product Design:** native containers, hierarchy, contextual actions, presentation ownership, all-state planning, accessibility.
- **Product Design index/audit framework:** evidence-linked findings, flow coverage, explicit limits. The user's no-simulator instruction takes precedence over the skill's fresh-capture workflow; this report is a code-and-supplied-screenshot review, not an executed end-to-end visual audit.
- **UI Radar:** attempted targeted public reference search; rejected irrelevant imagery rather than treating search metadata as evidence.
- **Apple Design / Emil Design Engineering:** immediate truthful feedback, spatial consistency, restraint, before/after motion findings. Web-specific implementation rules were not blindly transferred into SwiftUI.
- **Review Animations / Find Animation Opportunities:** exact timing review, two justified opportunities, explicit rejected decorative motion.
- **UI Slop Score:** three screenshot-grounded hierarchy findings, no unsupported score or imagined screen critique.
- **iOS Design MD:** secondary Bear reference checked against OneFeed's existing tokens; did not import another brand or fixed-size accessibility exceptions.
- **SwiftUI Skills:** Apple-authored WebKit, toolbar, and material documentation for feasibility.
- **Google Code Reviewer:** evidence and severity discipline for user-visible state problems; this is not a full PR approval review.

“Use all skills” was applied as using the relevant available design/review capabilities. Image generation, Figma writes, website hosting, Supabase, document/spreadsheet production, skill installation, and simulator/profiling workflows do not improve a Markdown-only native-app review and were not invoked. No unrelated assets, integrations, or app changes were created.

## 12. Definition of a better OneFeed

The redesign succeeds when the user can immediately identify one story to read, distinguish every saved item, close without consequences, understand what Done/Skip/Queue will do, recover mistakes, and trust the app's loading and sync messages. It should become easier to read and easier to leave—not more demanding to maintain.
