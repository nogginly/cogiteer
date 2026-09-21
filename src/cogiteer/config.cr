require "socket_connect_fix"
require "yaml"
require "liaison"

require "./toolkit"

module Cogiteer
  class ConfigError < Exception
  end

  # Azure OpenAI is not a protocol, it is a way of addressing one — a
  # different URL shape and a mandatory `api-version`. Modelled as a present-
  # or-absent block on the *server* rather than a boolean on a model entry,
  # which is where it used to live.
  #
  # Two things fall out of that. `api_version` is non-nilable here, so
  # "azure with no api_version" stops being a runtime error in `provider_for`
  # and becomes a shape that cannot be written down. And the fact lands on the
  # thing it describes: Azure is about where the request goes, not about which
  # model answers it.
  struct AzureAddressing
    getter api_version : String

    def initialize(@api_version : String)
      raise ConfigError.new("azure block needs an api_version") if @api_version.empty?
    end
  end

  # An endpoint: somewhere to send requests, and the protocol it speaks.
  #
  # Split out from `Deployment` because a local Ollama serving six models had
  # to repeat its URL and protocol six times, and because everything that was
  # awkward about the flat table turned out to be a server fact wearing a
  # model entry's clothes. `max_tokens_field` belongs here for the same
  # reason `protocol` does — `Liaison::Provider.for_azure` already rejects it on
  # anything but ChatCompletions, which makes it a property of the protocol,
  # and protocol is a property of the endpoint.
  struct ServerConfig
    getter name : String
    getter protocol : Liaison::ProtocolKind
    getter url : String
    getter credential_env : String?
    getter azure : AzureAddressing?
    getter max_tokens_field : Liaison::Protocol::ChatCompletions::Wire::MaxTokensField?

    def initialize(@name : String, @protocol : Liaison::ProtocolKind, @url : String,
                   @credential_env : String? = nil,
                   @azure : AzureAddressing? = nil,
                   @max_tokens_field : Liaison::Protocol::ChatCompletions::Wire::MaxTokensField? = nil)
    end

    # `nil` here, silently, is deliberate: an unset credential means an
    # unauthenticated call, which some servers (a local Ollama) genuinely
    # want. What this does *not* do is warn about a set-but-empty environment
    # variable — that failure surfaces as a 401 from the server itself, which
    # already carries more information than a guess made here could.
    def credential : String?
      credential_env.try { |name| ENV[name]? }
    end
  end

  # One named way to reach one model: a server, and what to ask of it.
  #
  # The name is what `start`/`continue` take and what a snapshot filename
  # records, so it stays the CLI's unit of identity even though it no longer
  # carries the endpoint itself.
  #
  # ## Why model preferences are configuration and not a catalog
  #
  # `reasoning` and `reasoning_retention` are model-specific facts, and this
  # shard already has a place for model-specific facts —
  # `Capability::Catalog`. They deliberately do not go there.
  #
  # The catalog holds **hard protocol facts**: get `SIGNED_TOOL_CALLS` wrong
  # and the request 400s, the vendor is the authority, and nobody's local
  # opinion should override it. These are **soft quality preferences**: qwen3.8
  # thinking too much and gemma4 preferring reasoning dropped from closed turns
  # are things an operator reads off a model card, get them wrong and the
  # answers are merely worse, and reasonable people running the same model may
  # disagree. Hard facts that break requests are ours to get right; soft
  # preferences are the operator's to state.
  #
  # It also means adding a model never requires a release, which for locally
  # served models is most of the point.
  #
  # This closes the question `Capability::Retention` parked — whether a model
  # catalog should exist for `CompletedTurns`. Answer: no, it is configuration.
  struct Deployment
    getter name : String
    getter server : ServerConfig
    getter model : String

    # Absent means absent, all the way down to the wire. `Options#reasoning`
    # documents why that is load-bearing rather than tidy: a request that does
    # not ask for reasoning stays byte-identical to what it was before this
    # option existed, so no recorded transcript is re-cut by adding it.
    getter reasoning : Liaison::Reasoning::Request?

    # `nil` leaves `Client`'s own default (`All`) in charge, rather than this
    # struct restating it — same reasoning as above, one layer up.
    getter reasoning_retention : Liaison::Capability::ReasoningRetention?

    def initialize(@name : String, @server : ServerConfig, @model : String,
                   @reasoning : Liaison::Reasoning::Request? = nil,
                   @reasoning_retention : Liaison::Capability::ReasoningRetention? = nil)
    end

    def protocol : Liaison::ProtocolKind
      server.protocol
    end
  end

  # How the CLI behaves, as opposed to where requests go or what is asked of
  # a model. The third question, and the one that had no home: a server is
  # *where*, a deployment is *what to ask of which model*, and neither of them
  # is *how the terminal behaves while the answer arrives*.
  #
  # Every key here pairs with a flag of the same name, so there is no
  # translation table between the config and `--help`. A key with no flag
  # behind it should be viewed with suspicion — that is how a section like
  # this becomes a junk drawer.
  #
  # Both flags default to false. The quiet, non-streaming, no-thinking-shown
  # behaviour is what the CLI did before either key existed, so an
  # `cogiteer.yaml` written today keeps meaning what it meant.
  struct Defaults
    # A ceiling on a runaway, not a budget. High enough that an honest session
    # never reaches it, which is what stops width and depth competing: a model
    # that opens with a wide parallel search should still have room left to
    # act on what it found.
    #
    # Counted in calls rather than in rounds. Every round holds at least one
    # call, so a cap on calls bounds the number of requests as well — where a
    # cap on rounds leaves one round free to make a hundred calls, and it is
    # calls that put tool results into the context.
    #
    # Zero declares no tools at all, which is also what the CLI did before any
    # of this existed.
    DEFAULT_MAX_TOOL_CALLS = 50

    getter? streaming : Bool
    getter? show_reasoning : Bool
    getter max_tool_calls : Int32
    getter? reproducible_tools : Bool
    # Which tools to offer. Nil offers everything the toolkit has, so a tool it
    # gains arrives without anyone editing a list here; an empty list offers
    # none. The names are checked where the tools are known, not here.
    getter tools : Array(String)?
    # Whether a turn may leave the machine. False by default: a tool that
    # reaches the internet is something an operator turns on, not something
    # they discover a dependency update gave them.
    #
    # False does not offer the tool, rather than offering it and refusing
    # every URL. A refusal costs a call and teaches a model something it
    # cannot act on, and `FsUtils` gives the empty-allowlist refusal its own
    # "stop, do not retry" suggestion precisely because it is unfixable from
    # the model's side.
    #
    # *Whether* the tool is offered is this key; *where* it may go is
    # `toolkit.fetch`. A boolean because the third state this was once an
    # enum for — an allowlist of hosts — found its home in that table instead.
    getter? web : Bool

    def initialize(@streaming : Bool = false, @show_reasoning : Bool = false,
                   @max_tool_calls : Int32 = DEFAULT_MAX_TOOL_CALLS,
                   @reproducible_tools : Bool = false,
                   @tools : Array(String)? = nil,
                   @web : Bool = false)
      raise ConfigError.new("max_tool_calls is #{@max_tool_calls} — expected 0 or more") if @max_tool_calls < 0
    end

    # Whether this run offers tools at all.
    def tools? : Bool
      @max_tool_calls > 0
    end
  end

  class Config
    getter defaults : Defaults
    getter servers : Hash(String, ServerConfig)
    getter deployments : Hash(String, Deployment)
    # How the tools behave once offered. A third top-level table rather than a
    # key under `defaults`, where every key pairs with a flag of the same name
    # and nested per-tool bounds could not.
    getter toolkit : FsUtils::Tools::Config

    def initialize(@servers : Hash(String, ServerConfig),
                   @deployments : Hash(String, Deployment),
                   @defaults : Defaults = Defaults.new,
                   @toolkit : FsUtils::Tools::Config = FsUtils::Tools::Config.new)
    end

    # `$CWD/cogiteer.yaml`, then `$HOME/cogiteer.yaml`. See `docs/DESIGN.md`.
    def self.load : Config
      path = locate || raise ConfigError.new(
        "no cogiteer.yaml found via $COGITEER_CONFIG, #{Dir.current}, or $HOME — see docs/DESIGN.md")
      from_yaml(File.read(path))
    end

    # Explicit beats implicit: `$COGITEER_CONFIG`, if set, names the file
    # directly and skips the search — the same reasoning `$COGITEER_HOME`
    # already exists for `Sessions`. Not just a testing convenience: without
    # it, a sandboxed test has no way to avoid being shadowed by whatever
    # real `cogiteer.yaml` an actual invocation happens to have left sitting in
    # `$CWD` or `$HOME`, and checking `$CWD` first gives an explicit override
    # nothing to override *with*.
    def self.locate : String?
      return ENV["COGITEER_CONFIG"]? if ENV["COGITEER_CONFIG"]?

      cwd_candidate = File.join(Dir.current, "cogiteer.yaml")
      return cwd_candidate if File.exists?(cwd_candidate)

      if home = ENV["HOME"]?
        home_candidate = File.join(home, "cogiteer.yaml")
        return home_candidate if File.exists?(home_candidate)
      end

      nil
    end

    def self.from_yaml(text : String) : Config
      root = YAML.parse(text)

      servers_node = root["servers"]?.try(&.as_h?) ||
                     raise ConfigError.new(legacy?(root) ? LEGACY_HELP : "cogiteer.yaml has no 'servers' key")

      servers = {} of String => ServerConfig
      servers_node.each do |key, node|
        name = key.as_s
        servers[name] = parse_server(name, node)
      end

      table = root["deployments"]?.try(&.as_h?) || raise ConfigError.new("cogiteer.yaml has no 'deployments' key")

      deployments = {} of String => Deployment
      table.each do |key, node|
        name = key.as_s
        deployments[name] = parse_deployment(name, node, servers)
      end

      new(servers, deployments, parse_defaults(root["defaults"]?), Toolkit.parse(root["toolkit"]?))
    end

    # Absent means the defaults, which are what the CLI did before this block
    # existed. A present block may name either key or neither.
    private def self.parse_defaults(node : YAML::Any?) : Defaults
      return Defaults.new if node.nil? || node.raw.nil?

      node.as_h? || raise ConfigError.new(
        "'defaults' is not a block — expected 'defaults:' with keys such as 'streaming' under it")

      Defaults.new(
        streaming: parse_flag(node, "streaming"),
        show_reasoning: parse_flag(node, "show_reasoning"),
        max_tool_calls: parse_count(node, "max_tool_calls", Defaults::DEFAULT_MAX_TOOL_CALLS),
        reproducible_tools: parse_flag(node, "reproducible_tools"),
        tools: parse_names(node, "tools"),
        web: parse_flag(node, "web"),
      )
    end

    # Absent means every tool; `[]` means none. A bare `tools:` is neither — it
    # parses as null and would read as "all" while looking like "none", so it
    # is rejected rather than guessed at.
    private def self.parse_names(node : YAML::Any, key : String) : Array(String)?
      field = node[key]?
      return unless field

      if field.raw.nil?
        raise ConfigError.new(
          "'defaults.#{key}' has no value — write a list of tool names, or '[]' to offer none")
      end

      list = field.as_a? ||
             raise ConfigError.new("'defaults.#{key}' is #{field.raw.inspect} — expected a list of tool names")
      list.map do |entry|
        entry.as_s? || raise ConfigError.new("'defaults.#{key}' holds #{entry.raw.inspect} — expected a tool name")
      end
    end

    # Absent means the built-in, not zero. Zero is a thing someone can ask for
    # — it turns tools off — so it cannot double as "unset".
    private def self.parse_count(node : YAML::Any, key : String, fallback : Int32) : Int32
      field = node[key]?
      return fallback if field.nil? || field.raw.nil?

      value = field.as_i? ||
              raise ConfigError.new("'defaults.#{key}' is #{field.raw.inspect} — expected a whole number")
      raise ConfigError.new("'defaults.#{key}' is #{value} — expected 0 or more") if value < 0

      value
    end

    # Anything that is not a boolean is refused, and the message names the key
    # — `defaults.streaming`, not "expected true or false" on its own, which
    # in a file with two boolean keys tells you nothing about which one.
    private def self.parse_flag(node : YAML::Any, key : String) : Bool
      field = node[key]?
      return false if field.nil? || field.raw.nil?

      value = field.as_bool?
      return value unless value.nil?

      raise ConfigError.new("'defaults.#{key}' is #{field.raw.inspect} — expected true or false")
    end

    # The old flat table said `server: https://…` on the deployment itself.
    # Under the new shape that parses as a reference to a server *named* after
    # a URL, and would fail with "no server named
    # \"http://localhost:11434\"" — technically accurate and useless.
    #
    # Sniffed once, at load, to produce an error that says what to change.
    # Deliberately not supported as an alternative shape: accepting both
    # forever would mean `server:` means two things depending on whether it
    # contains a colon-slash-slash, which is exactly the kind of cleverness
    # this restructure exists to remove.
    LEGACY_HELP = "cogiteer.yaml has no 'servers' key, but its deployments carry inline server URLs — " \
                  "the format changed. Move 'protocol', 'server' (now 'url'), 'credential_env', " \
                  "'max_tokens_field' and any azure settings into a top-level 'servers:' entry, then " \
                  "point each deployment at it with 'server: <name>'. See docs/DESIGN.md."

    private def self.legacy?(root : YAML::Any) : Bool
      deployments = root["deployments"]?.try(&.as_h?)
      return false unless deployments

      deployments.each_value do |node|
        url = node["server"]?.try(&.as_s?)
        return true if url && url.includes?("://")
        return true if node["protocol"]?
      end
      false
    end

    private def self.parse_server(name : String, node : YAML::Any) : ServerConfig
      protocol_name = node["protocol"]?.try(&.as_s?) ||
                      raise ConfigError.new("server #{name.inspect} has no 'protocol'")
      url = node["url"]?.try(&.as_s?) ||
            raise ConfigError.new("server #{name.inspect} has no 'url'")

      ServerConfig.new(
        name: name,
        protocol: parse_protocol(name, protocol_name),
        url: url,
        credential_env: node["credential_env"]?.try(&.as_s?),
        azure: parse_azure(name, node["azure"]?),
        max_tokens_field: node["max_tokens_field"]?.try(&.as_s?).try { |field| parse_max_tokens_field(name, field) },
      )
    end

    private def self.parse_azure(name : String, node : YAML::Any?) : AzureAddressing?
      return if node.nil? || node.raw.nil?

      block = node.as_h? || raise ConfigError.new(
        "server #{name.inspect} has an 'azure' that is not a block — expected 'azure:' with an 'api_version' under it")
      version = block["api_version"]?.try(&.as_s?) ||
                raise ConfigError.new("server #{name.inspect} has an 'azure' block with no 'api_version'")

      AzureAddressing.new(version)
    end

    private def self.parse_deployment(name : String, node : YAML::Any,
                                      servers : Hash(String, ServerConfig)) : Deployment
      server_name = node["server"]?.try(&.as_s?) ||
                    raise ConfigError.new("deployment #{name.inspect} has no 'server'")
      model = node["model"]?.try(&.as_s?) ||
              raise ConfigError.new("deployment #{name.inspect} has no 'model'")

      server = servers[server_name]? || raise ConfigError.new(
        "deployment #{name.inspect} names server #{server_name.inspect}, which is not defined " \
        "— have: #{servers.keys.join(", ")}")

      Deployment.new(name: name, server: server, model: model,
        reasoning: parse_reasoning(name, node["reasoning"]?),
        reasoning_retention: parse_retention(name, node["reasoning_retention"]?))
    end

    # `low`, `medium`, `high`, `xhigh`, `max`, `none`, or a positive integer
    # token budget. Absent leaves the provider's own default alone, which is a
    # different thing from `none` — `none` asks the model not to think.
    #
    # **`off` is not a spelling here, on purpose.** YAML 1.1 reads a bare
    # `off` as boolean false, so `reasoning: off` would arrive as a bool and
    # fail confusingly. Rather than accept a quoted `"off"` and have two
    # spellings for one thing, there is one word — `none` — and a bare boolean
    # gets an error that says so.
    private def self.parse_reasoning(name : String, node : YAML::Any?) : Liaison::Reasoning::Request?
      return if node.nil? || node.raw.nil?

      unless node.as_bool?.nil?
        raise ConfigError.new("deployment #{name.inspect} has a boolean 'reasoning' — YAML reads a bare " \
                              "on/off/yes/no as a boolean; write 'none' to ask the model not to think")
      end

      if budget = node.as_i?
        return Liaison::Reasoning::Budget.new(budget) if budget > 0
        raise ConfigError.new("deployment #{name.inspect} has a 'reasoning' budget of #{budget} " \
                              "— must be positive, or 'none' to ask the model not to think")
      end

      level = node.as_s? || raise ConfigError.new(
        "deployment #{name.inspect} has a 'reasoning' that is neither a level nor a token budget")

      return Liaison::Reasoning::Off.new if level.downcase == "none"
      parse_effort(name, level)
    end

    # The rungs only. Split from `parse_reasoning` because that method already
    # decides between four shapes — absent, boolean, integer, string — before
    # it gets here, and the ladder is the part most likely to grow.
    private def self.parse_effort(name : String, level : String) : Liaison::Reasoning::Effort
      case level.downcase
      when "low"    then Liaison::Reasoning::Effort::Low
      when "medium" then Liaison::Reasoning::Effort::Medium
      when "high"   then Liaison::Reasoning::Effort::High
      when "xhigh"  then Liaison::Reasoning::Effort::XHigh
      when "max"    then Liaison::Reasoning::Effort::Max
      else
        raise ConfigError.new("deployment #{name.inspect} has unrecognised reasoning #{level.inspect} " \
                              "— expected low, medium, high, xhigh, max, none, or a token budget")
      end
    end

    # `all`, `completed_turns`, or `none`.
    #
    # The `none` here and the `none` under `reasoning` are different things —
    # this one drops reasoning blocks out of the *history* being replayed, that
    # one asks the model not to produce any. They share a word because both are
    # the honest word for their own key, and the keys are adjacent enough that
    # nobody reads one for the other.
    private def self.parse_retention(name : String, node : YAML::Any?) : Liaison::Capability::ReasoningRetention?
      return if node.nil? || node.raw.nil?

      mode = node.as_s? || raise ConfigError.new(
        "deployment #{name.inspect} has a 'reasoning_retention' that is not a string")

      case mode.downcase
      when "all"             then Liaison::Capability::ReasoningRetention::All
      when "completed_turns" then Liaison::Capability::ReasoningRetention::CompletedTurns
      when "none"            then Liaison::Capability::ReasoningRetention::None
      else
        raise ConfigError.new("deployment #{name.inspect} has unrecognised reasoning_retention #{mode.inspect} " \
                              "— expected all, completed_turns, or none")
      end
    end

    private def self.parse_protocol(name : String, protocol_name : String) : Liaison::ProtocolKind
      case protocol_name
      when "chat_completions" then Liaison::ProtocolKind::ChatCompletions
      when "responses"        then Liaison::ProtocolKind::Responses
      when "anthropic"        then Liaison::ProtocolKind::Anthropic
      when "gemini"           then Liaison::ProtocolKind::Gemini
      else
        raise ConfigError.new("server #{name.inspect} has unrecognised protocol #{protocol_name.inspect} " \
                              "— expected chat_completions, responses, anthropic, or gemini")
      end
    end

    private def self.parse_max_tokens_field(name : String,
                                            field : String) : Liaison::Protocol::ChatCompletions::Wire::MaxTokensField
      case field
      when "max_tokens"            then Liaison::Protocol::ChatCompletions::Wire::MaxTokensField::MaxTokens
      when "max_completion_tokens" then Liaison::Protocol::ChatCompletions::Wire::MaxTokensField::MaxCompletionTokens
      else
        raise ConfigError.new("server #{name.inspect} has unrecognised max_tokens_field #{field.inspect} " \
                              "— expected max_tokens or max_completion_tokens")
      end
    end

    def deployment(name : String) : Deployment
      deployments[name]? || raise ConfigError.new(
        "no deployment named #{name.inspect} in cogiteer.yaml — have: #{deployments.keys.join(", ")}")
    end

    # The *server* name is the `Server`'s own name, which is what keeps
    # `Liaison::Provider.for`'s vendor default working: a server the operator called
    # `anthropic` is treated as authentically Anthropic by the same comparison
    # every other caller relies on.
    #
    # This changed with the split, and the change is the right way round. It
    # used to be the deployment name, which meant `claude-haiku` and
    # `claude-sonnet` pointed at the same endpoint under two different vendor
    # identities. The vendor claim is a fact about the endpoint, so it now
    # follows the endpoint.
    def provider_for(name : String) : Liaison::Provider
      s = deployment(name).server
      server = Liaison::Server.new(s.name, s.url, s.credential)

      if azure = s.azure
        Liaison::Provider.for_azure(server, s.protocol, azure.api_version, max_tokens_field: s.max_tokens_field)
      else
        Liaison::Provider.for(server, s.protocol, max_tokens_field: s.max_tokens_field)
      end
    end
  end
end
