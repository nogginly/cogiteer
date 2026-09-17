require "file_utils"
require "./cli_output"
require "../../src/cogiteer/config"
require "../../src/cogiteer/sessions"
require "../../src/cogiteer/query"
require "../../src/cogiteer/commands/start"

# Shared setup for the recorded tool specs: a throwaway config and session
# home, and ways to read back what a run archived.
#
# ```
# ToolHarness.with_config(ToolHarness.ollama(max_tool_calls: 50, tools: ["read_text_file"])) do
#   Wiretap.intercept("tools_read_file") { Cogiteer::Commands::Start.run(argv) }
#   ToolHarness.blocks_of(ToolHarness.only_session, Liaison::MPSH::ToolCallBlock)
# end
# ```
#
# A module rather than top-level defs, so these never collide with the
# file-private `with_sandbox` helpers the command specs keep.
#
# **Anything that reaches a request body re-records.** The model name, the
# server URL and the declared tools all do; the YAML's layout and comments do
# not. Changing `OLLAMA_MODEL` or `OLLAMA_URL` here moves every Ollama
# transcript at once.
module ToolHarness
  OLLAMA_MODEL = "gemma4:26b-mxfp8"

  # `127.0.0.1`, not `localhost`: macOS resolves `localhost` to `::1` first,
  # and Crystal's client does not fall back.
  OLLAMA_URL = "http://127.0.0.1:11434"

  # A config with one Ollama deployment named `ollama`.
  #
  # `tools` is required rather than defaulted. Absent means every tool the
  # toolkit offers, so a new `fsutils` tool would change the declared list and
  # re-record every transcript. `reproducible_tools` is always on, because a
  # tool's result is part of the next request body and an mtime or elapsed
  # time would stop it replaying.
  def self.ollama(max_tool_calls : Int32, tools : Array(String)) : String
    <<-YAML
      servers:
        ollama:
          protocol: chat_completions
          url: #{OLLAMA_URL}
      deployments:
        ollama:
          server: ollama
          model: #{OLLAMA_MODEL}
      defaults:
        max_tool_calls: #{max_tool_calls}
        reproducible_tools: true
        tools: [#{tools.join(", ")}]
      YAML
  end

  # Runs the block with `yaml` as the config and an empty session home,
  # capturing everything the CLI prints, and restores both afterwards.
  #
  # Sandboxes through `$COGITEER_CONFIG` and `$COGITEER_HOME`, never `Dir.cd`:
  # moving the working directory takes Wiretap's relative transcript path, and
  # the tools' sandbox root, with it.
  def self.with_config(yaml : String, &) : Nil
    tmp = File.join(Dir.tempdir, "cogiteer-tool-spec-#{Random.rand(1_000_000)}")
    Dir.mkdir_p(File.join(tmp, ".cogiteer"))
    config_path = File.join(tmp, "cogiteer.yaml")
    File.write(config_path, yaml)

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

  # The one session the run created. Fails the spec if there is not exactly one.
  def self.only_session : Liaison::MPSH::Session
    ids = Dir.children(Cogiteer::Sessions.folder)
    ids.size.should eq(1)
    Cogiteer::Sessions.latest(ids.first)
  end

  # Every block of `type` across the session, in order.
  def self.blocks_of(session : Liaison::MPSH::Session, type : T.class) : Array(T) forall T
    session.messages.flat_map { |message| message.content.select(type) }
  end

  # The concatenated text of a tool result.
  def self.text_of(result : Liaison::MPSH::ToolResultBlock) : String
    result.content.select(Liaison::MPSH::TextBlock).map(&.text).join
  end
end
