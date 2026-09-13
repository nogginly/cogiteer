# cogiteer

A command-line cross-LLM session orchestrator. Start a conversation with one
provider, continue it with another, and keep the whole thing on disk in a
format neither provider owns.

> **WARNING**: This tool is a work in progress and in development until this warning is removed.

> See [DISCLOSURE](./DISCLOSURE.md) for information how AI is used by this project.

## The point

Every vendor stores a conversation in its own shape, so moving one between them
loses something — usually quietly. [`liaison`][liaison], the shard this tool is
built on, keeps the conversation in a canonical portable form and translates at
the edges, reporting what each handoff cost rather than pretending it was free.

`cogiteer` is that made usable from a terminal: one invocation, one call to a
provider, one saved result. Sessions live in files, so the conversation outlives
the process that started it and can be picked up on a different deployment
tomorrow.

## Verbs

```
cogiteer start <deployment> <prompt...> [--id <session-id>] [--stream|--no-stream]
                                        [--show-reasoning|--hide-reasoning]
cogiteer continue <session-id> <prompt...> [--on <deployment>] [--stream|--no-stream]
                                           [--show-reasoning|--hide-reasoning]
cogiteer list
cogiteer show <session-id> [--snapshots] [--json]
cogiteer prune <session-id> --keep <n>
cogiteer delete <session-id>
```

```console
$ cogiteer start ollama "Name three things Vienna is known for."
Session: brisk-comet
Vienna is known for its coffee houses, its classical music, and the Ringstrasse.

$ cogiteer continue brisk-comet "Recommend one coffee house." --on anthropic
Café Sperl, for the billiard tables and the lack of hurry.
```

The second command is the whole pitch: a different vendor, a different wire
protocol, the same conversation. `continue` works out which deployment last
answered by reading it off the session itself, so `--on` is only needed when you
want to switch.

The reply is the only thing on stdout. Session ids, warnings and reasoning all
go to stderr, so `cogiteer start ... > answer.txt` gets an answer and nothing
else.

## Configuration

Deployments are named in `cogiteer.yaml`, found via `$COGITEER_CONFIG`, then
`$CWD`, then `$HOME`. Two tables and a block: a **server** is a url plus the
protocol it speaks, a **deployment** names one model on one server, and
**`defaults`** is how the CLI itself behaves.

```yaml
servers:
  ollama:
    url: http://localhost:11434/v1
    protocol: chat_completions
  anthropic:
    url: https://api.anthropic.com/v1
    protocol: anthropic
    credential_env: ANTHROPIC_API_KEY

deployments:
  ollama:
    server: ollama
    model: qwen3:8b
  anthropic:
    server: anthropic
    model: claude-sonnet-4-5

defaults:
  streaming: false
  show_reasoning: false
```

Sessions are stored under `$COGITEER_HOME`, else `./.cogiteer` if it exists,
else `~/.cogiteer` — one folder per session, one snapshot per turn.

See [docs/DESIGN.md](./docs/DESIGN.md) for the full format, the verb grammar,
and why each is shaped the way it is.

## Installation

```console
$ shards install
$ shards build --release
```

Puts `cogiteer` in `bin/`. Requires Crystal 1.19 or newer.

## Documentation

Document                          |Holds                                          
----------------------------------|-----------------------------------------------
[docs/DESIGN.md](./docs/DESIGN.md)|Config, session storage, verb grammar, and why 
[SCOPE.md](./SCOPE.md)            |The worklist: open questions, and their traps  
[HANDOFF.md](./HANDOFF.md)        |Where things stand and what is next            
[`liaison`][liaison]              |The shard underneath: protocols, MPSH, handoffs

## Contributions, by invitation!

*With apologies*, at this time contributions to this project are *by invitation only* and limited to people I know and see often.

- These are early days for the project and I am busy with family and work.
- At this time I want to work on this at a manageable pace.

## License

MPL-2.0. See [LICENSE](./LICENSE).

[liaison]: https://github.com/ModelArmy/liaison.cr
