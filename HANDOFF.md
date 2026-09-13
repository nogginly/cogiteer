# Handoff

For starting a fresh session on this project. Deliberately short: almost
everything worth knowing is already in the repository, and this file points
rather than restates.

## Read in this order

Document                           |Why                                                                                   
-----------------------------------|--------------------------------------------------------------------------------------
`docs/DESIGN.md`                   |Authoritative for this tool: config, session storage, verb grammar, and why           
`SCOPE.md`                         |The worklist. Every open question, each with the trap that makes it awkward           
`README.md`                        |The front door: what the tool is for, and the handoff in ten lines                    
[`liaison`][liaison]'s `HANDOFF.md`|The shard underneath. Its `docs/MPSH_SPECIFICATION.md` is authoritative for the format

Where this file and `docs/DESIGN.md` disagree, the design document wins. Where
either disagrees with the MPSH specification about the *format*, the
specification wins — this project consumes that format and does not define it.

## State

**Complete and working.** Six verbs — `start`, `continue`, `list`, `show`,
`prune`, `delete` — with streaming, config-file deployments, and one folder per
session on disk. `docs/DESIGN.md` carries the argument for each.

The whole surface migrated out of `liaison` and now depends on it as an ordinary
shard. The migration was a rename and a `require` change with no logic touched,
because `liaison_cli/` had been a *sibling* of `liaison/` rather than nested
inside it — a boundary enforced by the filesystem rather than by agreement. What
that means going forward: **nothing in `liaison` names this project, and nothing
should.** Applications depend on the shard, not the reverse, and there could be
many of them.

What did not come across is `spec/end_to_end/`, which stayed in `liaison`. Those
specs were that shard's only full-stack coverage — a session written to a disk
and picked back up, which is the product claim — and they are the shard's to
keep whether or not this tool exists. The consequence is worth stating plainly:
**this repo's specs cover this tool, not the handoff.** A green run here says the
CLI behaves; it does not say the shard's claim holds.

Ten spec files replay from six committed transcripts under
`spec/transcripts/`, so the suite needs no server and costs nothing. `ops test`
runs specs, builds the executable, and lints.

One thing in `spec/spec_helper.cr` is deliberate and easy to undo by mistake:
`normalize_body` is configured although **no transcript currently needs it** —
this tool is text-only, so none carries a minted call identifier. It is there
because it is not retroactive. Wiretap freezes `body_digest` at record time, so
adding it *after* tool execution records its first transcripts would invalidate
them and cost a re-record. Leave it.

## Next

**Tool execution, backed by a sandboxed filesystem toolkit.** This is why the
CLI left `liaison`: the toolkit is a runtime dependency, and that shard
deliberately has none. So the dependency is welcome here, and this is the first
decision the project owns outright.

The library half is done and needs no work: `Liaison::Function` is a declaration
plus its handler, `Liaison::Toolbox` holds them and dispatches, and
`Toolbox#dispatch` repairs its own argument before reading it. See [`liaison`'s
`docs/TOOL_EXECUTION.md`][tool-execution] and its `examples/tool_loop.cr`, which
is the caller-owned turn loop this project will need a version of.

**The open question is whether the executable declares tools at all, and what it
would run.** `docs/DESIGN.md`'s *Deliberately deferred, not forgotten* leans
text-only-first, and carries the argument that matters most before anything is
built:

> **Declaring and executing are one decision, not two.** `Repair.needed?`
> requires `ending.cut?`, so a turn that *completes* holding a tool call is
> untouched, and nothing in `Client` or this CLI enforces `Repair.sendable?` —
> it appears only in specs. A CLI that declares tools without dispatching them
> therefore writes exactly the unsendable session the archive exists to prevent,
> and nothing notices until the next `continue` is rejected by a protocol strict
> enough to care. There is no safe half-step.

Two things are already settled and should not be reopened as part of this:

- **What the terminal prints while a call is in flight.** `docs/DESIGN.md`'s
  *Printed bytes precede repair* settles it, and it is the rule that finally
  gets something to bite on here. Today `Output.reply` prints text blocks only,
  so a streamed run and its saved session agree exactly and nobody looking for
  the discrepancy will find it. It arrives the moment the terminal starts
  narrating calls as they materialise.
- **Where the ordering rule is enforced.** `Toolbox#dispatch` reads the repaired
  reply, so it holds whatever this project decides.

A third thing is *not* settled and is the real design work: what a sandboxed
filesystem toolkit is allowed to touch, who says so, and how that is expressed
in `cogiteer.yaml`. Nothing above helps with it.

## How to work on this

- **`ops test`** runs specs, builds, and lints. Green means all three.
- **Transcripts are committed and replay offline.** `record_mode` is `:once`
  locally, so a missing transcript records itself rather than failing; `:none`
  in CI, so a missing one fails the build instead of reaching for the network.
  `Wiretap.verify!` raises at end of suite if anything recorded, which is the
  signal that a transcript changed rather than replayed. Set `RECORD=1` for runs
  where recording is the point.
- **Recordings are against local Ollama**, so re-recording costs nothing but
  time. That stops being true if a paid deployment is ever recorded against.
- **Sandbox what the code reads, not the process.** Specs use `$COGITEER_HOME`
  and `$COGITEER_CONFIG` rather than `Dir.cd`. Two specs once moved the
  process's CWD to sandbox config resolution and silently broke Wiretap's
  relative transcript path, which then re-recorded rather than replayed.

## Deferred, and staying deferred

Not a REPL, not an agent framework, and not a home for session trees or
scatter-gather. If a sentence-like grammar ever wants those, it is a different,
later tool built on the same shard — not a reason to complicate this one.
`docs/DESIGN.md`'s *What this is, and what it deliberately is not* is the
argument.

[liaison]: https://github.com/ModelArmy/liaison.cr
[tool-execution]: https://github.com/ModelArmy/liaison.cr/blob/main/docs/TOOL_EXECUTION.md
