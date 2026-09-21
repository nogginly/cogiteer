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

Nothing currently.

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

- **The workspace root is the working directory, and nothing can move it.**
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

- **Nothing prunes the scratch directory.** A long fetch writes into
  `.agent-scratch/` under the working directory and leaves it there, across
  runs and sessions. Documented in `README.md` as the user's to clean up, which
  is honest rather than good. A `--clean` verb, an age limit, or per-session
  subdirectories would each work; none is obviously right, and inventing a
  retention policy before anyone has complained is how a CLI grows a cache
  nobody asked for.

- **The fetch transcripts hold a fixed port, and the fixture server binds it.**
  `WebFixture::PORT` is a constant because Wiretap matches on the exact URL
  and the prompt puts the same URL inside the deployment's request body, so a
  found port would replay neither. The server runs only while recording. If
  that port is ever taken on a recording machine, the number changes and both
  fetch transcripts re-record.

[liaison]: https://github.com/ModelArmy/liaison.cr
