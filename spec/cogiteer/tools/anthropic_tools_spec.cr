require "../../spec_helper"
require "../../support/tool_harness"

# The one paid recording in this suite, and the reason it exists is a thing a
# local Ollama cannot show.
#
# ## What Ollama cannot cover
#
# Ollama's chat-completions endpoint does not implement `tool_choice` — the
# capped Ollama run carries `"tool_choice":"none"` and comes back holding a
# call regardless. That exercises the loop's terminal branch, which is
# valuable, but it leaves the *other* ending untested: a server that honours
# the choice, ends the turn in prose, and lets the loop stop the intended way.
#
# It also leaves this project's adapter untested against a real provider's
# tool wire shape, and against a provider that puts reasoning in the same
# reply as tool calls.
#
# ## The cost, stated once
#
# Every other transcript here replays free and re-records for the price of a
# local model's time. This one costs money to re-cut, so a change to the
# request body is a decision rather than a keystroke. Kept deliberately small
# for that reason: one short prompt, one small file, one budget.
#
# Wiretap scrubs `X-Api-Key` by default, so the recorded request carries no
# credential — worth re-checking if the header set ever changes.
private MODEL = "claude-haiku-4-5"

private TARGET = "spec/fixtures/tool_target.md"
private MARKER = "PARSNIP-4417"

# `reasoning_retention` is not decoration. This provider refuses to replay
# reasoning it did not produce, and a tool loop sends the same history back
# on every round — so a turn carrying thinking blocks would be refused on
# the second request rather than the first.
private def haiku(max_tool_calls : Int32) : String
  <<-YAML
    servers:
      anthropic:
        protocol: anthropic
        url: https://api.anthropic.com
        credential_env: ANTHROPIC_API_KEY
    deployments:
      haiku:
        server: anthropic
        model: #{MODEL}
        reasoning_retention: completed_turns
    defaults:
      max_tool_calls: #{max_tool_calls}
      # A tool result becomes part of the next request's body, and that body is
      # what the transcript is matched against. Anything reporting when or
      # where a call ran would differ on every run and the recording would
      # never replay.
      reproducible_tools: true
      # Pinned, not inherited. Left to the built-in, every tool added to the
      # toolkit would change the declared tool list, change the request body,
      # and re-record every transcript here — including the paid ones.
      tools: [read_text_file]
    YAML
end

describe "the CLI's tool loop, on a provider that honours tool_choice" do
  it "runs the tool and archives a usable result" do
    ToolHarness.with_config(haiku(50)) do
      Wiretap.intercept("anthropic_tools_read_file") do
        Cogiteer::Commands::Start.run(["haiku",
                                       "Read #{TARGET} and tell me the marker line it contains.",
                                       "Use the tool; do not guess."])
      end

      session = ToolHarness.only_session
      calls = ToolHarness.blocks_of(session, Liaison::MPSH::ToolCallBlock)
      results = ToolHarness.blocks_of(session, Liaison::MPSH::ToolResultBlock)

      calls.should_not be_empty
      calls.first.name.should eq("read_text_file")
      results.size.should eq(calls.size)

      results.reject(&.is_error?).first.content.select(Liaison::MPSH::TextBlock)
        .map(&.text).join.should contain(MARKER)
    end
  end

  # The ending Ollama cannot produce. With the budget spent, the next request
  # carries `tool_choice: None`; a provider that honours it replies in prose,
  # and the loop stops because there is nothing to dispatch rather than
  # because there was nothing left to spend.
  it "ends in prose once the budget is spent" do
    ToolHarness.with_config(haiku(1)) do
      Wiretap.intercept("anthropic_tools_capped") do
        Cogiteer::Commands::Start.run(["haiku",
                                       "Read #{TARGET} and then read shard.yml.",
                                       "Use the tool for both; do not guess."])
      end

      session = ToolHarness.only_session
      results = ToolHarness.blocks_of(session, Liaison::MPSH::ToolResultBlock)

      # Exactly one call ran, whether the model asked for both at once or one
      # at a time. Anything else it asked for was refused.
      results.reject(&.is_error?).size.should eq(1)
      results.select(&.is_error?).each do |refused|
        refused.content.select(Liaison::MPSH::TextBlock)
          .map(&.text).join.should eq(Cogiteer::Query::CONTINUATION)
      end

      # The turn closed with something to read, rather than on a refusal.
      session.messages.last.role.should eq(Liaison::MPSH::Role::Assistant)
      session.messages.last.content.select(Liaison::MPSH::TextBlock).should_not be_empty

      Liaison::MPSH::Repair.sendable?(session).should be_true
    end
  end
end
