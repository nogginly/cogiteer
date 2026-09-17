# Handoff

For starting a fresh session on this project. Deliberately short: almost
everything worth knowing is already in the repository, and this file points
rather than restates.

## Read in this order

Document                           |Why                                                                                   
-----------------------------------|--------------------------------------------------------------------------------------
`docs/DESIGN.md`                   |Authoritative for this tool: config, session storage, verb grammar, tools, and why    
`SCOPE.md`                         |The worklist. Every open question, each with the trap that makes it awkward           
`README.md`                        |The front door: what the tool is for, and the handoff in ten lines                    
[`liaison`][liaison]'s `HANDOFF.md`|The shard underneath. Its `docs/MPSH_SPECIFICATION.md` is authoritative for the format
[`fsutils`][fsutils]'s `DESIGN.md` |The filesystem toolkit. Authoritative for what the tools do and refuse                

Where this file and `docs/DESIGN.md` disagree, the design document wins. Where
either disagrees with the MPSH specification about the *format*, the
specification wins — this project consumes that format and does not define it.

## State

**Complete and working.** Six verbs — `start`, `continue`, `list`, `show`,
`prune`, `delete` — with streaming, config-file deployments, and one folder per
session on disk. `docs/DESIGN.md` carries the argument for each.

**Tool execution is built.** A turn offers the [`fsutils`][fsutils] filesystem
tools, rooted at the working directory, and runs them in a bounded loop.
`docs/DESIGN.md`'s *Tools* section is the argument; the summary is that the
ceiling counts calls rather than rounds, a round too large is split rather than
refused, and a spent budget ends the turn with `tool_choice: None`.

The whole surface migrated out of `liaison` and depends on it as an ordinary
shard. **Nothing in `liaison` names this project, and nothing should.**
Applications depend on the shard, not the reverse, and there could be many.

`spec/end_to_end/` stayed in `liaison` and did not come across. The consequence
is worth stating plainly: **this repo's specs cover this tool, not the handoff.**
A green run here says the CLI behaves; it does not say the shard's claim holds.

## Transcripts: the thing most likely to catch you out

Specs replay from committed transcripts under `spec/transcripts/`, so the suite
needs no server. **Wiretap replays HTTP. It does not replay tools.** A tool runs
for real on every pass, and its result becomes part of the *next* request's
body, which is what the recording is matched against. Three consequences, all
of them already load-bearing:

1. **`reproducible_tools: true` in every recorded tool spec.** Without it a
   walk's `elapsed_ms` and a find result's `modified` differ on every run and
   the transcript never replays — not even on the machine that recorded it.
2. **`tools: [...]` pinned in every recorded tool spec.** Absent means every
   tool the toolkit offers, so a new `fsutils` tool would change the declared
   tool list, change the body, and re-record everything. Pinning is what stops
   the cost compounding.
3. **Fixtures under `spec/fixtures/` are read by tools and must not be edited.**
   Their contents land in a request body. Each says so at the top.

**Two transcripts are paid.** `anthropic_tools_read_file` and
`anthropic_tools_capped` were recorded against Anthropic Haiku, and exist
because Ollama cannot honour `tool_choice` and so cannot show a turn ending in
prose. Everything else is local Ollama and re-records for the price of time.
**Agree a paid re-record before causing one.** `record_mode` is `:once`
locally, so a missing transcript records itself rather than failing.

Other transcript traps, each of which has already bitten:

- **Anything that changes a request body re-records.** A config default that
  adds a tool declaration did it once; a URL change from `localhost` to
  `127.0.0.1` did it again. When ten specs suddenly say *No recorded
  interaction*, ask what changed in the body before reaching for `RECORD=1`.
- **Tool specs use `127.0.0.1`, not `localhost`.** Crystal's HTTP client takes
  the first resolved address where curl falls back, and macOS resolves
  `localhost` to `::1` first. The older specs still use `localhost`; leave them
  alone or their transcripts move.
- **`normalize_body` is configured although nothing yet needs it.** No
  transcript so far carries a liaison-minted call id — Ollama and Anthropic
  both supply their own. It is not retroactive, so leave it.
