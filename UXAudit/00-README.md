# OneFeed UX audit

This folder is `UXAudit/` in the OneFeed repo. Codex and other agents can read it next to the SwiftUI.

Handoff pack for another model. This is a source audit of the SwiftUI app, read from the project on 22 September 2026. It is not a pass on a running phone, so spacing and contrast that only show up in pixels are called out only when the code makes them obvious.

Upload this whole folder. Read the files in order. `08-priorities.md` is the short version if you only have room for one file.

## What OneFeed is

A personal reader for RSS, video, podcasts, and saved links. The job is a short daily list (Today), a place to park things (Queue), and a library of sources (Feed). Reading happens in one reader. Finishing an article is Done, Queue, Skip, or Not interested.

Visual materials already in the app: plaster canvas, paper groups, warm ink, serif for reading, SF for chrome. Do not propose a new visual language. Fix clarity, undo, and consistency inside this one.

## Files

| File | What it covers |
|---|---|
| `01-product-map.md` | Screens, navigation, sheets, how they connect |
| `02-user-flows.md` | Entry, actions, feedback, completion, where people get stuck |
| `03-friction-map.md` | Harmful friction, necessary friction, missing intentional friction |
| `04-findings.md` | Ranked issues with location, problem, change, and result |
| `05-motion.md` | What moves, what should, what should not |
| `06-accessibility.md` | Type, targets, VoiceOver, reduced motion |
| `07-design-system.md` | Tokens, repeated components, terminology |
| `08-priorities.md` | Quick wins, larger work, systemic causes |

## How to use this with ChatGPT

Ask it to treat these files as the product. Ask for implementation plans against the existing SwiftUI, not a new design system. The highest-value changes are in `08-priorities.md`.

Code lives in the OneFeed Xcode project. Paths below are relative to the `OneFeed/` source folder unless noted.
