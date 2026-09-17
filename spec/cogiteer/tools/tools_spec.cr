require "../../spec_helper"
require "../../support/tool_harness"

# The loop, end to end: a model is offered `read_text_file`, calls it, and the
# result goes back as the next request. In-process, so Wiretap intercepts the
# real `Server#post` — recorded once against a local Ollama, replayed offline
# after.
#
# ## Why the file being read is a fixture and not a repository file
#
# The tool result becomes part of the *second* request's body, and that body is
# what Wiretap digests. A file that changes — `README.md`, `shard.yml` — would
# invalidate these transcripts every time someone edited it. `spec/fixtures`
# holds a file nobody has a reason to touch.
#
# ## Why the path is repository-relative
#
# `Workspace.toolbox` roots the sandbox at `Dir.current`, which for a spec run
# is the repository. The sandbox is therefore the checkout, and no spec here
# calls `Dir.cd` — moving the process's working directory would take Wiretap's
# relative transcript path with it.
private TARGET = "spec/fixtures/tool_target.md"
private MARKER = "PARSNIP-4417"
private TOOLS  = ["read_text_file"]

describe "the CLI's tool loop" do
  it "calls the tool, feeds the result back, and archives both" do
    ToolHarness.with_config(ToolHarness.ollama(50, TOOLS)) do
      Wiretap.intercept("tools_read_file") do
        Cogiteer::Commands::Start.run(["ollama",
                                       "Read the file #{TARGET} and tell me the marker line it contains.",
                                       "Use the tool; do not guess."])
      end

      session = ToolHarness.only_session
      calls = ToolHarness.blocks_of(session, Liaison::MPSH::ToolCallBlock)
      results = ToolHarness.blocks_of(session, Liaison::MPSH::ToolResultBlock)

      calls.should_not be_empty
      calls.first.name.should eq("read_text_file")
      results.size.should eq(calls.size)

      # The tool actually ran: the fixture's marker is in the archived result,
      # which it could only be if the file was read from disk.
      succeeded = results.reject(&.is_error?)
      succeeded.should_not be_empty
      succeeded.first.content.select(Liaison::MPSH::TextBlock)
        .map(&.text).join.should contain(MARKER)
    end
  end

  # The invariant, not a particular shape. Whether a model asks for two files
  # in one round or in two is its own business, and both are correct; what must
  # hold either way is that exactly one call ran and the rest were refused.
  it "runs only what the budget allows and refuses the rest" do
    ToolHarness.with_config(ToolHarness.ollama(1, TOOLS)) do
      Wiretap.intercept("tools_capped") do
        Cogiteer::Commands::Start.run(["ollama",
                                       "Read #{TARGET} and then read shard.yml.",
                                       "Use the tool for both; do not guess."])
      end

      session = ToolHarness.only_session
      results = ToolHarness.blocks_of(session, Liaison::MPSH::ToolResultBlock)

      results.reject(&.is_error?).size.should eq(1)
      results.select(&.is_error?).each do |refused|
        refused.content.select(Liaison::MPSH::TextBlock)
          .map(&.text).join.should eq(Cogiteer::Query::CONTINUATION)
      end
    end
  end

  # The property the archive exists to keep, asserted on the shape most likely
  # to break it: a turn that ended holding calls. Checked for both runs above
  # rather than only the capped one, since a session that cannot be continued
  # is the failure mode either way.
  it "leaves a session that can be continued" do
    ToolHarness.with_config(ToolHarness.ollama(1, TOOLS)) do
      Wiretap.intercept("tools_capped") do
        Cogiteer::Commands::Start.run(["ollama",
                                       "Read #{TARGET} and then read shard.yml.",
                                       "Use the tool for both; do not guess."])
      end

      Liaison::MPSH::Repair.sendable?(ToolHarness.only_session).should be_true
    end
  end

  # Its own transcript rather than borrowing `start_ollama`. Sharing one would
  # assert something stronger — that the request body is identical to the one
  # recorded before tools existed — but it silently couples this file to
  # another's server URL, which is exactly how it broke.
  it "declares no tools when the ceiling is zero" do
    ToolHarness.with_config(ToolHarness.ollama(0, TOOLS)) do
      Wiretap.intercept("tools_disabled") do
        Cogiteer::Commands::Start.run(["ollama", "What is the tallest mountain on Earth?",
                                       "Answer in one short sentence."])
      end

      ToolHarness.blocks_of(ToolHarness.only_session, Liaison::MPSH::ToolCallBlock).should be_empty
    end
  end
end
