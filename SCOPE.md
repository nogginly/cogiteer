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
  nothing about what a tool touches — so every host offering a restricted mode
  hardcodes the same table. That passes the test for belonging in the shard.
  Now stronger than when it was written: the table has four members rather than
  two, and `fetch_as_markdown` proved a host cannot infer them from a name. We
  know what shape this project needed, so the reason for not raising it has
  expired.

- **The toolkit's own settings are not reachable from `cogiteer.yaml`.**
  `Workspace.toolbox` builds a bare `FsUtils::Tools::Config` and sets one
  field. Every bound the toolkit carries — `find` and `grep` limits, read and
  write sizes, the fetch host lists and timeout, where scratch lives — takes
  its default, so an operator who wants a shallower grep or a run that may read
  one vendor's docs and nothing else has nowhere to say so. `defaults.web`'s
  two states are the visible symptom: `WebAccess` is an enum rather than a
  `Bool` so a third state has somewhere to go, and nothing consumes one.

  **Deferred until fetch integration is released, deliberately.** It is a
  config-surface decision rather than a tool detail, and folding it into the
  fetch work would decide it in passing. The shape it should probably take,
  recorded so the argument does not have to be had twice:

  - A **third top-level table**, sibling to `servers:` and `deployments:` —
    `toolkit:`, not a key under `defaults:`. `defaults` is how the CLI behaves
    and every key there pairs with a flag of the same name; nested per-tool
    bounds cannot pair with a flag and should not force an exception to the
    rule. It also cannot go under `defaults.tools`, which already means *which
    tools to offer* — one key with two meanings depending on whether a list or
    a mapping follows is the shape `docs/DESIGN.md` refuses elsewhere.
  - **Deserialised straight into `FsUtils::Tools::Config`**, which is already
    `YAML::Serializable` with a section per tool. Exposing a curated subset
    under our own key names reads nicer and makes every bound the shard adds or
    renames a change here, plus a translation table between two files that must
    be kept in step.
  - **Ownership line:** `cogiteer` decides whether a tool is offered (`tools`,
    `web`, `--no-edit`, `max_tool_calls`); `fsutils` decides how it behaves
    once offered. Fields this project drives — `reproducible` — are overwritten
    after deserialising, so a flag never loses silently to a file.

  Three traps to handle when it is built. `YAML::Serializable` ignores
  unrecognised keys, so a misspelled bound would parse and do nothing, where
  every parser here raises with the key named. Errors would arrive as
  `YAML::ParseException` about a type rather than a `ConfigError` naming a key
  in `cogiteer.yaml`. And `web: any` stops being literally true once an
  allowlist exists — it would mean *offer the tool, the policy decides where*,
  which either gets documented or gets a better word.

- **Nothing prunes the scratch directory.** A long fetch writes into
  `.agent-scratch/` under the working directory and leaves it there, across
  runs and sessions. Documented in `README.md` as the user's to clean up, which
  is honest rather than good. A `--clean` verb, an age limit, or per-session
  subdirectories would each work; none is obviously right, and inventing a
  retention policy before anyone has complained is how a CLI grows a cache
  nobody asked for.

- **`Workspace` carries a protected seam so the fetch spec can reach its own
  fixture server.** `HostPolicy` refuses loopback unless `allow_private_hosts`
  is set, and this project cannot write `FsUtils::Tools::Config` — so
  `@@allow_private_hosts` and a protected setter exist, reopened by
  `spec/support/web_fixture.cr`. State rather than a parameter because the
  spec drives `Commands::Start.run` and is not the caller of `toolbox`.
  **Delete it when `toolkit:` lands**, and have the spec set the host policy
  the way an operator would; a seam that survives its replacement is how a
  project acquires two ways to do one thing.

- **The fetch transcripts hold a fixed port, and the fixture server binds it.**
  `WebFixture::PORT` is a constant because Wiretap matches on the exact URL
  and the prompt puts the same URL inside the deployment's request body, so a
  found port would replay neither. The server runs only while recording. If
  that port is ever taken on a recording machine, the number changes and both
  fetch transcripts re-record.

[liaison]: https://github.com/ModelArmy/liaison.cr
