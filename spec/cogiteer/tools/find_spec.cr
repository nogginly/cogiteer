require "json"
require "../../spec_helper"
require "../../support/tool_harness"

# `find_files`, end to end: offered alone, called over a fixture folder, and
# the listing archived. Recorded once against a local Ollama.
#
# Scoped to `spec/fixtures/notes/`, which holds exactly two files. The walker
# sorts entries and reports root-relative paths, and `reproducible_tools` drops
# each entry's mtime, so the listing is the same on every machine. Sizes stay
# in the result and are fixed only because the fixtures are never edited.
#
# Hidden entries are skipped by default, so a `.DS_Store` beside the fixtures
# does not reach the body unless the model asks for `include_hidden`.
private NOTES = "spec/fixtures/notes"

private EXPECTED_FILES = ["#{NOTES}/alpha.md", "#{NOTES}/beta.txt"]

# The paths of the files one successful result lists.
private def files_in(result : Liaison::MPSH::ToolResultBlock) : Array(String)
  entries = JSON.parse(ToolHarness.text_of(result))["results"]?.try(&.as_a?) || [] of JSON::Any
  entries.select { |entry| entry["type"].as_s == "file" }.map(&.["path"].as_s)
end

describe "the CLI's find_files tool" do
  it "lists the fixture folder and archives the files it found" do
    ToolHarness.with_config(ToolHarness.ollama(50, ["find_files"])) do
      Wiretap.intercept("tools_find_files") do
        Cogiteer::Commands::Start.run(["ollama",
                                       "Use find_files to list every file under #{NOTES}.",
                                       "Pass paths as a list: [\"#{NOTES}\"], and set type to \"file\".",
                                       "Then tell me the file names you found."])
      end

      session = ToolHarness.only_session
      calls = ToolHarness.blocks_of(session, Liaison::MPSH::ToolCallBlock)
      results = ToolHarness.blocks_of(session, Liaison::MPSH::ToolResultBlock)

      calls.should_not be_empty
      calls.map(&.name).uniq.should eq(["find_files"])
      results.size.should eq(calls.size)

      # The tool's own listing, not the model's summary of it. Any successful
      # call that found both is enough; a retry with better arguments is fine.
      found = results.reject(&.is_error?).map { |result| files_in(result) }
      found.any? { |files| files.sort == EXPECTED_FILES }.should be_true

      Liaison::MPSH::Repair.sendable?(session).should be_true
    end
  end
end
