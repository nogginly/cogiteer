require "liaison"
require "./display"
require "./output"
require "./progress"
require "./tools/workspace"

module Cogiteer
  # Both `start` and `continue` are this, differing only in whether `session`
  # arrives empty or loaded from disk. Kept separate from either command so
  # neither has to know the other exists.
  module Query
    extend self

    # What a refused call tells the model.
    #
    # Three things deliberately. That the call did *not* run, since a model
    # reading a failure it cannot distinguish from a tool error will retry it.
    # An instruction rather than a description, which is the form a model acts
    # on — the same reasoning behind `FsUtils`' separate `suggestion` field.
    # And that the work is resumable, because a turn ending in a summary of
    # where things stand is worth more to whoever reads it than an apology.
    CONTINUATION = "The tool call limit for this turn has been reached, so this call was not run. " \
                   "Do not call any more tools. Summarise what you have found so far and say what " \
                   "remains to be done, so the user can continue from there."

    # `reasoning` and `retention` arrive as `nil` unless the deployment said
    # otherwise, and `nil` is passed straight through rather than being
    # replaced with a default here. `Client#send` already falls back to its own
    # settings for `retention`, and an absent `Options#reasoning` emits nothing
    # on any protocol — so a deployment that configures neither produces the
    # same request body it produced before either option existed.
    #
    # `display` decides what the terminal does while the answer arrives;
    # `indicator` is the ticker already up around the call, handed in so the
    # streaming path can take it down on the first delta and put it back up
    # during a tool call.
    #
    # `max_tool_calls` is a ceiling on the whole turn, not on one round. Zero
    # declares no tools at all and reduces this to the single exchange it was
    # before tools existed, which is why it is the default here: a caller that
    # has not been taught about tools does not silently acquire them.
    #
    # The toolbox is built here rather than passed in, because `FsUtils::Tools`
    # fixes its sandbox root at construction and a toolbox that outlived one
    # invocation would carry that root into the next.
    #
    # The returned report is the last exchange's. Every request in a turn
    # raises the same structural annotations plus whatever its longer history
    # adds, so the last one is the most complete rather than merely the newest.
    def run(provider : Liaison::Provider, model : String, session : Liaison::MPSH::Session,
            prompt : String,
            reasoning : Liaison::Reasoning::Request? = nil,
            retention : Liaison::Capability::ReasoningRetention? = nil,
            display : Display = Display.new(false, false),
            indicator : Progress? = nil,
            max_tool_calls : Int32 = 0,
            reproducible_tools : Bool = false,
            continuation : String = CONTINUATION) : {Liaison::MPSH::Message, Liaison::Capability::Report}
      session << Liaison::MPSH::Message.user(prompt)

      client = Liaison::Client.new(provider)
      toolbox = max_tool_calls > 0 ? Tools::Workspace.toolbox(reproducible: reproducible_tools) : nil
      waiting = indicator.try(&.label)
      remaining = max_tool_calls

      loop do
        options = options_for(reasoning, toolbox, remaining)
        reply, report = exchange(client, session, model, retention, options, display, indicator)

        # What is archived is repaired; what is returned is what arrived.
        #
        # The two differ only for a cut turn, and only by its tool calls, but
        # the split is the point. A dangling call in a snapshot is a session
        # that cannot be continued — by this CLI, by another one, on another
        # provider — which is the single property the archive exists to keep.
        # The caller still gets the unrepaired reply, because a person is
        # entitled to see what the model actually said before it was cut.
        #
        # A cut turn that produced nothing but calls repairs to nothing, and
        # nothing is what gets appended. The user prompt stays: it was asked,
        # and the next turn reads better with it there than without.
        repaired = Liaison::MPSH::Repair.repaired(reply)
        session << repaired if repaired

        break {reply, report} unless toolbox && repaired

        # Server-executed calls are not counted and not run: the provider ran
        # them and their results arrived with the reply. Charging a budget for
        # work this process did not do could exhaust it without a single local
        # call.
        calls = repaired.content.select(Liaison::MPSH::ToolCallBlock).reject(&.server_executed?)
        break {reply, report} if calls.empty?

        runnable = calls.first(remaining)
        refused = calls[runnable.size..]

        results = [] of Liaison::MPSH::Block
        unless runnable.empty?
          indicator.try { |ticker| ticker.label = "running #{runnable.size} tool(s)"; ticker.start }
          dispatched = toolbox.dispatch(Liaison::MPSH::Message.new(
            Liaison::MPSH::Role::Assistant, runnable.map(&.as(Liaison::MPSH::Block))))
          dispatched.try { |message| results.concat(message.content) }
          remaining -= runnable.size
        end
        refused.each { |call| results << refusal(call, continuation) }

        session << Liaison::MPSH::Message.new(Liaison::MPSH::Role::User, results)

        # Nothing ran, which means the budget was already spent when this reply
        # arrived — so the model was asked not to call and called anyway. One
        # protocol does that; see liaison's `docs/protocols/GEMINI.md`. Every
        # call has a result, so the session is sendable and resumable; there is
        # simply nobody left to ask for a closing word.
        break {reply, report} if runnable.empty?

        indicator.try { |ticker| ticker.label = waiting || ticker.label }
      end
    end

    # `tool_choice` is asked for only once the budget is spent, and only while
    # tools are declared — `Options` refuses a choice with nothing to choose
    # from. Three of the four protocols then honour it and the turn ends in
    # prose; the fourth is handled where the loop stops.
    private def options_for(reasoning : Liaison::Reasoning::Request?,
                            toolbox : Liaison::Toolbox?,
                            remaining : Int32) : Liaison::Options
      return Liaison::Options.new(reasoning: reasoning) unless toolbox

      Liaison::Options.new(
        tools: toolbox.tools,
        reasoning: reasoning,
        tool_choice: remaining.zero? ? Liaison::ToolChoice::None : nil)
    end

    private def exchange(client : Liaison::Client, session : Liaison::MPSH::Session, model : String,
                         retention : Liaison::Capability::ReasoningRetention?,
                         options : Liaison::Options,
                         display : Display,
                         indicator : Progress?) : {Liaison::MPSH::Message, Liaison::Capability::Report}
      return stream(client, session, model, retention, options, display, indicator) if display.streaming?

      client.send(session, model, retention: retention, options: options)
    end

    # Dispatched through `Toolbox` for the calls that fit; built here for the
    # ones that do not.
    #
    # `Toolbox#dispatch` runs every call in the message it is handed and keeps
    # `run` private, so a partial round cannot go through it — hence the
    # synthetic assistant message above holding only the runnable calls, and
    # hence this pairing a `call_id` by hand for the rest. `is_error` is set
    # because the call genuinely did not happen: an unflagged result would tell
    # the model it succeeded while its text said otherwise.
    private def refusal(call : Liaison::MPSH::ToolCallBlock, continuation : String) : Liaison::MPSH::Block
      Liaison::MPSH::ToolResultBlock.new(
        call.call_id,
        [Liaison::MPSH::TextBlock.new(continuation).as(Liaison::MPSH::Block)],
        is_error: true).as(Liaison::MPSH::Block)
    end

    # The streamed turn.
    #
    # ## What the block may not do
    #
    # This block is called from inside `Server#stream`, which means it is
    # inside a captured proc, which means the `yield` **keyword** is illegal
    # anywhere it reaches — see `server.cr` on why `exec` is called directly.
    # Nothing here yields. Blocking on IO or on a channel is a different thing
    # entirely and is fine; `Progress#stop` waits on one.
    #
    # ## Why annotations are watched and not shown
    #
    # `AnnotationRaised` arrives at the head of the stream, before any content,
    # because every annotation exists before the request leaves. The same
    # annotations are in `report`, which both verbs already print through
    # `warn_lossy` after the reply. Showing them twice, or showing them here
    # and not there, would make a streamed run and an unstreamed one disagree
    # about a session's stderr for no gain.
    private def stream(client : Liaison::Client, session : Liaison::MPSH::Session, model : String,
                       retention : Liaison::Capability::ReasoningRetention?,
                       options : Liaison::Options,
                       display : Display,
                       indicator : Progress?) : {Liaison::MPSH::Message, Liaison::Capability::Report}
      Output.tune_colour

      printed = false
      thinking = false

      reply, report = client.send(session, model, retention: retention, options: options) do |event, _turn|
        case event
        in Liaison::Streaming::TextDelta
          indicator.try(&.stop)
          if thinking
            Output.reasoning_close
            thinking = false
          end
          printed = true
          Output.text_delta(event.text)
        in Liaison::Streaming::ReasoningDelta
          if display.show_reasoning?
            indicator.try(&.stop)
            unless thinking
              Output.reasoning_open
              thinking = true
            end
            Output.reasoning_delta(event.text)
          end
        in Liaison::Streaming::ToolCallStarted
          # The pause about to happen is a tool call, not a stall. The label is
          # the whole reason `Progress` made it settable.
          if thinking
            Output.reasoning_close
            thinking = false
          end
          indicator.try do |ticker|
            ticker.label = "calling #{event.name}"
            ticker.start
          end
        in Liaison::Streaming::AnnotationRaised
          # Reported once, after the reply, by `warn_lossy`.
        in Liaison::Streaming::ProviderDelta
          # Namespaced vendor detail with no canonical meaning to render.
        end
      end

      Output.reasoning_close if thinking
      Output.end_stream if printed

      {reply, report}
    end
  end
end
