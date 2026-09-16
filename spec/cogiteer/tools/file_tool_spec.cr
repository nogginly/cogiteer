require "file_utils"

require "../../spec_helper"
require "../../../src/cogiteer/tools/file_tool"

# The two libraries actually meeting: a real `FsUtils::Tools` over a real
# directory, driven through the `Liaison::Function` contract. No model and no
# network — the sandbox root is a temp directory rather than the process's
# working directory, so nothing here depends on where the suite is run from
# and nothing calls `Dir.cd`.
private def in_sandbox(& : FsUtils::Tools, String ->)
  root = File.join(Dir.tempdir, "cogiteer-tools-#{Random.new.hex(8)}")
  Dir.mkdir_p(File.join(root, "src"))
  File.write(File.join(root, "notes.txt"), "the first line\nthe second line\n")
  File.write(File.join(root, "src", "main.cr"), "puts 1\n")

  begin
    yield FsUtils::Tools.new(root), root
  ensure
    FileUtils.rm_rf(root)
  end
end

private def reader(tools : FsUtils::Tools) : Cogiteer::Tools::FileTool
  definition = tools.definitions.find! { |d| d.name == "read_text_file" }
  Cogiteer::Tools::FileTool.new(tools, definition)
end

private def arguments(pairs) : Liaison::MPSH::Object
  result = Liaison::MPSH::Object.new
  pairs.each { |key, value| result[key] = value }
  result
end

private def text_of(blocks : Array(Liaison::MPSH::Block)) : String
  blocks.size.should eq 1
  blocks[0].as(Liaison::MPSH::TextBlock).text
end

describe Cogiteer::Tools::FileTool do
  describe "the declaration" do
    it "is the definition's, unaltered" do
      in_sandbox do |tools, _|
        definition = tools.definitions.find! { |d| d.name == "read_text_file" }
        tool = Cogiteer::Tools::FileTool.new(tools, definition)

        tool.name.should eq definition.name
        tool.description.should eq definition.description
        tool.parameters.should eq definition.schema
      end
    end

    it "produces a Tool carrying a parseable schema" do
      in_sandbox do |tools, _|
        schema = JSON.parse(reader(tools).to_tool.parameters.not_nil!)
        schema["type"].as_s.should eq "object"
        schema["properties"].as_h.has_key?("path").should be_true
      end
    end
  end

  describe "a call that works" do
    it "returns one text block of the response body" do
      in_sandbox do |tools, _|
        blocks = reader(tools).call(arguments({"path" => "notes.txt"}))
        body = JSON.parse(text_of(blocks))

        body["ok"].as_bool.should be_true
        body["content"].as_s.should contain "the first line"
      end
    end

    it "carries an integer argument through the conversion" do
      in_sandbox do |tools, _|
        blocks = reader(tools).call(arguments({"path" => "notes.txt", "limit" => 1_i64}))
        body = JSON.parse(text_of(blocks))

        body["ok"].as_bool.should be_true
        body["content"].as_s.should contain "the first line"
        body["content"].as_s.should_not contain "the second line"
      end
    end

    it "carries a boolean argument through the conversion" do
      in_sandbox do |tools, _|
        blocks = reader(tools).call(arguments({"path" => "notes.txt", "line_numbers" => false}))
        JSON.parse(text_of(blocks))["content"].as_s.should start_with "the first line"
      end
    end
  end

  # The failure path is a raise rather than a block, because that is what sets
  # `is_error` on the result: `Toolbox` catches `Failure` and flags what it
  # builds. The message is the whole envelope, so `code` and `suggestion`
  # survive to the model.
  describe "a call the model can fix" do
    it "raises Failure carrying the envelope when the file is missing" do
      in_sandbox do |tools, _|
        error = expect_raises(Liaison::Function::Failure) do
          reader(tools).call(arguments({"path" => "absent.txt"}))
        end

        body = JSON.parse(error.message.not_nil!)
        body["ok"].as_bool.should be_false
        body["error"]["code"].as_s.should_not be_empty
      end
    end

    it "raises Failure when a required argument is missing" do
      in_sandbox do |tools, _|
        error = expect_raises(Liaison::Function::Failure) do
          reader(tools).call(Liaison::MPSH::Object.new)
        end

        JSON.parse(error.message.not_nil!)["ok"].as_bool.should be_false
      end
    end

    it "raises Failure when an argument has the wrong type" do
      in_sandbox do |tools, _|
        error = expect_raises(Liaison::Function::Failure) do
          reader(tools).call(arguments({"path" => "notes.txt", "limit" => "one"}))
        end

        JSON.parse(error.message.not_nil!)["ok"].as_bool.should be_false
      end
    end
  end

  # Confinement is the sandbox's, not this adapter's. Asserted here anyway,
  # because it is the property that makes handing these tools to a model
  # defensible and it should fail loudly if the root ever stops being applied.
  describe "the sandbox" do
    it "refuses a path outside the root" do
      in_sandbox do |tools, _|
        error = expect_raises(Liaison::Function::Failure) do
          reader(tools).call(arguments({"path" => "../../etc/passwd"}))
        end

        JSON.parse(error.message.not_nil!)["ok"].as_bool.should be_false
      end
    end

    it "reads a path below the root" do
      in_sandbox do |tools, _|
        blocks = reader(tools).call(arguments({"path" => "src/main.cr"}))
        JSON.parse(text_of(blocks))["content"].as_s.should contain "puts 1"
      end
    end
  end
end
