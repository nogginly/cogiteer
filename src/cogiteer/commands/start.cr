require "option_parser"
require "../config"
require "../sessions"
require "../query"
require "../display"
require "../output"
require "../progress"

module Cogiteer::Commands
  module Start
    extend self

    USAGE = "usage: cogiteer start <deployment> <prompt...> [--id <session-id>] " \
            "[--stream|--no-stream] [--show-reasoning|--hide-reasoning] " \
            "[--max-tool-calls N] " \
            "[--reproducible-tools|--no-reproducible-tools] " \
            "[--tools a,b] [--readonly]"

    def run(args : Array(String)) : Nil
      chosen_id = nil.as(String?)
      stream_flag = nil.as(Bool?)
      show_reasoning = nil.as(Bool?)
      max_tool_calls = nil.as(Int32?)
      reproducible_tools = nil.as(Bool?)
      tool_names = nil.as(Array(String)?)
      readonly_tools = false
      OptionParser.parse(args) do |parser|
        parser.on("--id SESSION_ID", "name this session instead of taking a generated name") do |value|
          chosen_id = value
        end
        parser.on("--stream", "show the reply as it arrives, whatever the config says") { stream_flag = true }
        parser.on("--no-stream", "wait for the whole reply") { stream_flag = false }
        parser.on("--show-reasoning", "put the model's thinking on stderr as it arrives") { show_reasoning = true }
        parser.on("--hide-reasoning", "keep the model's thinking off the terminal") { show_reasoning = false }
        parser.on("--tools NAMES", "offer only these tools, comma-separated; empty offers none") do |value|
          tool_names = value.split(',').map(&.strip).reject(&.empty?)
        end
        parser.on("--readonly", "drop any tool that writes, whatever else was asked for") { readonly_tools = true }
        parser.on("--reproducible-tools", "omit when and where a tool call ran") { reproducible_tools = true }
        parser.on("--no-reproducible-tools", "report when and where a tool call ran") { reproducible_tools = false }
        parser.on("--max-tool-calls N", "ceiling on tool calls for this turn; 0 offers no tools") do |value|
          max_tool_calls = value.to_i? ||
                           raise ArgumentError.new("--max-tool-calls is #{value.inspect} — expected a whole number")
        end
      end

      deployment_name, prompt = parse(args)

      config = Config.load
      d = config.deployment(deployment_name)
      provider = config.provider_for(deployment_name)

      # Checked *before* the request, not after. A refusal is only useful if
      # it arrives before the money is spent and the reply is stranded with
      # nowhere to be written.
      #
      # Copied out of `chosen_id` first: that one is closured by the
      # OptionParser block above, so the compiler will not narrow it out of
      # `String?` however it is tested.
      requested = chosen_id
      id = requested ? claim(requested) : Sessions.generate_id

      display = Display.resolve(config.defaults, stream_flag, show_reasoning, Output.stream)

      # Copied out of the closured flag before it is tested, for the reason
      # `requested` above gives: OptionParser holds it, so it never narrows
      # out of `Int32?` however it is written.
      requested_calls = max_tool_calls
      tool_calls = requested_calls || config.defaults.max_tool_calls
      requested_reproducible = reproducible_tools
      reproducible = requested_reproducible.nil? ? config.defaults.reproducible_tools? : requested_reproducible
      requested_tools = tool_names
      tools = requested_tools || config.defaults.tools

      session = Liaison::MPSH::Session.new
      reply, report = Progress.while_waiting("waiting on #{deployment_name}", Output.error_stream) do |ticker|
        Query.run(provider, d.model, session, prompt,
          reasoning: d.reasoning, retention: d.reasoning_retention,
          display: display, indicator: ticker,
          max_tool_calls: tool_calls, reproducible_tools: reproducible,
          tool_names: tools, readonly_tools: readonly_tools)
      end

      Sessions.snapshot(id, session, deployment_name)

      Output.session_id(id)
      Output.warn_lossy(report)
      Output.warn_cut(reply)

      # `report.streamed` rather than `display.streaming?`, because a protocol
      # that cannot stream falls back to one body and prints nothing on the
      # way. The report knows which of those happened; the request did not.
      Output.reply(reply) unless report.streamed?
    end

    # `--id` is for someone driving `cogiteer` from a script, who wants the
    # session named after whatever they already call this piece of work rather
    # than having to capture a generated name. Also the honest answer for
    # anyone creating sessions in bulk, where the two-word generator's supply
    # eventually matters and a meaningful name was always better anyway.
    #
    # Refuses an id already in use rather than continuing that session.
    # `start` means start, and silently appending to an existing conversation
    # because a script reused a name is the kind of surprise that costs
    # someone a day. `continue` is right there, and says what it does.
    private def claim(id : String) : String
      Sessions.validate_id(id)
      if Sessions.exists?(id)
        raise SessionError.new(
          "session #{id.inspect} already exists — use 'cogiteer continue #{id} ...' to add to it, " \
          "or pick another --id")
      end
      id
    end

    private def parse(args : Array(String)) : {String, String}
      deployment_name = args[0]?
      prompt_words = args[1..]?
      if deployment_name.nil? || prompt_words.nil? || prompt_words.empty?
        raise ArgumentError.new(USAGE)
      end
      {deployment_name, prompt_words.join(" ")}
    end
  end
end
