require "option_parser"
require "../config"
require "../sessions"
require "../query"
require "../display"
require "../output"
require "../progress"

module Cogiteer::Commands
  module Continue
    extend self

    USAGE = <<-USAGE
      usage: cogiteer continue <session-id> <prompt...> [options]

      Takes another turn in an existing session, on whichever deployment last
      answered. Use 'cogiteer list' to find a session id.

      Options:
        --on DEPLOYMENT                answer on a different deployment
        --stream, --no-stream          show the reply as it arrives, or wait
        --show-reasoning, --hide-reasoning
                                       put the model's thinking on stderr
        --tools a,b                    offer only these tools; empty offers none
        --no-edit                      drop every tool that changes your files
        --web, --no-web                allow, or refuse, tools that reach the web
        --max-tool-calls N             ceiling for this turn; 0 offers no tools
        --reproducible-tools, --no-reproducible-tools
                                       omit when and where a tool call ran
        -h, --help                     show this message

      Example:
        cogiteer continue brisk-comet "And the second?" --on anthropic
      USAGE

    def run(args : Array(String)) : Nil
      on_deployment = nil.as(String?)
      stream_flag = nil.as(Bool?)
      show_reasoning = nil.as(Bool?)
      max_tool_calls = nil.as(Int32?)
      reproducible_tools = nil.as(Bool?)
      tool_names = nil.as(Array(String)?)
      no_edit_tools = false
      web_tools = nil.as(Bool?)
      OptionParser.parse(args) do |parser|
        parser.on("-h", "--help", "show this message") do
          puts USAGE
          exit 0
        end
        parser.invalid_option { |flag| raise ArgumentError.new("#{flag} is not an option here\n\n#{USAGE}") }
        parser.on("--on DEPLOYMENT", "continue on a different deployment than this session last used") do |value|
          on_deployment = value
        end
        parser.on("--stream", "show the reply as it arrives, whatever the config says") { stream_flag = true }
        parser.on("--no-stream", "wait for the whole reply") { stream_flag = false }
        parser.on("--show-reasoning", "put the model's thinking on stderr as it arrives") { show_reasoning = true }
        parser.on("--hide-reasoning", "keep the model's thinking off the terminal") { show_reasoning = false }
        parser.on("--tools NAMES", "offer only these tools, comma-separated; empty offers none") do |value|
          tool_names = value.split(',').map(&.strip).reject(&.empty?)
        end
        parser.on("--no-edit", "drop any tool that changes your files, whatever else was asked for") do
          no_edit_tools = true
        end
        parser.on("--web", "allow tools that reach the web, whatever the config says") { web_tools = true }
        parser.on("--no-web", "refuse tools that reach the web") { web_tools = false }
        parser.on("--reproducible-tools", "omit when and where a tool call ran") { reproducible_tools = true }
        parser.on("--no-reproducible-tools", "report when and where a tool call ran") { reproducible_tools = false }
        parser.on("--max-tool-calls N", "ceiling on tool calls for this turn; 0 offers no tools") do |value|
          max_tool_calls = value.to_i? ||
                           raise ArgumentError.new("--max-tool-calls is #{value.inspect} — expected a whole number")
        end
      end

      session_id, prompt = parse_positional(args)

      config = Config.load
      # Not the config's own default — a session's own history. What "continue"
      # means is "whoever I was already talking to," which the config's
      # default_deployment never actually recorded; see docs/DESIGN.md.
      deployment_name = on_deployment || Sessions.latest_deployment(session_id) ||
                        raise SessionError.new(
                          "session #{session_id.inspect} was saved before deployment tracking existed — " \
                          "specify --on once and every snapshot after that will remember it")
      d = config.deployment(deployment_name)
      provider = config.provider_for(deployment_name)

      # Snapshots written before repair existed can hold a turn cut mid-call,
      # and a session is portable enough to have been written by something
      # else entirely. Repairing on load costs one pass over messages that
      # are already in memory and removes the only shape a request cannot be
      # built from.
      session = Sessions.latest(session_id)
      Output.repaired_on_load(session_id) if Liaison::MPSH::Repair.repair!(session)
      display = Display.resolve(config.defaults, stream_flag, show_reasoning, Output.stream)

      # Copied out of the closured flag before it is tested: OptionParser holds
      # it, so it never narrows out of `Int32?` however it is written.
      requested_calls = max_tool_calls
      tool_calls = requested_calls || config.defaults.max_tool_calls
      requested_reproducible = reproducible_tools
      reproducible = requested_reproducible.nil? ? config.defaults.reproducible_tools? : requested_reproducible
      requested_tools = tool_names
      tools = requested_tools || config.defaults.tools
      requested_web = web_tools
      web = requested_web.nil? ? config.defaults.web? : requested_web

      reply, report = Progress.while_waiting("waiting on #{deployment_name}", Output.error_stream) do |ticker|
        Query.run(provider, d.model, session, prompt,
          reasoning: d.reasoning, retention: d.reasoning_retention,
          display: display, indicator: ticker,
          max_tool_calls: tool_calls, reproducible_tools: reproducible,
          tool_names: tools, no_edit_tools: no_edit_tools, web_tools: web)
      end
      Sessions.snapshot(session_id, session, deployment_name)

      Output.warn_lossy(report)
      Output.warn_cut(reply)
      Output.reply(reply) unless report.streamed?
    end

    private def parse_positional(args : Array(String)) : {String, String}
      session_id = args[0]?
      prompt_words = args[1..]?
      if session_id.nil? || prompt_words.nil? || prompt_words.empty?
        raise ArgumentError.new(USAGE)
      end
      {session_id, prompt_words.join(" ")}
    end
  end
end
