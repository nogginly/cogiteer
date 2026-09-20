require "file_utils"

require "../../spec_helper"
require "../../../src/cogiteer/tools/offering"

private def in_workspace(& : String ->)
  root = File.join(Dir.tempdir, "cogiteer-offering-#{Random.new.hex(8)}")
  Dir.mkdir_p(root)
  File.write(File.join(root, "notes.txt"), "a line\n")

  begin
    yield root
  ensure
    FileUtils.rm_rf(root)
  end
end

describe Cogiteer::Tools::Offering do
  # Everything except the network tools, which `web` admits rather than
  # `no_edit` dropping: that default is the one thing here an operator has to
  # ask for, so the unnarrowed set is not the whole toolkit.
  it "offers every local tool the toolkit has when nothing narrows it" do
    in_workspace do |root|
      offered = Cogiteer::Tools::Offering.toolbox(root).functions.map(&.name)
      local = FsUtils::Tools.new(root).definitions
        .reject(&.capabilities.network?)
        .map(&.name)

      offered.sort.should eq local.sort
    end
  end

  it "offers everything when web is allowed" do
    in_workspace do |root|
      offered = Cogiteer::Tools::Offering.toolbox(root, web: true).functions.map(&.name)
      offered.sort.should eq FsUtils::Tools.new(root).definitions.map(&.name).sort
    end
  end

  describe "web" do
    it "keeps a network tool out of a set that named it" do
      in_workspace do |root|
        toolbox = Cogiteer::Tools::Offering.toolbox(root, names: ["fetch_as_markdown"])
        toolbox.functions.should be_empty
      end
    end

    it "offers a network tool that was named once web is allowed" do
      in_workspace do |root|
        toolbox = Cogiteer::Tools::Offering.toolbox(root, names: ["fetch_as_markdown"], web: true)
        toolbox.functions.map(&.name).should eq ["fetch_as_markdown"]
      end
    end

    # The two gates are independent, and the combination is the one an
    # operator reaching for both would expect: read the web, touch nothing.
    # This is also where `ScratchWrite` surviving `no_edit` is asserted, since
    # a fetch that spills a large page is the tool that has it.
    it "admits a network tool under no_edit" do
      in_workspace do |root|
        offered = Cogiteer::Tools::Offering
          .toolbox(root, web: true, no_edit: true)
          .functions.map(&.name)

        offered.should contain "fetch_as_markdown"
        offered.should_not contain "write_text_file"
      end
    end
  end

  describe "narrowing" do
    it "offers only what was named" do
      in_workspace do |root|
        toolbox = Cogiteer::Tools::Offering.toolbox(root, names: ["read_text_file"])
        toolbox.functions.map(&.name).should eq ["read_text_file"]
      end
    end

    it "offers nothing for an empty list" do
      in_workspace do |root|
        Cogiteer::Tools::Offering.toolbox(root, names: [] of String).functions.should be_empty
      end
    end

    # A typo that silently dropped a tool would leave a model unable to do
    # something with nothing to read explaining why.
    it "refuses a name the toolkit does not offer" do
      in_workspace do |root|
        error = expect_raises(Cogiteer::Tools::Offering::UnknownTool) do
          Cogiteer::Tools::Offering.toolbox(root, names: ["read_text_fil"])
        end
        error.message.not_nil!.should contain "read_text_file"
      end
    end
  end

  describe "no_edit" do
    it "drops every tool that writes" do
      in_workspace do |root|
        offered = Cogiteer::Tools::Offering.toolbox(root, no_edit: true).functions.map(&.name)

        offered.should contain "read_text_file"
        offered.should_not contain "write_text_file"
        offered.should_not contain "text_replace"
      end
    end

    it "overrides a named set that asked for a writing tool" do
      in_workspace do |root|
        offered = Cogiteer::Tools::Offering
          .toolbox(root, names: ["read_text_file", "write_text_file"], no_edit: true)
          .functions.map(&.name)

        offered.should eq ["read_text_file"]
      end
    end
  end

  it "produces declarations a request can carry" do
    in_workspace do |root|
      toolbox = Cogiteer::Tools::Offering.toolbox(root)
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
    in_workspace do |first|
      in_workspace do |second|
        # Narrowed by name rather than taken positionally: the toolbox offers
        # every tool now, and `find_files` wants an array where this wants a
        # string.
        reader = Cogiteer::Tools::Offering.toolbox(first, names: ["read_text_file"]).functions.first
        arguments = Liaison::MPSH::Object{"path" => "notes.txt"}

        File.delete(File.join(second, "notes.txt"))
        reader.call(arguments).should_not be_empty

        elsewhere = Cogiteer::Tools::Offering.toolbox(second, names: ["read_text_file"]).functions.first
        expect_raises(Liaison::Function::Failure) { elsewhere.call(arguments) }
      end
    end
  end
end
