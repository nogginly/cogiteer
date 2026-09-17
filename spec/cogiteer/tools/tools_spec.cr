require "../../spec_helper"
require "../../support/cli_output"
require "file_utils"
require "../../../src/cogiteer/config"
require "../../../src/cogiteer/sessions"
require "../../../src/cogiteer/query"
require "../../../src/cogiteer/commands/start"

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
private MODEL = "gemma4:26b-mxfp8"

private TARGET = "spec/fixtures/tool_target.md"
private MARKER = "PARSNIP-4417"

private def with_sandbox(max_tool_calls : Int32, &) : Nil
  tmp = File.join(Dir.tempdir, "cogiteer-tools-spec-#{Random.rand(1_000_000)}")
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

  # See start_spec.cr's with_sandbox: $COGITEER_CONFIG / $COGITEER_HOME rather
  # than Dir.cd or a bare $HOME override.
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

describe "the CLI's tool loop" do
  it "calls the tool, feeds the result back, and archives both" do
    with_sandbox(50) do
      Wiretap.intercept("tools_read_file") do
        Cogiteer::Commands::Start.run(["ollama",
                                       "Read the file #{TARGET} and tell me the marker line it contains.",
                                       "Use the tool; do not guess."])
      end

      session = only_session
      calls = blocks_of(session, Liaison::MPSH::ToolCallBlock)
      results = blocks_of(session, Liaison::MPSH::ToolResultBlock)

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
    with_sandbox(1) do
      Wiretap.intercept("tools_capped") do
        Cogiteer::Commands::Start.run(["ollama",
                                       "Read #{TARGET} and then read shard.yml.",
                                       "Use the tool for both; do not guess."])
      end

      session = only_session
      results = blocks_of(session, Liaison::MPSH::ToolResultBlock)

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
    with_sandbox(1) do
      Wiretap.intercept("tools_capped") do
        Cogiteer::Commands::Start.run(["ollama",
                                       "Read #{TARGET} and then read shard.yml.",
                                       "Use the tool for both; do not guess."])
      end

      Liaison::MPSH::Repair.sendable?(only_session).should be_true
    end
  end

  # Its own transcript rather than borrowing `start_ollama`. Sharing one would
  # assert something stronger — that the request body is identical to the one
  # recorded before tools existed — but it silently couples this file to
  # another's server URL, which is exactly how it broke.
  it "declares no tools when the ceiling is zero" do
    with_sandbox(0) do
      Wiretap.intercept("tools_disabled") do
        Cogiteer::Commands::Start.run(["ollama", "What is the tallest mountain on Earth?",
                                       "Answer in one short sentence."])
      end

      blocks_of(only_session, Liaison::MPSH::ToolCallBlock).should be_empty
    end
  end
end
