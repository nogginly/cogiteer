require "../../spec_helper"
require "../../support/tool_harness"
require "../../support/web_fixture"

# `fetch_as_markdown`, end to end: a model is offered the tool, calls it, and
# the converted page comes back as the next request.
#
# ## Why this one has a server behind it
#
# Every other tool reads the checkout. This one reads the network, so the
# suite supplies the network: `WebFixture` serves one page from `127.0.0.1` on
# a fixed port, and only while recording. Wiretap intercepts
# `HTTP::Client#exec` globally, so the fetch is recorded into this transcript
# alongside the deployment's own exchanges and replays from disk like anything
# else — the server is a record-time detail, not a runtime dependency.
#
# ## Why the marker is in the page and not in the prose
#
# The model's answer is its own business. What proves the tool ran is the
# marker turning up in the *archived tool result*, which it could only do by
# way of a fetch, a conversion, and the adapter handing the result back.
private TOOLS  = ["fetch_as_markdown"]
private MARKER = "one hundred degrees"

describe "the CLI's web fetch" do
  it "fetches a page, converts it, and archives the result" do
    ToolHarness.with_config(ToolHarness.ollama(50, TOOLS)) do
      WebFixture.serving do |base|
        WebFixture.allowing_private_hosts do
          Wiretap.intercept("tools_fetch_markdown") do
            Cogiteer::Commands::Start.run(["ollama",
                                           "Fetch #{base}/small and tell me what temperature it names.",
                                           "Use the tool; do not guess.",
                                           "--web"])
          end
        end

        session = ToolHarness.only_session
        calls = ToolHarness.blocks_of(session, Liaison::MPSH::ToolCallBlock)
        results = ToolHarness.blocks_of(session, Liaison::MPSH::ToolResultBlock)

        calls.should_not be_empty
        calls.first.name.should eq("fetch_as_markdown")
        results.size.should eq(calls.size)

        succeeded = results.reject(&.is_error?)
        succeeded.should_not be_empty
        succeeded.first.content.select(Liaison::MPSH::TextBlock)
          .map(&.text).join.should contain(MARKER)
      end
    end
  end

  # The gate, through the same path a user takes. `--no-web` is not merely a
  # narrower offer: the tool is absent, so a model that names it anyway is
  # refused by the toolbox rather than served.
  #
  # Recorded separately because the declared tool list differs, which is a
  # different request body.
  it "offers nothing to fetch with when --no-web is given" do
    ToolHarness.with_config(ToolHarness.ollama(50, TOOLS)) do
      WebFixture.serving do |base|
        WebFixture.allowing_private_hosts do
          Wiretap.intercept("tools_fetch_refused") do
            Cogiteer::Commands::Start.run(["ollama",
                                           "Fetch #{base}/small and tell me what temperature it names.",
                                           "If you cannot fetch, say so plainly.",
                                           "--no-web"])
          end
        end

        session = ToolHarness.only_session
        results = ToolHarness.blocks_of(session, Liaison::MPSH::ToolResultBlock)

        # What the model attempted is not the subject; that no fetch succeeded
        # is. A model emitting calls as text can name a tool it never had.
        results.each(&.is_error?.should be_true)
        Liaison::MPSH::Repair.sendable?(session).should be_true
      end
    end
  end
end
