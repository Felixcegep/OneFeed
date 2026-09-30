# OneFeed: an opinionated learning roadmap

Status: phase one is being implemented for iPhone; later phases remain a product plan.

## Product promise

Read or watch something worth your time, explain one idea in your own words, and use or remember it later.

OneFeed becomes a guided learning reader. Its strongest opinion is that saving, consuming, understanding, remembering, and applying are different accomplishments. Reading completion must never automatically mark something learned.

Keep the daily reading list, RSS discovery, YouTube playback, PDF/EPUB support, and existing takeaway prompts. Introduce a learning loop that works without AI. AI summaries, card drafts, related-note suggestions, and explanation feedback require an explicit action and user acceptance.

## Product rules

- One durable note expresses one idea in the user's own words.
- Quotes retain attribution and a location in the original source.
- User explanations and source assertions remain visibly distinct.
- Every learning step can be deferred or skipped. Avoid automatic modal prompts on opening or closing content.
- A source can be finished without producing a note. A note can be useful without becoming a review card.
- New review cards require approval. Avoid turning the entire reading queue into homework.
- The home screen offers a finite session and a clear stopping point.
- A related source is a suggestion; the user confirms knowledge connections.
- Notes and evidence survive removing an RSS subscription or cleaning up downloaded content.

## Navigation and daily behavior

Target four destinations: Today, Library, Knowledge, Settings.

Today recommends a short session in this order: review due cards, process one completed source, continue the current source, then discover a new source. The order is a default; the user can choose another task. Show actual time estimates only where available, and let the user choose a session budget. A proposed starting policy is up to five new cards and one source-processing task per day; adjust after observing real usage.

Library houses Queue, Feed, finished sources, and deferred processing. Keep current subscriptions and folder browsing within it. Existing navigation can remain during the first phases so the workflow can be validated before replacing tabs.

Knowledge offers Ideas, Open questions, Review cards, and Projects. Start with searchable lists and backlinks. A graph is a later option, after links are useful in ordinary views.

## Five user-facing objects

| Object | Storage direction | Key behavior |
| --- | --- | --- |
| Learning source | Extend existing Article; keep Feed as the subscription | Original metadata, saved reason, captures, processing state, source-note draft |
| Capture | New model | Quote, thought, question, or claim; optional source locator and response |
| Knowledge note | New model | One idea, explanation, position, evidence links, related notes |
| Review card | New model | Explicit prompt/answer, parent note, scheduling state |
| Project | New model in a later phase | A concrete application of notes with an outcome and reflection |

Use “learning source” in product language to avoid confusing it with the existing Feed/subscription concept. Do not rename Article as the first migration.

A source note is a structured document owned by a learning source, not another top-level object. Review events and relationship records may be separate storage entities even though the UI has only five main concepts.

Capture kinds start with Quote, Thought, Question, Claim. “Investigate” is an unresolved question; an idea can begin as a thought and become a note. Avoid six nearly identical entry forms.

A note's position is a Claim, Interpretation, Hypothesis, or Question. Evidence is attached separately. Do not present an automatically assigned “Fact” badge as proof that something is true.

## Phase 1: make the existing takeaway durable

Extend the current ReadingTakeawaySheet into an inline finish panel using the existing Learned, Why, Connect, and Use prompts. The user can finish with nothing, save a source takeaway, or turn it into an idea. Reopening a finished source restores the saved draft. No automatic summary modal.

Add Knowledge > Ideas with create, edit, search, and source backlinks. Save rough drafts immediately with their sources. Refine them manually into a separate explanation while preserving the original capture. Explicitly finish a note only after adding a title, explanation, and source. Keep Drafts separate from Finished notes. Keep existing Article.readingNote content as source takeaways. Do not automatically convert old takeaways into permanent notes.

Deliverable: capture an unfinished thought while reading, find it in Drafts, rewrite it in your own words with sources, and explicitly finish the note.

## Phase 2: capture and process

