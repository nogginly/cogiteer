require "../../spec_helper"
require "../../support/cli_output"
require "file_utils"
require "../../../src/cogiteer/sessions"
require "../../../src/cogiteer/commands/delete"
require "../../../src/cogiteer/commands/prune"

# `delete` and `prune` touch no network, like `list` and `show`: they act on
# what `start`/`continue` already wrote. No Wiretap, nothing recorded.
#
# Sandboxed with `$COGITEER_HOME` rather than `Dir.cd`, for the reason
# `start_spec.cr` records at length.
private def with_sandbox(&) : Nil
  tmp = File.join(Dir.tempdir, "cogiteer-remove-spec-#{Random.rand(1_000_000)}")
  Dir.mkdir_p(File.join(tmp, ".cogiteer"))

  original_home = ENV["COGITEER_HOME"]?
  ENV["COGITEER_HOME"] = File.join(tmp, ".cogiteer")
  begin
    yield
  ensure
    original_home ? (ENV["COGITEER_HOME"] = original_home) : ENV.delete("COGITEER_HOME")
    FileUtils.rm_rf(tmp)
  end
end

private def seed(id : String, deployment : String) : Nil
  session = M::Session.new
  session << M::Message.user("a question")
  session << M::Message.assistant("a reply")
  Cogiteer::Sessions.snapshot(id, session, deployment)
end

describe Cogiteer::Commands::Delete do
  it "removes the session and says what it cost" do
    with_sandbox do
      seed("brisk-comet", "ollama")
      seed("brisk-comet", "ollama")

      _, warned = captured { Cogiteer::Commands::Delete.run(["brisk-comet"]) }

      Cogiteer::Sessions.exists?("brisk-comet").should be_false
      warned.should contain("brisk-comet")
      warned.should contain("2 snapshots")
    end
  end

  it "leaves every other session alone" do
    with_sandbox do
      seed("brisk-comet", "ollama")
      seed("keen-otter", "ollama")

      captured { Cogiteer::Commands::Delete.run(["brisk-comet"]) }

      Cogiteer::Sessions.list.should eq(["keen-otter"])
    end
  end

  # The likeliest reason to reach for this verb. `list` renders a session it
  # cannot parse as `<unreadable>`, and a delete that insisted on reading what
  # it was about to remove would fail exactly when it was most wanted.
  it "removes a session whose snapshots will not parse" do
    with_sandbox do
      seed("brisk-comet", "ollama")
      File.write(File.join(Cogiteer::Sessions.path_for("brisk-comet"), "9999999999999-ollama.json"), "{ not json")

      captured { Cogiteer::Commands::Delete.run(["brisk-comet"]) }

      Cogiteer::Sessions.exists?("brisk-comet").should be_false
    end
  end

  it "reports a session that was never there" do
    with_sandbox do
      expect_raises(Cogiteer::SessionError, /no session named/) do
        Cogiteer::Commands::Delete.run(["no-such-thing"])
      end
    end
  end

  # `path_for` validates before anything becomes a path, so the traversal
  # question was settled before this verb existed. Pinned here anyway: `delete`
  # is the verb where a gap in that guard would be worst, and a spec is how a
  # future refactor learns that it mattered.
  it "refuses an id that tries to leave the sessions folder" do
    with_sandbox do
      expect_raises(Cogiteer::SessionError) do
        Cogiteer::Commands::Delete.run(["../../etc"])
      end
    end
  end

  it "wants exactly one session id" do
    with_sandbox do
      expect_raises(ArgumentError, /usage/) { Cogiteer::Commands::Delete.run([] of String) }
      expect_raises(ArgumentError, /usage/) { Cogiteer::Commands::Delete.run(["one", "two"]) }
    end
  end
end

describe Cogiteer::Commands::Prune do
  it "keeps the newest snapshots and removes the rest" do
    with_sandbox do
      seed("brisk-comet", "first")
      seed("brisk-comet", "second")
      seed("brisk-comet", "third")

      _, warned = captured { Cogiteer::Commands::Prune.run(["brisk-comet", "--keep", "2"]) }

      remaining = Cogiteer::Sessions.snapshots("brisk-comet")
      remaining.size.should eq(2)
      remaining.none?(&.includes?("first")).should be_true
      warned.should contain("Pruned 1")
      warned.should contain("2 kept")
    end
  end

  # The session survives pruning as a working session, which is the whole
  # difference between this verb and `delete`.
  it "leaves the session continuable" do
    with_sandbox do
      seed("brisk-comet", "ollama")
      seed("brisk-comet", "ollama-responses")

      captured { Cogiteer::Commands::Prune.run(["brisk-comet", "--keep", "1"]) }

      Cogiteer::Sessions.latest_deployment("brisk-comet").should eq("ollama-responses")
      Cogiteer::Sessions.latest("brisk-comet").messages.size.should eq(2)
    end
  end

  it "says so plainly when there is nothing to remove" do
    with_sandbox do
      seed("brisk-comet", "ollama")

      _, warned = captured { Cogiteer::Commands::Prune.run(["brisk-comet", "--keep", "5"]) }

      Cogiteer::Sessions.snapshots("brisk-comet").size.should eq(1)
      warned.should contain("Nothing to prune")
    end
  end

  # No default, deliberately: every value is a judgement about how much
  # history is worth keeping, and guessing one on the person's behalf is how an
  # irreversible verb becomes a surprising one.
  it "refuses to guess how much to keep" do
    with_sandbox do
      seed("brisk-comet", "ollama")

      expect_raises(ArgumentError, /usage/) { Cogiteer::Commands::Prune.run(["brisk-comet"]) }
      Cogiteer::Sessions.snapshots("brisk-comet").size.should eq(1)
    end
  end

  # A session with no snapshots is indistinguishable from a corrupt one, and
  # `delete` is the verb for meaning that.
  it "refuses to leave a session with nothing in it" do
    with_sandbox do
      seed("brisk-comet", "ollama")

      expect_raises(Cogiteer::SessionError, /fewer than one/) do
        Cogiteer::Commands::Prune.run(["brisk-comet", "--keep", "0"])
      end
      Cogiteer::Sessions.snapshots("brisk-comet").size.should eq(1)
    end
  end

  it "wants a number" do
    with_sandbox do
      seed("brisk-comet", "ollama")

      expect_raises(ArgumentError, /whole number/) do
        Cogiteer::Commands::Prune.run(["brisk-comet", "--keep", "some"])
      end
    end
  end

  it "reports a session that was never there" do
    with_sandbox do
      expect_raises(Cogiteer::SessionError, /no session named/) do
        Cogiteer::Commands::Prune.run(["no-such-thing", "--keep", "1"])
      end
    end
  end
end
