require "json"
require "../../spec_helper"
require "../../support/tool_harness"

# `write_text_file`, end to end, in its two calling patterns. Each example has
# its own transcript and scratch folder, and they share nothing. Recorded once
# each against a local Ollama.
#
# - **Create:** a path whose file and parent folder do not exist yet, so the
#   sandbox resolves a path nothing is at.
# - **Overwrite:** a scratch copy of a fixture, replaced with `overwrite: true`,
#   so a boolean argument has to survive the trip to the tool.
#
# Both contents are one line with no trailing newline: the tool writes exactly
# what it is given, so the bytes on disk are the bytes in the prompt.
private FIXTURE = "spec/fixtures/editable/draft.md"

private CREATE_ID      = "tools_write_text_file_create"
private CREATE_CONTENT = "Created by the write spec."

private OVERWRITE_ID      = "tools_write_text_file_overwrite"
private OVERWRITE_CONTENT = "Replaced by the write spec."

# The `created` flag of every successful result: true for a new file, false
# for a replacement.
private def created_flags(results : Array(Liaison::MPSH::ToolResultBlock)) : Array(Bool)
  results.reject(&.is_error?).compact_map do |result|
    JSON.parse(ToolHarness.text_of(result))["created"]?.try(&.as_bool?)
  end
end

private def tool_run(id : String, prompt : Array(String)) : Array(Liaison::MPSH::ToolResultBlock)
  Wiretap.intercept(id) do
    Cogiteer::Commands::Start.run(["ollama"] + prompt)
  end

  session = ToolHarness.only_session
  calls = ToolHarness.blocks_of(session, Liaison::MPSH::ToolCallBlock)
  results = ToolHarness.blocks_of(session, Liaison::MPSH::ToolResultBlock)

  calls.should_not be_empty
  calls.map(&.name).uniq.should eq(["write_text_file"])
  results.size.should eq(calls.size)
  Liaison::MPSH::Repair.sendable?(session).should be_true
  results
end

describe "the CLI's write_text_file tool" do
  it "creates a file, and its missing parent folder, in scratch" do
    ToolHarness.with_config(ToolHarness.ollama(50, ["write_text_file"])) do
      ToolHarness.with_scratch(CREATE_ID, [] of String) do |dir|
        target = File.join(dir, "new", "created.txt")

        results = tool_run(CREATE_ID, [
          "Use write_text_file to create #{target}.",
          "Set content to exactly \"#{CREATE_CONTENT}\" with no trailing newline.",
          "Then tell me whether it worked.",
        ])

        created_flags(results).should contain(true)
        File.read(target).should eq(CREATE_CONTENT)
      end
    end
  end

  it "replaces an existing scratch copy when overwrite is set" do
    original = File.read(FIXTURE)

    ToolHarness.with_config(ToolHarness.ollama(50, ["write_text_file"])) do
      ToolHarness.with_scratch(OVERWRITE_ID, [FIXTURE]) do |dir|
        target = File.join(dir, File.basename(FIXTURE))

        results = tool_run(OVERWRITE_ID, [
          "Use write_text_file to replace #{target}, which already exists.",
          "Set content to exactly \"#{OVERWRITE_CONTENT}\" with no trailing newline, and set overwrite to true.",
          "Then tell me whether it worked.",
        ])

        # `created: false` is the tool saying it replaced a file, which it
        # refuses to do unless `overwrite` arrived as a boolean true.
        created_flags(results).should contain(false)
        File.read(target).should eq(OVERWRITE_CONTENT)
        File.read(FIXTURE).should eq(original)
      end
    end
  end
end
