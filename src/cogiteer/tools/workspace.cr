require "fsutils"
require "liaison"

require "./file_tool"

module Cogiteer::Tools
  # What a tool does to the tree it is pointed at.
  #
  # Declared rather than inferred, so `--readonly` can mean "nothing that
  # declares a write" instead of "nothing on a list someone remembered to
  # update". A list goes stale silently; a flag cannot.
  @[Flags]
  enum Capability
    Read
    Write
  end

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
    class UnknownTool < Exception
    end

    # What each tool `FsUtils` offers does to the tree.
    #
    # A table rather than a `case`, so the suite can ask which names are
    # classified. An `else` branch is invisible to a spec.
    #
    # **An unrecognised name counts as writing.** The alternative — raising —
    # would turn a routine `shards update` into a CLI that will not start, on
    # nothing worse than the toolkit gaining an `ls`. Classifying it as a write
    # still fails closed: it is kept out of `--readonly`, and offered to a run
    # that asked for everything.
    #
    # The forcing function lives in the suite instead. A spec asserts every
    # definition is named here, so a new tool fails this project's tests on the
    # update that introduces it — which is when someone should decide what it
    # is, rather than when a user hits it.
    CAPABILITIES = {
      "find_files"           => Capability::Read,
      "search_file_contents" => Capability::Read,
      "read_text_file"       => Capability::Read,
      "write_text_file"      => Capability::Read | Capability::Write,
      "text_replace"         => Capability::Read | Capability::Write,
    }

    def self.capabilities(name : String) : Capability
      CAPABILITIES[name]? || Capability::Write
    end

    # `names` narrows what is offered; `nil` offers everything `FsUtils` has,
    # so a tool the toolkit gains arrives without a change here. An empty list
    # offers nothing, which is a thing an operator can mean.
    #
    # `readonly` then drops anything declaring a write, and takes precedence —
    # it exists to make a configured set safe for one run without editing the
    # configuration.
    #
    # `reproducible` drops the fields reporting *when and where* a call ran — a
    # walk's `elapsed_ms`, a find result's `modified` — leaving a response
    # derived only from the tree. Off by default, because an mtime is how a
    # model notices a file changed under it; on where two runs of the same
    # prompt have to agree, which includes every recorded spec.
    #
    # The root is the current working directory: the tools are for the project
    # someone is standing in. `FsUtils::Tools::Sandbox` resolves every
    # agent-supplied path against it and compares the resolved form, so `..`
    # and symlinks cannot launder a path past it.
    #
    # Raises `UnknownTool` for a name `FsUtils` does not offer. A typo that
    # silently dropped a tool would leave a model quietly unable to do
    # something, with nothing to read explaining why.
    def self.toolbox(root : String = Dir.current,
                     names : Array(String)? = nil,
                     readonly : Bool = false,
                     reproducible : Bool = false) : Liaison::Toolbox
      config = FsUtils::Tools::Config.new
      config.reproducible = reproducible
      tools = FsUtils::Tools.new(root, config)

      definitions = tools.definitions
      if names
        offered = definitions.map(&.name)
        names.each do |name|
          next if offered.includes?(name)
          raise UnknownTool.new("no tool named #{name.inspect} — available: #{offered.join(", ")}")
        end
        definitions = definitions.select { |definition| names.includes?(definition.name) }
      end

      if readonly
        definitions = definitions.reject do |definition|
          capabilities(definition.name).includes?(Capability::Write)
        end
      end

      functions = definitions.map do |definition|
        FileTool.new(tools, definition).as(Liaison::Function)
      end

      Liaison::Toolbox.new(functions)
    end
  end
end
