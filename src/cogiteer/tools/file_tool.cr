require "fsutils"
require "liaison"

require "./arguments"

module Cogiteer::Tools
  # One `FsUtils` tool, as something `Liaison::Toolbox` can declare and run.
  #
  # The two libraries already agree about almost everything. `Definition`
  # carries a name, a description and a JSON Schema as text, which is exactly
  # what `Function` declares; `Tools#call` takes named arguments and returns a
  # response. So this is a join rather than a translation, and it is one class
  # per tool sharing one `Tools` rather than a hand-written class each.
  #
  # ```
  # tools = FsUtils::Tools.new(Dir.current)
  # functions = tools.definitions.map { |d| FileTool.new(tools, d) }
  # ```
  #
  # **Build these per invocation.** A `Tools` fixes its sandbox root at
  # construction, and `Function`'s own contract warns that instances outlive a
  # call and leak between sessions. Nothing here holds per-call state, but the
  # root is per-run state and memoising a toolbox would carry one run's root
  # into the next.
  class FileTool
    include Liaison::Function

    def initialize(@tools : FsUtils::Tools, @definition : FsUtils::Tools::Definition)
    end

    def name : String
      @definition.name
    end

    def description : String?
      @definition.description
    end

    def parameters : String
      @definition.schema
    end

    # The model sees the same bytes either way; what differs is whether the
    # result is flagged.
    #
    # `FsUtils` reports failure inside the body as `ok: false` and every
    # protocol carries it on the block instead, so an unflagged failure would
    # tell a model the call succeeded while its body said otherwise. `Failure`
    # is what sets that flag: `Toolbox` catches it and builds the result block
    # with `is_error`. The whole envelope goes into the message rather than
    # just `error.message`, so the model keeps the code and the suggestion.
    #
    # `Tools#call` raises `ArgumentError` for a name it does not hold, and that
    # is deliberately not caught. A model inventing a name never reaches here —
    # `Toolbox` answers an unknown name itself — so the only way to raise it is
    # to construct this with a definition the `Tools` disowns, which is a
    # wiring bug and should look like one.
    def call(arguments : Liaison::MPSH::Object) : Array(Liaison::MPSH::Block)
      response = @tools.call(@definition.name, Arguments.for(arguments))
      body = response.to_json
      raise Liaison::Function::Failure.new(body) unless response.ok?

      [Liaison::MPSH::TextBlock.new(body).as(Liaison::MPSH::Block)]
    end
  end
end
