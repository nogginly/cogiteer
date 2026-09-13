# Scope

Outstanding work, tracked in two buckets. **Completed items are deleted, not
ticked** — this file is a worklist, not a changelog. It should grow through the
early phases and dissolve as the design settles.

- **MUST FIX** — blocks progress, or is cheap now and expensive later.
- **WILL FIX** — real, but deliberately not now.

Anything settled belongs in code comments or `docs/DESIGN.md`; anything
outstanding belongs here, because nobody greps a codebase for open questions.

Questions about the shard underneath belong in [`liaison`][liaison]'s own
`SCOPE.md`, not here. The test is who would have to change: if the answer is a
mapper, an exporter or the archive format, it is not this file's.

---

## MUST FIX

Empty.

---

## WILL FIX

Empty. The one open question this project inherited — whether the executable
declares tools at all, and what it would run — is the subject of *Next* in
`HANDOFF.md` rather than an entry here, because it is the work in front rather
than work deferred behind it. It moves here if it gets put down again.

[liaison]: https://github.com/ModelArmy/liaison.cr
