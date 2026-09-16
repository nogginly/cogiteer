require "json"
require "liaison"

module Cogiteer::Tools
  # Tool-call arguments, as `FsUtils` wants them.
  #
  # A model's arguments arrive from `liaison` as `MPSH::Object` and are wanted
  # by `FsUtils::Tools#call` as `Hash(String, JSON::Any)`. The two libraries
  # disagree deliberately and both are right locally: `MPSH::Value` exists so
  # canonical types carry no parse artifact, and `FsUtils::Tools::Arguments`
  # takes `JSON::Any` so a model's mistake — `max_matches: "200"` — survives
  # far enough into that shard to be refused in its own error vocabulary.
  #
  # **This application owns the seam.** Closing it in either library would be a
  # change whose only beneficiary is this one caller: a `Value#to_json_any`
  # would put a serialization identity back into the types that exist to avoid
  # it, and a typed argument struct on the other side would move rejection into
  # the host and break that shard's promise never to raise for anything a model
  # can fix.
  #
  # Nothing is interpreted here. Every arm maps to its JSON counterpart and the
  # values a model got wrong pass through intact, which is what makes them
  # refusable downstream.
  module Arguments
    # Converts one call's arguments. Total: every arm of `MPSH::Value` has a
    # `JSON::Any` counterpart, so nothing is lost and nothing can fail.
    def self.for(arguments : Liaison::MPSH::Object) : Hash(String, JSON::Any)
      arguments.transform_values { |value| converted(value) }
    end

    # Exhaustive by `in` rather than `when`, so adding an arm to `MPSH::Value`
    # fails the build here instead of reaching a tool as something unexpected.
    #
    # `Int64` stays `Int64`, which is what a schema's `integer` is read from on
    # the far side. Widening happens in the readers there, not here.
    private def self.converted(value : Liaison::MPSH::Value) : JSON::Any
      case value
      in Nil
        JSON::Any.new(nil)
      in Bool
        JSON::Any.new(value)
      in Int64
        JSON::Any.new(value)
      in Float64
        JSON::Any.new(value)
      in String
        JSON::Any.new(value)
      in Array(Liaison::MPSH::Value)
        JSON::Any.new(value.map { |item| converted(item) })
      in Hash(String, Liaison::MPSH::Value)
        JSON::Any.new(value.transform_values { |item| converted(item) })
      end
    end
  end
end
