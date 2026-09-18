require "../../spec_helper"
require "../../support/tool_harness"

# The tool flags, through a verb's own option parser rather than through
# config. Each verb parses its own copy, so each is covered separately, as
# `streaming_spec.cr` does for `--stream`.
#
# `--readonly` first, because it is the flag whose whole purpose is to deny
# something the config allows: the config here offers a writer, the flag drops
# it, and the turn must be unable to write. The reader stays offered and is
# still called, so a failure here is the flag misfiring rather than tools
# being off altogether.
private ID        = "flags_readonly_start"
private TOOLS_ID  = "flags_tools_start"
private NONE_ID   = "flags_no_tools_start"
private CAPPED_ID = "flags_capped_start"
private FIXTURE   = "spec/fixtures/editable/draft.md"

private OFFERED = ["read_text_file", "write_text_file"]

# Every flag here is tested against a config that says something *different*,
# so a pass cannot come from the config already agreeing with the flag.

describe "cogiteer start --readonly" do
  it "drops the writer the config offered, leaving the reader" do
    ToolHarness.with_config(ToolHarness.ollama(50, OFFERED)) do
      ToolHarness.with_scratch(ID, [FIXTURE]) do |dir|
        source = File.join(dir, File.basename(FIXTURE))
        target = File.join(dir, "summary.txt")

        Wiretap.intercept(ID) do
          Cogiteer::Commands::Start.run(["ollama",
                                         "Write the first line of #{source} into #{target}.",
                                         "If you cannot write, read #{source} and tell me its first line instead.",
                                         "--readonly"])
        end

        session = ToolHarness.only_session
        pairs = ToolHarness.exchanges(session)

        # What the model *attempted* is not the subject. A model that emits
        # calls as text can name a tool it was never offered, and this one
        # does: it reads, tries to write, is refused, and answers in prose.
        # What `--readonly` promises is that such a call cannot succeed.
        pairs.map { |call, _| call.name }.should contain("read_text_file")
        pairs.each { |call, result| result.is_error?.should be_true if call.name == "write_text_file" }
        File.exists?(target).should be_false

        Liaison::MPSH::Repair.sendable?(session).should be_true
      end
    end
  end

  # The flag narrows a config that offers more, the mirror of `--readonly`
  # arriving at the same place by a different route.
  it "offers only the named tool when --tools narrows the config" do
    ToolHarness.with_config(ToolHarness.ollama(50, OFFERED)) do
      ToolHarness.with_scratch(TOOLS_ID, [FIXTURE]) do |dir|
        source = File.join(dir, File.basename(FIXTURE))
        target = File.join(dir, "summary.txt")

        Wiretap.intercept(TOOLS_ID) do
          Cogiteer::Commands::Start.run(["ollama",
                                         "Write the first line of #{source} into #{target}.",
                                         "If you cannot write, read #{source} and tell me its first line instead.",
                                         "--tools", "read_text_file"])
        end

        pairs = ToolHarness.exchanges(ToolHarness.only_session)

        pairs.map { |call, _| call.name }.should contain("read_text_file")
        pairs.each { |call, result| result.is_error?.should be_true if call.name == "write_text_file" }
        File.exists?(target).should be_false
      end
    end
  end

  # An empty list is a thing an operator can mean, and the parser has to keep
  # meaning it: `"".split(',')` yields one empty string, which the flag drops.
  it "offers nothing when --tools is empty" do
    ToolHarness.with_config(ToolHarness.ollama(50, OFFERED)) do
      ToolHarness.with_scratch(NONE_ID, [FIXTURE]) do |dir|
        source = File.join(dir, File.basename(FIXTURE))

        Wiretap.intercept(NONE_ID) do
          Cogiteer::Commands::Start.run(["ollama",
                                         "Read #{source} and tell me its first line.",
                                         "--tools", ""])
        end

        session = ToolHarness.only_session
        ToolHarness.blocks_of(session, Liaison::MPSH::ToolCallBlock).should be_empty
        Liaison::MPSH::Repair.sendable?(session).should be_true
      end
    end
  end

  # The config allows fifty; the flag allows one. Whether the model asks for
  # both files in one round or two is its own business — what must hold is
  # that one call ran and the rest came back as the refusal.
  it "caps the turn at the flag's ceiling, not the config's" do
    ToolHarness.with_config(ToolHarness.ollama(50, OFFERED)) do
      ToolHarness.with_scratch(CAPPED_ID, [FIXTURE]) do |dir|
        source = File.join(dir, File.basename(FIXTURE))

        Wiretap.intercept(CAPPED_ID) do
          Cogiteer::Commands::Start.run(["ollama",
                                         "Read #{source} and then read shard.yml.",
                                         "Use the tool for both; do not guess.",
                                         "--max-tool-calls", "1"])
        end

        session = ToolHarness.only_session
        results = ToolHarness.blocks_of(session, Liaison::MPSH::ToolResultBlock)

        results.reject(&.is_error?).size.should eq(1)
        results.select(&.is_error?).each do |refused|
          ToolHarness.text_of(refused).should eq(Cogiteer::Query::CONTINUATION)
        end
      end
    end
  end

  # Parsing only: this raises before a request is built, so there is nothing
  # to record and nothing to replay.
  it "refuses a --max-tool-calls that is not a number, and says so" do
    expect_raises(ArgumentError, /expected a whole number/) do
      Cogiteer::Commands::Start.run(["ollama", "hello", "--max-tool-calls", "lots"])
    end
  end
end