Add text selection capture in the reader and manual capture in the video view. Video captures can include a playback timestamp; PDFs need page references; web quotes need quoted text plus context and best-effort anchors. Unsupported content still permits a manual capture with a source link.

A processing workspace shows selected captures, “What is the main idea?”, “Explain it”, and “What remains unclear?”. Create one or more notes from a subset of captures. Preserve drafts and original quotes. Source processing states are separate from ArticleState: untouched, in progress, ready to process, processed, or dismissed. “Learned” is not inferred from these states.

Deliverable: capture during consumption, defer processing, return to it, and create a note with source evidence.

## Phase 3: questions, positions, and connections

Questions remain captures until promoted into standalone question notes. Show them in Open questions across sources. Resolution records the answer and evidence rather than deleting the original question. Allow answers to reopen as uncertain.

Add manual note links, backlinks, supporting evidence, counterarguments, and optional topics. AI may propose a related note or a missing concept after the user asks; never save those links or overwrite the user's explanation automatically.

Deliverable: a second source answers an open question or changes an existing opinion, preserving both the source and the revision.

## Phase 4: remember and explain

Start with question/answer and cloze cards. Other card formats can follow after these are useful. Cards are created from notes; AI generates editable drafts with supporting excerpts only on request.

Evaluate and pin a Swift FSRS implementation rather than writing a scheduler from scratch. Open Spaced Repetition maintains a Swift package: https://github.com/open-spaced-repetition/swift-fsrs . Hide tuning by default; expose Again, Hard, Good, Easy after an answer reveal. Add pause/suspend and daily new-card limits.

Keep an append-only review event log, including event ID, timestamp, card revision, grade, and scheduling-version metadata. Card edits can require a learning reset. For simultaneous reviews on two devices, merge event identities and replay using a documented deterministic ordering and reconciliation rule. Do not rely only on whichever due date was written last.

“Explain it” supports a whole-note retrieval exercise separately from a factual card. AI feedback cites supporting passages and distinguishes missing ideas from uncertainty; it is not an authoritative learning score.

Deliverable: create a card intentionally, answer it later, and see the same schedule on iPhone and Mac.

## Phase 5: apply and refine Today

A project can be small: implement something, write a paragraph, compare tools, or try an experiment. Link relevant notes, record what happened, and capture questions discovered during the attempt. Notes may be marked practiced based on that outcome; reading alone does not imply mastery.

Roll the proven tasks into the new Today order and consolidate navigation into the four destinations. Preserve easy access to regular reading.

Deliverable: explain an idea, test it in a real task, and record a new question that leads to another source.

## Architecture and migration requirements

- Use SwiftData models with stable UUIDs. Keep knowledge independent of Article deletion; save durable attribution and quote snapshots on evidence links.
- Extend the library file format and merge logic before offering cross-device learning. Include notes, captures, cards, relationships, review events, deletion tombstones, and explicit conflict behavior. Current library schema version is 2.
- Do not reuse ContentMemory as the user's notebook. It is currently a device-local semantic index for content matching. New knowledge models are user-owned records and need export/sync behavior.
- Migrate existing reactions and reading notes without altering reading state. Retain rollback/export paths for existing library files.
- Record source locators independently of cached bodies. If a page changes or an anchor fails, show the original quote and source metadata.
- Core capture, note editing, review, and export should work offline. Imported media support grows only when it fits the workflow.
- Export knowledge as readable Markdown plus structured JSON for locators, links, and scheduling history.

## Initial scope and success criteria

Build Phase 1 first and use it on real reading before adding spaced repetition. The first release needs an inline takeaway, durable ideas with provenance, and a way to revisit unfinished processing. Keep podcasts, lecture recording, course tracking, advanced card formats, and graph visualization for later.

Evaluate whether users return to notes, resolve questions, retrieve ideas successfully, and record applications. Treat saved-item counts and consumption volume as secondary metrics. Measure a funnel from finished sources to takeaways to notes to later reuse, while preserving the ability to finish without a note.
