require "fsutils"
require "liaison"

require "./file_tool"

module Cogiteer::Tools
  # Which tools a turn is offered, over one directory.
  #
  # ```
  # toolbox = Cogiteer::Tools::Offering.toolbox
  # options = Liaison::Options.new(tools: toolbox.tools)
  # ```
  #
  # Named for what it decides rather than for what it builds. A `Toolbox` here
  # would collide with the `Liaison::Toolbox` it returns, and `Workspace` now
  # belongs to `FsUtils::Tools::Workspace`, which is the path confinement and
  # has the better claim on the word.
  #
  # What a tool touches is `FsUtils::Tools::Capability`, declared on each
  # `Definition` by the shard that implements it. Which of those an operator
  # allows is this module's question, and the two are kept apart on purpose.
  #
  # **Built per invocation, never memoised.** `FsUtils::Tools` fixes its
  # workspace root at construction, so a toolbox held across runs would carry
  # one run's root into the next — and `Liaison::Function`'s contract warns
  # separately that instances outlive a call and leak between sessions. This
  # process runs one session and exits, which makes that safe by accident;
  # building here rather than at the call sites keeps it safe on purpose.
  module Offering
    class UnknownTool < Exception
    end

    # `names` narrows what is offered; `nil` offers everything `FsUtils` has,
    # so a tool the toolkit gains arrives without a change here. An empty list
    # offers nothing, which is a thing an operator can mean.
    #
    # Two gates then apply to whatever `names` left, and both take precedence
    # over it, because each exists to make a configured set safe for one run
    # without editing the configuration. A set narrowed to one tool that a
    # gate then drops offers nothing, which is the gate doing its job.
    #
    # `no_edit` drops anything declaring `Capability::WorkspaceWrite`. What it
    # protects is the user's files, so a tool writing only to the scratch
    # directory survives it — `ScratchWrite` is a separate capability for
    # exactly that reason — and a tool that leaves the machine survives it
    # too, since nothing here can promise what a request does at the far end.
    #
    # The gate tests what a tool *changes*, never what it reads, so a
    # reclassification of the reading half cannot widen or narrow it.
    #
    # `web` admits anything declaring `Capability::Network`, and its default
    # of false is the one asymmetry: every other gate here subtracts from what
    # was asked for, and this one has to be asked for. Egress is not something
    # a `shards update` should be able to turn on.
    #
    # `toolkit` is the operator's `toolkit:` table — every bound the tools run
    # under. It arrives already parsed, and this project overwrites exactly one
    # field of it, below, so that a flag never loses silently to a file.
    #
    # `reproducible` drops the fields reporting *when and where* a call ran — a
    # walk's `elapsed_ms`, a find result's `modified` — leaving a response
    # derived only from the tree. Off by default, because an mtime is how a
    # model notices a file changed under it; on where two runs of the same
    # prompt have to agree, which includes every recorded spec.
    #
    # The root is the current working directory: the tools are for the project
    # someone is standing in. `FsUtils::Tools::Workspace` resolves every
    # agent-supplied path against it and compares the resolved form, so `..`
    # and symlinks cannot launder a path past it.
    #
    # Raises `UnknownTool` for a name `FsUtils` does not offer. A typo that
    # silently dropped a tool would leave a model quietly unable to do
    # something, with nothing to read explaining why.
    def self.toolbox(root : String = Dir.current,
                     names : Array(String)? = nil,
                     no_edit : Bool = false,
                     web : Bool = false,
                     reproducible : Bool = false,
                     toolkit : FsUtils::Tools::Config = FsUtils::Tools::Config.new) : Liaison::Toolbox
      toolkit.reproducible = reproducible
      tools = FsUtils::Tools.new(root, toolkit)

      definitions = tools.definitions
      if names
        offered = definitions.map(&.name)
        names.each do |name|
          next if offered.includes?(name)
          raise UnknownTool.new("no tool named #{name.inspect} — available: #{offered.join(", ")}")
        end
        definitions = definitions.select { |definition| names.includes?(definition.name) }
      end

      definitions = definitions.reject(&.capabilities.network?) unless web
      definitions = definitions.reject(&.capabilities.workspace_write?) if no_edit

      functions = definitions.map do |definition|
        FileTool.new(tools, definition).as(Liaison::Function)
      end

      Liaison::Toolbox.new(functions)
    end
  end
end
