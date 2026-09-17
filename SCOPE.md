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

- **`docs/DESIGN.md` has not caught up with tool selection.** Its `defaults`
  table is missing `tools` and `reproducible_tools`, and nothing records why an
  unclassified tool counts as writing rather than raising. Cheap now: the
  reasoning is fresh and the table is two rows short. Expensive later: the
  unclassified-means-writing decision reads as an oversight to anyone finding
  it cold, and the obvious "fix" — raising — turns a routine `shards update`
  into a CLI that will not start.

---

## WILL FIX

- **A session can accumulate content the next deployment cannot replay.** The
  first instance was reasoning: continue a turn from a local model onto
  Anthropic and the mapper refuses, because it will not replay thinking it did
  not produce. `reasoning_retention` on the target deployment is the operator's
  answer, and `main.cr` now reports the refusal as an error rather than a stack
  trace — but the operator has to know in advance which pairs need which
  setting, which is not a reasonable thing to expect. Intrinsic to a
  cross-provider session tool, so reasoning will not be the last instance.

- **The sandbox root is the working directory, and nothing can move it.**
  Deliberate for now: the tools are for the project someone is standing in, and
  the specs rely on it — a settable root would let a spec point somewhere
  convenient, which is how `Dir.cd` crept in and broke Wiretap's relative
  transcript path last time. Becomes real the moment someone wants to run
  against a directory they are not in.

- **`Query::CONTINUATION` is overridable through the API but not through
  config.** The default is good enough to use permanently, and a prose
  paragraph is unusable as a CLI flag — which collides with the rule that every
  `defaults` key pairs with a flag of the same name. Needs either a documented
  exception for operator prose, or a second such setting to justify the shape.
  Neither is worth inventing for one string.

- **`Workspace::CAPABILITIES` classifies tools that `fsutils` could classify
  itself.** `Definition` carries a name, a description and a schema, and says
  nothing about whether a tool writes — so every host offering a read-only mode
  hardcodes the same table. That passes the test for belonging in the shard.
  Not raised yet, deliberately: worth knowing what shape this project actually
  needed before asking for it.

- **The `AGAIN` branch of the tool loop is exercised by one transcript and one
  provider.** A model that ignores `tool_choice: None` is answered with
  refusals and the turn stops. Ollama does that today because its
  chat-completions endpoint does not implement the parameter; Gemini does it by
  documented defect. If Ollama ever implements it, that branch loses its only
  cheap coverage and the behaviour would need a Gemini recording to keep.

[liaison]: https://github.com/ModelArmy/liaison.cr