- **Sandbox what the code reads, not the process.** Specs use `$COGITEER_HOME`
  and `$COGITEER_CONFIG`, never `Dir.cd`. Moving the working directory takes
  Wiretap's relative transcript path with it.

## Next

**The remaining tools, one at a time.** `read_text_file` is covered end to end;
the other four are offered but only `read_text_file` is exercised by a recorded
spec. In rough order of usefulness: `search_file_contents`, `find_files`, then
`write_text_file` and `text_replace`.

Each is now one spec and one transcript, because the selection mechanism landed
first. Three things to know before writing one:

1. **Scope the prompt to `spec/fixtures/`.** A search over the repository
   returns results that change with every commit, and those results go into a
   request body. `spec/fixtures/notes/` holds two files with a known token at
   known lines, for exactly this.
2. **Bound walks by work, not by clock.** `max_matches`, `max_depth` and
   `max_entries_scanned` truncate identically everywhere; `timeout_seconds`
   does not, and a walk that completes on one machine may not on another.
   `reproducible` cannot fix that and does not claim to.
3. **Argument shapes differ between tools.** `find_files` takes `path` as an
   array of strings where `read_text_file` takes one string. A prompt vague
   about this produces a failed first call.

## How to work on this

**The maintainer holds the toolchain and does all of the running.** Crystal, the
shards, a local Ollama and the credentials live on their machine, and building,
test execution, recording, reviewing and committing are all theirs. An assistant
working here should not install or invoke the toolchain, and should not assume
anything has been compiled or run: write the change, present the files
individually for review, and let the maintainer run it.

- **Nothing an assistant writes has been type-checked.** Say plainly which lines
  rest on a type detail rather than an obvious API, so those get looked at
  first. Two that have already cost a round trip: **`MPSH::Value` must be named
  in full and never re-aliased** — it is recursive, and a local alias expands to
  a union Crystal treats as a different type — and **a variable captured by an
  `OptionParser` block never narrows out of its nilable type**, so copy it into
  a local before testing it. Both are documented at their sites.
- **`shards update` after a dependency changes.** `shard.lock` pins a commit,
  and neither shard is version-constrained. A missing method on a shard type is
  usually a stale lock, not a wrong API.
- **`ops test`** runs specs, builds and lints. Green means all three. Ameba
  rejects `d` and `it` as block parameter names.
- **Transcripts replay offline**, `:none` in CI. `Wiretap.verify!` raises at end
  of suite if anything recorded, which is the signal that a transcript changed
  rather than replayed. `RECORD=1` for runs where recording is the point.

## Working with the shards

Three change requests went to `liaison` and `fsutils` during the tool work and
all three were accepted. The test that made them acceptable is worth keeping:
**would the next host write the same thing?** If yes it belongs in the shard; if
it is only convenient for this application, this application owns it.

Two live examples of the second case. The `MPSH::Object` to
`Hash(String, JSON::Any)` conversion stays in `src/cogiteer/tools/arguments.cr`
because both libraries made the correct local choice and closing the seam would
break one of them. The capability classification in `Workspace::CAPABILITIES`
stays here because `Definition` carries no notion of whether a tool writes —
though that one *would* pass the test, and is worth raising with `fsutils` once
it is clear what shape it wants.

**An unrecognised tool counts as writing, and the forcing function is a spec.**
Raising would turn a routine `shards update` into a CLI that will not start.
`workspace_spec.cr` asserts every definition is classified, so a new tool fails
this project's tests on the update that introduces it.

## Deferred, and staying deferred

Not a REPL, not an agent framework, and not a home for session trees or
scatter-gather. If a sentence-like grammar ever wants those, it is a different,
later tool built on the same shard — not a reason to complicate this one.
`docs/DESIGN.md`'s *What this is, and what it deliberately is not* is the
argument.

Still deferred from the tool work: an operator-settable sandbox root (the root
is the working directory, and specs rely on that), and a config key for the
message a refused call carries (`Query::CONTINUATION`, overridable through the
API only).

[liaison]: https://github.com/ModelArmy/liaison.cr
[tool-execution]: https://github.com/ModelArmy/liaison.cr/blob/main/docs/TOOL_EXECUTION.md
[fsutils]: https://github.com/nogginly/fsutils.cr
