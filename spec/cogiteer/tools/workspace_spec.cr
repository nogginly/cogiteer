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
  it "offers only the enabled tools" do
    in_sandbox do |root|
      names = Cogiteer::Tools::Workspace.toolbox(root).functions.map(&.name)
      names.should eq Cogiteer::Tools::Workspace::ENABLED
    end
  end

  it "produces declarations a request can carry" do
    in_sandbox do |root|
      declarations = Cogiteer::Tools::Workspace.toolbox(root).tools

      declarations.size.should eq Cogiteer::Tools::Workspace::ENABLED.size
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
        reader = Cogiteer::Tools::Workspace.toolbox(first).functions.first
        arguments = Liaison::MPSH::Object{"path" => "notes.txt"}

        File.delete(File.join(second, "notes.txt"))
        reader.call(arguments).should_not be_empty

        elsewhere = Cogiteer::Tools::Workspace.toolbox(second).functions.first
        expect_raises(Liaison::Function::Failure) { elsewhere.call(arguments) }
      end
    end
  end
end
