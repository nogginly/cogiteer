require "../spec_helper"
require "../support/cli_output"

# What the CLI says about a turn that did not finish, and — as much to the
# point — where it says it. Stdout carries the reply and nothing else, which
# is the guarantee `cogiteer start ... | pbcopy` rests on, so every word here
# belongs on stderr.
describe Cogiteer::Output do
  args = M::Object{"city" => "Kyoto".as(M::Value)}

  cut = ->(ending : M::Ending) do
    reply = M::Message.new(M::Role::Assistant, [
      M::TextBlock.new("Let me look that up.").as(M::Block),
      M::ToolCallBlock.new("mc_cli_weather", "get_weather", args).as(M::Block),
    ])
    reply.ending = ending
    reply
  end

  describe ".warn_cut" do
    it "says nothing at all about a turn that finished" do
      printed, warned = captured { Cogiteer::Output.warn_cut(M::Message.assistant("Kyoto is mild.")) }

      printed.should be_empty
      warned.should be_empty
    end

    it "distinguishes the three ways a turn ends early" do
      {M::Ending::Truncated   => /stopped short/,
       M::Ending::Stopped     => /was stopped/,
       M::Ending::Interrupted => /stream ended/}.each do |ending, expected|
        _, warned = captured { Cogiteer::Output.warn_cut(cut.call(ending)) }
        warned.should match(expected)
      end
    end

    # The discrepancy worth naming out loud: the reply on screen mentions
    # looking something up, and the saved session contains no such call.
    it "counts the tool calls left out of the saved session" do
      _, warned = captured { Cogiteer::Output.warn_cut(cut.call(M::Ending::Interrupted)) }

      warned.should match(/1 unfinished tool call/)
    end

    it "stays quiet about calls when a cut turn made none" do
      reply = M::Message.assistant("The capital of Fra")
      reply.ending = M::Ending::Truncated

      _, warned = captured { Cogiteer::Output.warn_cut(reply) }

      warned.should match(/stopped short/)
      warned.should_not match(/tool/)
    end

    it "keeps all of it off stdout" do
      printed, warned = captured { Cogiteer::Output.warn_cut(cut.call(M::Ending::Truncated)) }

      printed.should be_empty
      warned.should_not be_empty
    end
  end

  describe "streaming" do
    it "prints deltas to stdout with no newlines of its own" do
      printed, warned = captured do
        Cogiteer::Output.text_delta("Kyoto ")
        Cogiteer::Output.text_delta("is mild.")
      end

      printed.should eq("Kyoto is mild.")
      warned.should be_empty
    end

    it "closes the reply so a shell prompt does not land on it" do
      printed, _ = captured do
        Cogiteer::Output.text_delta("Kyoto is mild.")
        Cogiteer::Output.end_stream
      end

      printed.should eq("Kyoto is mild.\n")
    end

    # The guarantee `cogiteer start … > answer.txt` rests on. Streaming was the
    # obvious way to break it and does not.
    it "keeps reasoning entirely off stdout" do
      printed, warned = captured do
        Cogiteer::Output.tune_colour
        Cogiteer::Output.reasoning_open
        Cogiteer::Output.reasoning_delta("Kyoto is in Kansai…")
        Cogiteer::Output.reasoning_close
      end

      printed.should be_empty
      warned.should contain("Kyoto is in Kansai…")
      warned.should contain("thinking")
    end

    # `Colorize.default_enabled?` on a redirected stream is false, so the
    # escapes are absent rather than merely invisible — which is what makes
    # the example above able to assert on plain text at all.
    it "emits no colour escapes when stderr is not a terminal" do
      _, warned = captured do
        Cogiteer::Output.tune_colour
        Cogiteer::Output.reasoning_delta("thinking")
      end

      warned.should_not contain("\e[")
    end
  end

  describe ".repaired_on_load" do
    it "names the session, since it changed what is on disk" do
      printed, warned = captured { Cogiteer::Output.repaired_on_load("brisk-otter") }

      printed.should be_empty
      warned.should match(/brisk-otter/)
    end
  end
end
