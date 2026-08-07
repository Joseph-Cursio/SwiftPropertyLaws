# SwiftInferProperties — moved

The SwiftInferProperties PRD and source no longer live in this repo. As of 2026-04-30, SwiftInferProperties is an independent Swift package with a one-way dependency on SwiftPropertyLaws.

- **Repo:** [Joseph-Cursio/SwiftInferProperties](https://github.com/Joseph-Cursio/SwiftInferProperties)
- **Local checkout:** `~/xcode_projects/SwiftInferProperties/`
- **Canonical PRD:** `SwiftInferProperties/docs/SwiftInferProperties PRD v1.0.md`, plus `SwiftInferProperties/docs/SwiftInferProperties PRD v2.0.md` for the interaction-invariant surface. (This line named `docs/SwiftInferProperties PRD v0.3.md` until 2026-08-07; the v0.1–v0.4 drafts were retired in that repo's `745b76b`.)
- **Older drafts (v0.1, v0.2):** in this repo's git history, prior to commit `e272ba8` (2026-04-30)

The split was made so SwiftInferProperties can release on its own cadence and pull SwiftPropertyLaws via SPM, preventing accidental upward coupling.
