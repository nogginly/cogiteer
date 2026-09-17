require "../../spec_helper"
require "../../support/cli_output"
require "file_utils"
require "json"
require "../../../src/cogiteer/config"
require "../../../src/cogiteer/sessions"
require "../../../src/cogiteer/query"
require "../../../src/cogiteer/commands/start"

# `search_file_contents`, end to end: offered alone, called over a fixture
# folder, and the matches archived. Recorded once against a local Ollama.
#
# The search is scoped to `spec/fixtures/notes/`, whose token sits at known
# lines. The walker sorts entries and reports root-relative paths, so the
# result — and therefore the next request body — is the same on every machine.
private MODEL = "gemma4:26b-mxfp8"

private NOTES = "spec/fixtures/notes"
private TOKEN = "SALSIFY-9002"

private EXPECTED_HITS = [
  {"#{NOTES}/alpha.md", 6},
  {"#{NOTES}/alpha.md", 10},
  {"#{NOTES}/beta.txt", 3},
]

private def with_sandbox(&) : Nil
  tmp = File.join(Dir.tempdir, "cogiteer-search-spec-#{Random.rand(1_000_000)}")
  Dir.mkdir_p(File.join(tmp, ".cogiteer"))
  config_path = File.join(tmp, "cogiteer.yaml")
  File.write(config_path, <<-YAML)
    servers:
      ollama:
        protocol: chat_completions
        url: http://127.0.0.1:11434
    deployments:
      ollama:
        server: ollama
        model: #{MODEL}
    defaults:
      max_tool_calls: 50
      reproducible_tools: true
      tools: [search_file_contents]
    YAML

  original_home = ENV["COGITEER_HOME"]?
  original_config = ENV["COGITEER_CONFIG"]?
  ENV["COGITEER_HOME"] = File.join(tmp, ".cogiteer")
  ENV["COGITEER_CONFIG"] = config_path
  begin
    captured { yield }
  ensure
    original_home ? (ENV["COGITEER_HOME"] = original_home) : ENV.delete("COGITEER_HOME")
    original_config ? (ENV["COGITEER_CONFIG"] = original_config) : ENV.delete("COGITEER_CONFIG")
    FileUtils.rm_rf(tmp)
  end
end

private def only_session : Liaison::MPSH::Session
  ids = Dir.children(Cogiteer::Sessions.folder)
  ids.size.should eq(1)
  Cogiteer::Sessions.latest(ids.first)
end

private def blocks_of(session : Liaison::MPSH::Session, type : T.class) : Array(T) forall T
  session.messages.flat_map { |message| message.content.select(type) }
end

# The `{path, line}` pairs one successful result reports.
private def hits_in(result : Liaison::MPSH::ToolResultBlock) : Array({String, Int32})
  body = result.content.select(Liaison::MPSH::TextBlock).map(&.text).join
  matches = JSON.parse(body)["results"]?.try(&.as_a?) || [] of JSON::Any
  matches.map { |match| {match["path"].as_s, match["line"].as_i} }
end

describe "the CLI's search_file_contents tool" do
  it "searches the fixture folder and archives every matching line" do
    with_sandbox do
      Wiretap.intercept("tools_search_file_contents") do
        Cogiteer::Commands::Start.run(["ollama",
                                       "Use search_file_contents to find every line containing #{TOKEN}.",
                                       "Pass paths as a list: [\"#{NOTES}\"]. Use mode \"lines\".",
                                       "Then tell me which files and line numbers matched."])
      end

      session = only_session
      calls = blocks_of(session, Liaison::MPSH::ToolCallBlock)
      results = blocks_of(session, Liaison::MPSH::ToolResultBlock)

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
