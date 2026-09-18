require "../../spec_helper"
require "../../support/tool_harness"

# `text_replace`, end to end: offered alone, called on a scratch copy of a
# fixture, and the edited file checked on disk. Recorded once against a local
# Ollama.
#
# The copy lives at a fixed path named after the transcript, so the prompt,
# the call and the result are the same on every run.
private ID      = "tools_text_replace"
private FIXTURE = "spec/fixtures/editable/draft.md"

private OLD_TEXT = "Status: draft"
private NEW_TEXT = "Status: final"

describe "the CLI's text_replace tool" do
  it "edits a scratch copy and leaves exactly the requested change on disk" do
    original = File.read(FIXTURE)
    original.scan(OLD_TEXT).size.should eq(1)
    expected = original.sub(OLD_TEXT, NEW_TEXT)

    ToolHarness.with_config(ToolHarness.ollama(50, ["text_replace"])) do
      ToolHarness.with_scratch(ID, [FIXTURE]) do |dir|
        target = File.join(dir, File.basename(FIXTURE))

        Wiretap.intercept(ID) do
          Cogiteer::Commands::Start.run(["ollama",
                                         "Use text_replace on #{target}.",
                                         "Set old_string to \"#{OLD_TEXT}\" and new_string to \"#{NEW_TEXT}\".",
                                         "Then tell me whether it worked."])
        end

        session = ToolHarness.only_session
        calls = ToolHarness.blocks_of(session, Liaison::MPSH::ToolCallBlock)
        results = ToolHarness.blocks_of(session, Liaison::MPSH::ToolResultBlock)

        calls.should_not be_empty
        calls.map(&.name).uniq.should eq(["text_replace"])
        results.size.should eq(calls.size)
        results.reject(&.is_error?).should_not be_empty

        # The disk, not the tool's report: proves the arguments reached the
        # file the sandbox root says they name, and that nothing else changed.
        File.read(target).should eq(expected)
        File.read(FIXTURE).should eq(original)

        Liaison::MPSH::Repair.sendable?(session).should be_true
      end
    end
  end
end
