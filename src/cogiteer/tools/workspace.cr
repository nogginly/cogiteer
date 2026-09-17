require "fsutils"
require "liaison"

require "./file_tool"

module Cogiteer::Tools
  # A toolbox over one directory.
  #
  # ```
  # toolbox = Cogiteer::Tools::Workspace.toolbox
  # options = Liaison::Options.new(tools: toolbox.tools)
  # ```
  #
  # **Built per invocation, never memoised.** `FsUtils::Tools` fixes its
  # sandbox root at construction, so a toolbox held across runs would carry
  # one run's root into the next — and `Liaison::Function`'s contract warns
  # separately that instances outlive a call and leak between sessions. This
  # process runs one session and exits, which makes that safe by accident;
  # building here rather than at the call sites keeps it safe on purpose.
  module Workspace
    # The tools offered, by name.
    #
    # One to begin with. The adapter is general over any definition, so
    # widening this is the whole of adding a tool — and the read-only subset,
    # when there is a switch for it, is a different list rather than different
    # code.
    ENABLED = ["read_text_file"]

    # The root is the current working directory: the tools are for the project
    # someone is standing in. `FsUtils::Tools::Sandbox` resolves every
    # agent-supplied path against it and compares the resolved form, so `..`
    # and symlinks cannot launder a path past it.
    # `reproducible` drops the fields that report *when and where* a call ran
    # — a walk's `elapsed_ms`, a find result's `modified` — leaving a response
    # derived only from the tree. Off by default, because an mtime is how a
    # model notices a file changed under it; on where two runs of the same
    # prompt have to agree, which includes every recorded spec.
    def self.toolbox(root : String = Dir.current, reproducible : Bool = false) : Liaison::Toolbox
      config = FsUtils::Tools::Config.new
      config.reproducible = reproducible
      tools = FsUtils::Tools.new(root, config)
      functions = tools.definitions
        .select { |definition| ENABLED.includes?(definition.name) }
        .map { |definition| FileTool.new(tools, definition).as(Liaison::Function) }

      Liaison::Toolbox.new(functions)
    end
  end
end
