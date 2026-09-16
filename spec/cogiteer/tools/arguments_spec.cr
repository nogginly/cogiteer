require "../../spec_helper"
require "../../../src/cogiteer/tools/arguments"

# Pure: an `MPSH::Object` in, a `Hash(String, JSON::Any)` out. No tool, no
# sandbox, no model — this file asserts only that the seam loses nothing.
#
# `MPSH::Value` is named in full rather than re-aliased here. It is recursive,
# through `Array(Value)` and `Hash(String, Value)`, so a local alias expands to
# a flattened union that Crystal treats as a different type.
private def object(pairs) : Liaison::MPSH::Object
  result = Liaison::MPSH::Object.new
  pairs.each { |key, value| result[key] = value }
  result
end

describe Cogiteer::Tools::Arguments do
  it "carries an empty call through" do
    Cogiteer::Tools::Arguments.for(Liaison::MPSH::Object.new).should be_empty
  end

  describe "scalars" do
    it "keeps a string" do
      result = Cogiteer::Tools::Arguments.for(object({"path" => "README.md"}))
      result["path"].as_s.should eq "README.md"
    end

    it "keeps a bool" do
      result = Cogiteer::Tools::Arguments.for(object({"recursive" => true}))
      result["recursive"].as_bool.should be_true
    end

    it "keeps a float" do
      result = Cogiteer::Tools::Arguments.for(object({"timeout_seconds" => 1.5}))
      result["timeout_seconds"].as_f.should eq 1.5
    end

    it "keeps a null" do
      result = Cogiteer::Tools::Arguments.for(object({"after" => nil}))
      result["after"].raw.should be_nil
    end
  end

  # The one conversion with a downstream consequence. `FsUtils` reads a schema's
  # `integer` from the raw value, so what matters is that an `Int64` arrives as
  # an `Int64` rather than as a float carrying the same quantity.
  #
  # Asserted on `raw` deliberately. `JSON::Any#as_f?` widens an integer, so it
  # answers a question about the reader rather than about what was stored.
  describe "an integer" do
    result = Cogiteer::Tools::Arguments.for(object({"max_matches" => 200_i64}))

    it "reads back as an integer" do
      result["max_matches"].as_i64.should eq 200
    end

    it "is stored as an integer, not a float" do
      result["max_matches"].raw.should be_a(Int64)
    end
  end

  # Nested literals carry `of Liaison::MPSH::Value`, because a bare literal
  # infers its own element union and `Array(String | Int64 | Nil)` is not an
  # `Array(Value)`.
  describe "nesting" do
    it "converts inside an array" do
      roots = ["src", 2_i64, nil] of Liaison::MPSH::Value
      result = Cogiteer::Tools::Arguments.for(object({"roots" => roots}))

      items = result["roots"].as_a
      items[0].as_s.should eq "src"
      items[1].as_i64.should eq 2
      items[2].raw.should be_nil
    end

    it "converts inside a hash" do
      options = {"case_sensitive" => false} of String => Liaison::MPSH::Value
      result = Cogiteer::Tools::Arguments.for(object({"options" => options}))

      result["options"].as_h["case_sensitive"].as_bool.should be_false
    end

    it "converts all the way down" do
      inner = {"depth" => 3_i64} of String => Liaison::MPSH::Value
      where = [inner] of Liaison::MPSH::Value
      result = Cogiteer::Tools::Arguments.for(object({"where" => where}))

      result["where"].as_a[0].as_h["depth"].as_i64.should eq 3
    end
  end

  # A model's mistakes are the reason the far side takes `JSON::Any` at all:
  # they have to arrive intact to be refused there rather than here.
  it "passes a wrongly-typed value through unchanged" do
    result = Cogiteer::Tools::Arguments.for(object({"max_matches" => "200"}))

    result["max_matches"].as_s.should eq "200"
    result["max_matches"].as_i64?.should be_nil
  end
end
