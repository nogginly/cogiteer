require "./cogiteer/config"
require "./cogiteer/sessions"
require "./cogiteer/commands/start"
require "./cogiteer/commands/continue"
require "./cogiteer/commands/list"
require "./cogiteer/commands/show"
require "./cogiteer/commands/delete"
require "./cogiteer/commands/prune"

USAGE = <<-USAGE
  cogiteer — a portable session history

  Usage:
    cogiteer start <deployment> <prompt...> [--id <session-id>]
    cogiteer continue <session-id> <prompt...> [--on <deployment>]
    cogiteer list
    cogiteer show <session-id> [--snapshots] [--json]
    cogiteer prune <session-id> --keep <n>
    cogiteer delete <session-id>

  Deployments and their defaults come from ./cogiteer.yaml or ~/cogiteer.yaml.
  Sessions are stored under ./.cogiteer (if present) or ~/.cogiteer.
  USAGE

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
  when nil, "-h", "--help"
    puts USAGE
  else
    STDERR.puts "unknown command: #{verb}"
    STDERR.puts USAGE
    exit 1
  end
rescue e : Cogiteer::ConfigError | Cogiteer::SessionError | ArgumentError
  STDERR.puts "cogiteer: #{e.message}"
  exit 1
rescue e : Liaison::TransportError
  STDERR.puts "cogiteer: #{e.message}"
  exit 1
end
