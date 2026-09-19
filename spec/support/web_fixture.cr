require "http/server"
require "../../src/cogiteer/tools/workspace"

# The suite's own web server, and the seam that lets a turn reach it.
#
# ```
# WebFixture.serving do |base|
#   WebFixture.allowing_private_hosts do
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

  # Opens the protected seam on `Workspace` for the duration of the block.
  #
  # Reopening the module is what makes the protected setter reachable: the
  # call is inside the namespace that declared it, rather than a public
  # setting anything could reach. Restored in an `ensure`, because this is
  # process-wide state and a leak would quietly permit loopback in every
  # example that ran afterwards.
  def self.allowing_private_hosts(&)
    Cogiteer::Tools::Workspace.permit_private_hosts(true)
    begin
      yield
    ensure
      Cogiteer::Tools::Workspace.permit_private_hosts(false)
    end
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

# The suite's half of the seam `Workspace` documents: inside the module, so
# the protected setter is reachable, and nowhere near the shipped API.
module Cogiteer::Tools::Workspace
  def self.permit_private_hosts(value : Bool) : Nil
    self.allow_private_hosts = value
  end
end
