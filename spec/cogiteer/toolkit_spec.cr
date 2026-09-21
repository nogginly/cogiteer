require "../spec_helper"
require "../../src/cogiteer/config"
require "../../src/cogiteer/tools/offering"

private BASE = <<-YAML
  servers:
    local:
      protocol: chat_completions
      url: http://127.0.0.1:11434
  deployments:
    local:
      server: local
      model: qwen3

  YAML

describe Cogiteer::Toolkit do
  it "leaves the toolkit's own defaults standing when the table is absent" do
    toolkit = Cogiteer::Config.from_yaml(BASE).toolkit
    toolkit.grep.max_depth.should eq FsUtils::Tools::Config::Grep.new.max_depth
  end

  it "reads a bound into the section it belongs to" do
    toolkit = Cogiteer::Config.from_yaml(BASE + "toolkit:\n  grep:\n    max_depth: 8\n").toolkit
    toolkit.grep.max_depth.should eq 8
  end

  # A document naming one bound leaves the rest standing, which is the shard's
  # promise and worth asserting here because an operator relies on it every
  # time they write a two-line table.
  it "leaves the rest of a section standing" do
    toolkit = Cogiteer::Config.from_yaml(BASE + "toolkit:\n  grep:\n    max_depth: 8\n").toolkit
    toolkit.grep.max_matches.should eq FsUtils::Tools::Config::Grep.new.max_matches
  end

  it "reads a top-level bound that is not a section" do
    toolkit = Cogiteer::Config.from_yaml(BASE + "toolkit:\n  max_output_bytes: 4096\n").toolkit
    toolkit.max_output_bytes.should eq 4096
  end

  it "reads the fetch host lists" do
    toolkit = Cogiteer::Config.from_yaml(
      BASE + "toolkit:\n  fetch:\n    allowed_hosts: [\"docs.crystal-lang.org\"]\n").toolkit
    toolkit.fetch.allowed_hosts.should eq ["docs.crystal-lang.org"]
  end

  # The reason this module exists rather than a bare `from_yaml`. A misspelled
  # bound would otherwise parse and do nothing, and unlike a misspelled flag
  # there is nothing downstream that looks different.
  describe "unknown keys" do
    it "refuses a misspelled section, and names what it expected" do
      expect_raises(Cogiteer::ConfigError, /toolkit.*graep|graep/) do
        Cogiteer::Config.from_yaml(BASE + "toolkit:\n  graep:\n    max_depth: 8\n")
      end
    end

    it "refuses a misspelled bound inside a good section" do
      expect_raises(Cogiteer::ConfigError, /max_dept/) do
        Cogiteer::Config.from_yaml(BASE + "toolkit:\n  grep:\n    max_dept: 8\n")
      end
    end

    it "names the section in the message, so the key can be found" do
      expect_raises(Cogiteer::ConfigError, /toolkit\.grep/) do
        Cogiteer::Config.from_yaml(BASE + "toolkit:\n  grep:\n    max_dept: 8\n")
      end
    end
  end

  describe "malformed tables" do
    it "refuses a toolkit that is not a block" do
      expect_raises(Cogiteer::ConfigError, /toolkit/) do
        Cogiteer::Config.from_yaml(BASE + "toolkit: shallow\n")
      end
    end

    it "refuses a section that is not a block" do
      expect_raises(Cogiteer::ConfigError, /toolkit\.grep/) do
        Cogiteer::Config.from_yaml(BASE + "toolkit:\n  grep: shallow\n")
      end
    end

    # A wrong type reaches `YAML::Serializable`, which raises about a type and
    # a line in a document the operator did not write. It arrives as a
    # `ConfigError` instead, like every other problem in this file.
    it "reports a wrong value type as a config error" do
      expect_raises(Cogiteer::ConfigError, /toolkit/) do
        Cogiteer::Config.from_yaml(BASE + "toolkit:\n  grep:\n    max_depth: deep\n")
      end
    end
  end

  # The ownership line: `reproducible` is this project's to drive, so the
  # flag overwrites whatever the file said rather than losing to it.
  it "lets the flag win over a reproducible written in the file" do
    toolkit = Cogiteer::Config.from_yaml(BASE + "toolkit:\n  reproducible: true\n").toolkit
    toolkit.reproducible?.should be_true

    Cogiteer::Tools::Offering.toolbox(Dir.current, names: [] of String,
      reproducible: false, toolkit: toolkit)
    toolkit.reproducible?.should be_false
  end
end
