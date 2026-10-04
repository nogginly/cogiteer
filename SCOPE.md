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

- **An unreadable reply ends the run with a stack trace, and says nothing of
  what the tools already did.** `liaison` raises
  `Protocol::MalformedResponseError` for a reply it cannot read, and since the
  lock moved to `2d1a471` that includes tool-call arguments that are not a JSON
  object, which a local model can produce. `main.cr` catches neither that nor
  `Protocol::StreamError`. Nothing is saved, because the snapshot is written
  only after `Query.run` returns. The completed rounds are not the loss — the
  session up to them is sendable, since the bad reply never became a message.
  The loss is the record of what they did: a `text_replace` that ran is still
  on disk, and a retried prompt meets its own earlier edit with no history to
  explain it. Decided: catch both, exit 1, and report how many calls ran and
  whether any changed workspace files. The trap is where the count lives: inside
  `Query.run`'s loop, which the exception leaves, so it has to travel with the
  error rather than be reconstructed in `main.cr`, which knows nothing of the
  turn. Whether a call changed files is its `Definition`'s `WorkspaceWrite`
  capability, not a guess from its name. Saving the partial session instead is
  the fuller answer, and changes what a snapshot may end on; not now.

- **Only `toolkit:` refuses a key it does not recognise.** Every other parser in
  `config.cr` reads the keys it knows and ignores the rest: the top level,
  `defaults`, each server and deployment entry, and a server's `azure` block. A
  misspelled `streamng:` parses and does nothing, and so does a misspelled
  `toolkt:` — which means the strictness `toolkit:` gained does not survive a
  typo in its own name. Cheap now because the hand-written parsers already know
  their keys and only need to check the remainder; each message should name the
  key, where it sat, and what was expected, as `toolkit:`'s do. The argument for
  refusing at all is in `DESIGN.md` under *Unknown keys raise here*, and applies
  with less force to a flag than to a bound — but a config that means one thing
  and reads as another is the same fault in either table.

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

- **On a server that ignores `tool_choice: None`, a capped turn ends without a
  summary.** Ollama answers `None` with another call, so a capped local turn
  ends on refused calls rather than prose (`DESIGN.md`, *Two endings*). Dropping
  the tools from the final request would likely force prose, and Anthropic no
  longer rules it out: `liaison` recorded Haiku accepting tool history with no
  tools declared. Two things stand in the way. The price is the prefix cache on
  the longest request of the turn. And nobody knows whether Ollama still turns a
  call written as text into a structured one when no tools are declared — the
  local model already names tools it was never offered. Only a recording
  answers that, and changing the final request re-records every capped
  transcript, the paid `anthropic_tools_capped` included if it applies on every
  protocol. Applying it only where the choice is ignored needs that fact to live
  somewhere, on the server entry or in `liaison`'s catalog.

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

- **Nothing tells an operator what the offered tools do to their machine.**
  `--no-edit` and `--web` are the controls, and learning which tools each one
  moves means reading `DESIGN.md` or running a turn. The answer is now free —
  each `Definition` declares its capabilities, so a listing cannot drift the way
  a hand-kept table would. Most likely a flag on `show` or a small verb printing
  each offered tool against what it touches, run against a deployment's config
  so it answers "what does this profile let a model do". A convenience, not a
  gap: nothing is wrong without it.

[liaison]: https://github.com/ModelArmy/liaison.cr
