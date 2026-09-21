require "http/server"

# The suite's own web server, and the config that lets a turn reach it.
#
# ```
# WebFixture.serving do |base|
#   ToolHarness.with_config(ToolHarness.ollama(50, TOOLS, WebFixture::TOOLKIT)) do
#     Wiretap.intercept(ID) { Cogiteer::Commands::Start.run([..., "#{base}/small"]) }
#   end
# end
# ```
module WebFixture
  # **Fixed, not found.** `fsutils` binds an unused port for its own fetch
  # specs, which is right for a suite that records nothing. Here the port
  # reaches a request body twice — Wiretap matches interactions on the exact
  # URL string, and the prompt naming the page puts the port inside the
  # deployment's body as well — so a port that changed per run would replay
  # neither.
  #
  # High and unlikely to be taken. If it is, recording fails with the bind
  # error rather than anything subtle, and this constant is the thing to
  # change — followed by re-recording, since the number is in the transcript.
  PORT = 47_231

  BASE = "http://127.0.0.1:#{PORT}"

  # `HostPolicy` refuses loopback unless told otherwise, so a recorded fetch
  # spec cannot reach this server without saying so. Written as config rather
  # than reached through a seam in the source: this is exactly what an
  # operator pointing the tool at a local service would put in their own
  # `cogiteer.yaml`, and a spec that takes a different route tests a path
  # nobody else can take.
  TOOLKIT = <<-YAML
    toolkit:
      fetch:
        allow_private_hosts: true
    YAML

  # Runs the block with the server up, and only when recording.
  #
  # On replay Wiretap answers the fetch from disk, so nothing binds a port and
  # a machine already using it is not a failing suite. That also means the
  # pages below are only ever consulted at record time: change one and the
  # transcript, not the server, is what a replay still believes.
  def self.serving(&)
    return yield BASE unless recording?

    server = HTTP::Server.new { |context| respond(context) }
    server.bind_tcp("127.0.0.1", PORT)
    spawn { server.listen }
    Fiber.yield

    begin
      yield BASE
    ensure
      server.close
    end
  end

  def self.recording? : Bool
    Wiretap.config.record_mode == :once
  end

  # Runs the block with the server up, and only when recording.
  #
  # On replay Wiretap answers the fetch from disk, so nothing binds a port and
  # a machine already using it is not a failing suite. That also means the
  # pages below are only ever consulted at record time: change one and the
  # transcript, not the server, is what a replay still believes.
  def self.serving(&)
    return yield BASE unless recording?

    server = HTTP::Server.new { |context| respond(context) }
    server.bind_tcp("127.0.0.1", PORT)
    spawn { server.listen }
    Fiber.yield

    begin
      yield BASE
    ensure
      server.close
    end
  end

  def self.recording? : Bool
    Wiretap.config.record_mode == :once
  end

  private def self.respond(context : HTTP::Server::Context) : Nil
    response = context.response
    response.content_type = "text/html"

    case context.request.path
    when "/small"
      response.print "<html><head><title>Kettle</title></head><body><main>" \
                     "<h1>Kettle</h1><p>The kettle boils at one hundred degrees.</p>" \
                     "</main></body></html>"
    else
      response.status_code = 404
      response.print "<html><body>gone</body></html>"
    end
  end
end
