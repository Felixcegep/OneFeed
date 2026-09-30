# OneFeed learning: phase-one design brief

## Goal and design basis

Platform scope: new screens and learning interactions are iPhone-only. Preserve the existing Mac interface. Shared SwiftData and library records remain compatible so new data is not lost by the common persistence layer.

Help someone deliberately keep one idea in their own words, then find and revise it later. Preserve the editorial reading experience and distinguish reading completion from understanding.

This brief extends the current code and UXAudit design system. It is a proposed implementation target, not a claim that live screens were visually verified.

Designeer could not be opened live through the available browser or web tools. Its archived resource directory was available and identified relevant typography and accessibility references. Research used:

- Designeer archived directory: https://archive.vn/2026.09.26-133235/https%3A/designeer.xyz/
- Practical Typography: https://practicaltypography.com/typography-in-ten-minutes.html — body text, measure, spacing, and hierarchy deserve attention before decoration. Apply those principles with native scalable typography.
- Inclusive Components: https://inclusive-components.design/ — labels, operable controls, and component states must remain accessible.
- Readwise Reader: https://readwise.io/read — source-linked annotation and later revisiting provide workflow reference; do not reproduce its full feature density.
- Bear: https://bear.app/ — native note editing is a product reference. No screenshot comparison was available here.

## Visual style

Keep OneFeed's theme aliases, including their existing dark variants:

| Role | Existing light value | Use |
| --- | --- | --- |
| Canvas/plaster | #F3EFE5 | Screen background |
| Paper | #FAF7F0 | Reading and grouped content |
| Ink | #171715 | Titles, prose, primary controls |
| Graphite | #625F58 | Supporting information |
| Sand | #D8D2C7 | Separators and field outlines |
| Link | #355F59 | Explicit source links |
| Sage | #52705B | Existing reading completion semantics |
| Attention | #A94F37 | Sparse attention markers |

Use serif prose for explanations and takeaway text, existing SF/system sans for controls and list titles. Use semantic font sizes and allow Dynamic Type. Page inset stays 20pt, fields use the existing 10pt radius, grouped cards use 12pt only when a meaningful group exists. Use the existing scalable iPhone text styles and available width. Mac layout changes are outside this implementation. Avoid card-wrapping every row or using shadows for hierarchy.

Use existing press and presentation motion. Respect Reduce Motion; keep long prose stable when metadata or save state changes.

## Navigation

Retain Today, Queue, Feed, Settings for phase one. Add a clearly labeled Ideas destination reachable from Today. Ideas has its own navigation stack/list detail. Do not revive the superseded LibraryView.

Longer-term roadmap remains Today, Library, Knowledge, Settings. That consolidation should follow validation of the new learning workflow.

## Capture, refine, finish

Opening a source stays focused on its content. Summary remains an explicit reading-options action. The deliberate Done action enters the existing optional takeaway task.

The learning flow has three distinct steps:

1. **Capture a draft.** Save incomplete thoughts from the reader or takeaway. No polished title or finished explanation is required. Copy the source attribution immediately. This is saved work that can be returned to later.
2. **Refine it yourself.** Open a draft from the Drafts section. Keep the original rough capture visible while writing a meaningful title and a separate explanation in your own words. Add source URLs if needed. Save progress without claiming the note is complete.
3. **Finish the note.** Explicitly mark it finished after supplying a title, explanation, and an attributed source. Move it into Finished notes. Preserve the rough capture and all source attribution.

Rewriting is manual, per the user's preference. A draft is not automatically rewritten or promoted by AI, reading completion, or saving an editor. The source takeaway remains independent from the knowledge note.

Takeaway action: “Save as draft” stores the rough text and source, then offers “Refine draft”. Reader option: “Capture a draft” opens a small capture editor. Neither flow asks for polished prose before the capture is saved.

## Drafts and finished notes

Keep the existing Today entry point and searchable Ideas destination. Separate Drafts from Finished notes with native section headers and explicit draft status. Search includes title, rough capture, explanation, and source title. Most recently edited items come first within each section.

A draft detail emphasizes the unfinished capture and provides “Refine draft”. A finished detail emphasizes the authored explanation and sources, while retaining the original capture as supporting context. Standalone captures can be saved as drafts; finishing requires an attached source (including imported books and PDFs) or a manually added source URL.

## Refinement and editing

The refinement editor is a writing page: a large unboxed title and a generous native rich-text body on the existing paper background. Its keyboard toolbar offers Body, Heading, Bold, Italic, and Bullet list controls. Native text selection, dictation, and undo remain available. Original capture sits in a disclosure section; Sources sit below the body. Formatting persists alongside plain text for search and in library sync. “Save draft” retains partial work. “Finish note” is an explicit promotion, with validation that preserves all typed input. Additional sources use editable URL references alongside copied source metadata. Original attribution survives removal of the article or feed.

Use semantic fonts, native sheets, explicit Save and Cancel, and prevent accidental swipe dismissal after typing. Deletion remains confirmed and records a sync tombstone. Completed notes can be edited without losing their original capture or references. Each successful save that changes the note records an immutable version containing draft/finished status, raw capture, explanation, formatting, and source attribution. Version history lets the user read earlier drafts and finished versions. Sync combines histories from both devices rather than discarding the losing side of a concurrent edit.

## Data and sync

Use a separate KnowledgeNote SwiftData model with a stable UUID and copied source attribution, independent of Article ownership. Do not repurpose ContentMemory, the existing semantic matching index.

New knowledge must participate in library-file sync/export before being described as available across devices. Keep old library documents readable with empty defaults for new collections. Sync draft status, original capture, and additional source references with backward-compatible defaults. Use modification timestamps and deletion tombstones with a documented deterministic merge, avoiding note resurrection. A source disappearing must not delete the idea.

## Implementation and validation order

1. Model, save operations, library snapshot/merge, schema registration.
2. Ideas list, detail, editor, source citation.
3. Takeaway conversion, manual reading action, Today entry.
4. Integration/build, persistence failure and duplicate-save review, accessibility and draft lifecycle checks.

This release does not implement capture selection anchors, review cards, projects, or graph visualization. Those remain later roadmap phases.
