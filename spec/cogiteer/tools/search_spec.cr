require "json"
require "../../spec_helper"
require "../../support/tool_harness"

# `search_file_contents`, end to end: offered alone, called over a fixture
# folder, and the matches archived. Recorded once against a local Ollama.
#
# The search is scoped to `spec/fixtures/notes/`, whose token sits at known
# lines. The walker sorts entries and reports root-relative paths, so the
# result — and therefore the next request body — is the same on every machine.
private NOTES = "spec/fixtures/notes"
private TOKEN = "SALSIFY-9002"

private EXPECTED_HITS = [
  {"#{NOTES}/alpha.md", 6},
  {"#{NOTES}/alpha.md", 10},
  {"#{NOTES}/beta.txt", 3},
]

# The `{path, line}` pairs one successful result reports.
private def hits_in(result : Liaison::MPSH::ToolResultBlock) : Array({String, Int32})
  matches = JSON.parse(ToolHarness.text_of(result))["results"]?.try(&.as_a?) || [] of JSON::Any
  matches.map { |match| {match["path"].as_s, match["line"].as_i} }
end

describe "the CLI's search_file_contents tool" do
  it "searches the fixture folder and archives every matching line" do
    ToolHarness.with_config(ToolHarness.ollama(50, ["search_file_contents"])) do
      Wiretap.intercept("tools_search_file_contents") do
        Cogiteer::Commands::Start.run(["ollama",
                                       "Use search_file_contents to find every line containing #{TOKEN}.",
                                       "Pass paths as a list: [\"#{NOTES}\"]. Use mode \"lines\".",
                                       "Then tell me which files and line numbers matched."])
      end

      session = ToolHarness.only_session
      calls = ToolHarness.blocks_of(session, Liaison::MPSH::ToolCallBlock)
      results = ToolHarness.blocks_of(session, Liaison::MPSH::ToolResultBlock)

      calls.should_not be_empty
      calls.map(&.name).uniq.should eq(["search_file_contents"])
      results.size.should eq(calls.size)

      # The tool's own report, not the model's summary of it. Any successful
      # call that found all three is enough; a model may retry with better
      # arguments, and that is its business.
      found = results.reject(&.is_error?).map { |result| hits_in(result) }
      found.any? { |hits| hits.sort == EXPECTED_HITS.sort }.should be_true

      Liaison::MPSH::Repair.sendable?(session).should be_true
    end
  end
end
