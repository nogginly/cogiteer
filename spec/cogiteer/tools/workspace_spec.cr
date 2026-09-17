require "file_utils"

require "../../spec_helper"
require "../../../src/cogiteer/tools/workspace"

private def in_sandbox(& : String ->)
  root = File.join(Dir.tempdir, "cogiteer-workspace-#{Random.new.hex(8)}")
  Dir.mkdir_p(root)
  File.write(File.join(root, "notes.txt"), "a line\n")

  begin
    yield root
  ensure
    FileUtils.rm_rf(root)
  end
end

describe Cogiteer::Tools::Workspace do
  it "offers everything the toolkit has when nothing narrows it" do
    in_sandbox do |root|
      offered = Cogiteer::Tools::Workspace.toolbox(root).functions.map(&.name)
      offered.sort.should eq FsUtils::Tools.new(root).definitions.map(&.name).sort
    end
  end

  # The forcing function for `capabilities`. An unrecognised name is treated as
  # writing rather than raising, so that a toolkit update cannot stop the CLI
  # starting — which means nothing at runtime would ever report a tool nobody
  # classified. This does.
  it "classifies every tool the toolkit offers" do
    in_sandbox do |root|
      classified = Cogiteer::Tools::Workspace::CAPABILITIES.keys
      FsUtils::Tools.new(root).definitions.map(&.name).each do |name|
        fail("#{name} is not classified in Workspace::CAPABILITIES") unless classified.includes?(name)
      end
    end
  end

  describe "narrowing" do
    it "offers only what was named" do
      in_sandbox do |root|
        toolbox = Cogiteer::Tools::Workspace.toolbox(root, names: ["read_text_file"])
        toolbox.functions.map(&.name).should eq ["read_text_file"]
      end
    end

    it "offers nothing for an empty list" do
      in_sandbox do |root|
        Cogiteer::Tools::Workspace.toolbox(root, names: [] of String).functions.should be_empty
      end
    end

    # A typo that silently dropped a tool would leave a model unable to do
    # something with nothing to read explaining why.
    it "refuses a name the toolkit does not offer" do
      in_sandbox do |root|
        error = expect_raises(Cogiteer::Tools::Workspace::UnknownTool) do
          Cogiteer::Tools::Workspace.toolbox(root, names: ["read_text_fil"])
        end
        error.message.not_nil!.should contain "read_text_file"
      end
    end
  end

  describe "readonly" do
    it "drops every tool that writes" do
      in_sandbox do |root|
        offered = Cogiteer::Tools::Workspace.toolbox(root, readonly: true).functions.map(&.name)

        offered.should contain "read_text_file"
        offered.should_not contain "write_text_file"
        offered.should_not contain "text_replace"
      end
    end

    it "overrides a named set that asked for a writing tool" do
      in_sandbox do |root|
        offered = Cogiteer::Tools::Workspace
          .toolbox(root, names: ["read_text_file", "write_text_file"], readonly: true)
          .functions.map(&.name)

        offered.should eq ["read_text_file"]
      end
    end
  end

  it "produces declarations a request can carry" do
    in_sandbox do |root|
      toolbox = Cogiteer::Tools::Workspace.toolbox(root)
      declarations = toolbox.tools

      declarations.size.should eq toolbox.functions.size
      declarations.each do |tool|
        tool.name.should_not be_empty
        JSON.parse(tool.parameters.not_nil!)["type"].as_s.should eq "object"
      end
    end
  end

  # The root is what makes the tools safe to offer, so it is asserted rather
  # than assumed: two toolboxes over different directories must not see each
  # other's files.
  it "roots each toolbox where it was told" do
    in_sandbox do |first|
      in_sandbox do |second|
        # Narrowed by name rather than taken positionally: the toolbox offers
        # every tool now, and `find_files` wants an array where this wants a
        # string.
        reader = Cogiteer::Tools::Workspace.toolbox(first, names: ["read_text_file"]).functions.first
        arguments = Liaison::MPSH::Object{"path" => "notes.txt"}

        File.delete(File.join(second, "notes.txt"))
        reader.call(arguments).should_not be_empty

        elsewhere = Cogiteer::Tools::Workspace.toolbox(second, names: ["read_text_file"]).functions.first
        expect_raises(Liaison::Function::Failure) { elsewhere.call(arguments) }
      end
    end
  end
end
