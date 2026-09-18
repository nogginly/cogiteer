require "./cogiteer/config"
require "./cogiteer/sessions"
require "./cogiteer/commands/start"
require "./cogiteer/commands/continue"
require "./cogiteer/commands/list"
require "./cogiteer/commands/show"
require "./cogiteer/commands/delete"
require "./cogiteer/commands/prune"

USAGE = <<-USAGE
  cogiteer — one conversation, any number of providers

  Usage:
    cogiteer start <deployment> <prompt...>      begin a session and take a turn
    cogiteer continue <session-id> <prompt...>   take another turn in one
    cogiteer list                                every session, newest first
    cogiteer show <session-id>                   print the conversation
    cogiteer prune <session-id> --keep <n>       drop all but the newest snapshots
    cogiteer delete <session-id>                 remove a session
    cogiteer help [<verb>]                       this message, or a verb's own

  Common options for start and continue:
    --stream, --no-stream            show the reply as it arrives, or wait
    --show-reasoning, --hide-reasoning
                                     put the model's thinking on stderr
    --tools a,b                      offer only these tools; empty offers none
    --readonly                       drop every tool that writes
    --max-tool-calls N               ceiling for this turn; 0 offers no tools

  A turn can read and edit files under the directory you run it from. 'cogiteer
  help start' lists every option; README.md explains the tools.

  Deployments and their defaults come from ./cogiteer.yaml or ~/cogiteer.yaml.
  Sessions are stored under ./.cogiteer (if present) or ~/.cogiteer.

  The reply is the only thing on stdout, so it redirects cleanly.
  USAGE

VERB_USAGE = {
  "start"    => Cogiteer::Commands::Start::USAGE,
  "continue" => Cogiteer::Commands::Continue::USAGE,
  "list"     => Cogiteer::Commands::List::USAGE,
  "show"     => Cogiteer::Commands::Show::USAGE,
  "prune"    => Cogiteer::Commands::Prune::USAGE,
  "delete"   => Cogiteer::Commands::Delete::USAGE,
}

verb = ARGV[0]?
rest = ARGV[1..]? || [] of String

begin
  case verb
  when "start"
    Cogiteer::Commands::Start.run(rest)
  when "continue"
    Cogiteer::Commands::Continue.run(rest)
  when "list"
    Cogiteer::Commands::List.run(rest)
  when "show"
    Cogiteer::Commands::Show.run(rest)
  when "prune"
    Cogiteer::Commands::Prune.run(rest)
  when "delete"
    Cogiteer::Commands::Delete.run(rest)
  when "help", nil, "-h", "--help"
    asked = rest[0]?
    if asked.nil?
      puts USAGE
    elsif text = VERB_USAGE[asked]?
      puts text
    else
      STDERR.puts "cogiteer: no such command: #{asked}"
      STDERR.puts USAGE
      exit 1
    end
  else
    STDERR.puts "cogiteer: no such command: #{verb}"
    STDERR.puts "cogiteer: try 'cogiteer help' for the list"
    exit 1
  end
rescue e : Cogiteer::ConfigError | Cogiteer::SessionError | ArgumentError
  STDERR.puts "cogiteer: #{e.message}"
  exit 1
rescue e : Liaison::TransportError
  STDERR.puts "cogiteer: #{e.message}"
  exit 1
rescue e : Liaison::Capability::RefusedError
  # Carrying a session onto a provider that cannot replay part of it. Usually
  # reasoning: one model's thinking cannot be replayed as another's, and the
  # policy refuses rather than discarding it silently. Operator-fixable, so it
  # exits like any other configuration problem instead of arriving as a stack
  # trace.
  STDERR.puts "cogiteer: #{e.message}"
  STDERR.puts "cogiteer: this session holds content the target cannot replay — " \
              "set 'reasoning_retention: completed_turns' on that deployment to drop it"
  exit 1
end
