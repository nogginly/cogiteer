require "../../spec_helper"
require "../../support/tool_harness"
require "../../../src/cogiteer/commands/continue"

# The same tool flags, through `continue`'s own option parser. It keeps a
# separate copy of every flag, so a flag working on `start` says nothing about
# it here — the split `streaming_spec.cr` already makes for `--stream`.
#
# Each example starts from a turn that offers no tools at all, so every tool
# call in the transcript belongs to the `continue` turn under test. The setup
# request is byte-identical each time, so all three share one transcript, as
# `continue_spec.cr`'s `started` does.
private SETUP_ID = "flags_continue_setup"

private FIXTURE = "spec/fixtures/editable/draft.md"

private OFFERED = ["read_text_file", "write_text_file"]

# Named for the flag as it was when this was recorded; see tool_flags_spec.cr.
private READONLY_ID = "flags_readonly_continue"
private TOOLS_ID    = "flags_tools_continue"
private CAPPED_ID   = "flags_capped_continue"

private def started : String
  Wiretap.intercept(SETUP_ID) do
    Cogiteer::Commands::Start.run(["ollama", "Say hello in one short sentence.", "--tools", ""])
  end
  Dir.children(Cogiteer::Sessions.folder).first
end

describe "cogiteer continue, with tool flags" do
  it "drops the writer the config offered when --no-edit is given" do
    ToolHarness.with_config(ToolHarness.ollama(50, OFFERED)) do
      ToolHarness.with_scratch(READONLY_ID, [FIXTURE]) do |dir|
        id = started
        source = File.join(dir, File.basename(FIXTURE))
        target = File.join(dir, "summary.txt")

        Wiretap.intercept(READONLY_ID) do
          Cogiteer::Commands::Continue.run([id,
                                            "Write the first line of #{source} into #{target}. " \
                                            "If you cannot write, read #{source} and tell me its first line instead.",
                                            "--no-edit"])
        end

        pairs = ToolHarness.exchanges(ToolHarness.latest(id))
        pairs.map { |call, _| call.name }.should contain("read_text_file")
        pairs.each { |call, result| result.is_error?.should be_true if call.name == "write_text_file" }
        File.exists?(target).should be_false
      end
    end
  end

  it "offers only the named tool when --tools narrows the config" do
    ToolHarness.with_config(ToolHarness.ollama(50, OFFERED)) do
      ToolHarness.with_scratch(TOOLS_ID, [FIXTURE]) do |dir|
        id = started
        source = File.join(dir, File.basename(FIXTURE))
        target = File.join(dir, "summary.txt")

        Wiretap.intercept(TOOLS_ID) do
          Cogiteer::Commands::Continue.run([id,
                                            "Write the first line of #{source} into #{target}. " \
                                            "If you cannot write, read #{source} and tell me its first line instead.",
                                            "--tools", "read_text_file"])
        end

        pairs = ToolHarness.exchanges(ToolHarness.latest(id))
        pairs.map { |call, _| call.name }.should contain("read_text_file")
        pairs.each { |call, result| result.is_error?.should be_true if call.name == "write_text_file" }
        File.exists?(target).should be_false
      end
    end
  end

  it "caps the turn at the flag's ceiling, not the config's" do
    ToolHarness.with_config(ToolHarness.ollama(50, OFFERED)) do
      ToolHarness.with_scratch(CAPPED_ID, [FIXTURE]) do |dir|
        id = started
        source = File.join(dir, File.basename(FIXTURE))

        Wiretap.intercept(CAPPED_ID) do
          Cogiteer::Commands::Continue.run([id,
                                            "Read #{source} and then read shard.yml. " \
                                            "Use the tool for both; do not guess.",
                                            "--max-tool-calls", "1"])
        end

        results = ToolHarness.blocks_of(ToolHarness.latest(id), Liaison::MPSH::ToolResultBlock)
        results.reject(&.is_error?).size.should eq(1)
        results.select(&.is_error?).each do |refused|
          ToolHarness.text_of(refused).should eq(Cogiteer::Query::CONTINUATION)
        end
      end
    end
  end

  it "refuses a --max-tool-calls that is not a number, and says so" do
    ToolHarness.with_config(ToolHarness.ollama(50, OFFERED)) do
      id = started

      expect_raises(ArgumentError, /expected a whole number/) do
        Cogiteer::Commands::Continue.run([id, "And again?", "--max-tool-calls", "lots"])
      end
    end
  end
end
