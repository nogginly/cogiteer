require "fsutils"
require "yaml"

module Cogiteer
  # The `toolkit:` table: how the tools behave once offered.
  #
  # ```
  # toolkit:
  #   grep:
  #     max_depth: 8
  #   fetch:
  #     allowed_hosts: ["docs.crystal-lang.org"]
  # ```
  #
  # Deserialised straight into `FsUtils::Tools::Config` rather than curated
  # under local key names. A curated subset would make every bound the shard
  # adds or renames a change here, plus a translation table between two files
  # that must be kept in step — and `Arguments` is the only other place this
  # project stands between itself and `fsutils`, where it exists to preserve
  # pass-through rather than to interpret.
  #
  # **The ownership line.** `cogiteer` decides whether a tool is offered —
  # `tools`, `web`, `--no-edit`, `max_tool_calls`. `fsutils` decides how it
  # behaves once offered. The one field this project drives, `reproducible`,
  # is overwritten by the caller after parsing, so a flag never loses silently
  # to a file.
  module Toolkit
    # Section name to the bounds it accepts, derived from the shard's own type
    # at compile time. Nothing here is written by hand, so a bound `fsutils`
    # adds is accepted the day the lock moves.
    #
    # A section is a field that converts to settings of its own, which is the
    # shape `FsUtils::Tools::Config` documents: sections mirror the tools, and
    # a section converts.
    SECTIONS = begin
      sections = {} of String => Array(String)
      {% for ivar in FsUtils::Tools::Config.instance_vars %}
        {% if ivar.type.has_method?("to_settings") %}
          sections[{{ ivar.name.stringify }}] = [
            {% for bound in ivar.type.instance_vars %}
              {{ bound.name.stringify }},
            {% end %}
          ] of String
        {% end %}
      {% end %}
      sections
    end

    # Top-level bounds that are not sections: `max_output_bytes`,
    # `reproducible`.
    TOP_LEVEL = begin
      names = [] of String
      {% for ivar in FsUtils::Tools::Config.instance_vars %}
        {% unless ivar.type.has_method?("to_settings") %}
          names << {{ ivar.name.stringify }}
        {% end %}
      {% end %}
      names
    end

    # Parses the table, or returns the shard's defaults when it is absent.
    #
    # Unknown keys raise rather than being ignored, which is where this
    # departs from `YAML::Serializable`'s own behaviour. A misspelled flag
    # under `defaults` is visible in what the CLI does; a misspelled bound is
    # not visible anywhere, because the tool goes on working at a limit nobody
    # chose.
    def self.parse(node : YAML::Any?) : FsUtils::Tools::Config
      return FsUtils::Tools::Config.new if node.nil? || node.raw.nil?

      table = node.as_h? || raise ConfigError.new(
        "'toolkit' is not a block — expected 'toolkit:' with sections such as 'grep' under it")

      table.each do |key, value|
        name = key.as_s? || raise ConfigError.new("'toolkit' has a non-name key #{key.raw.inspect}")
        check_section(name, value)
      end

      from_yaml(node)
    end

    private def self.check_section(name : String, value : YAML::Any) : Nil
      bounds = SECTIONS[name]?
      unless bounds
        return if TOP_LEVEL.includes?(name)
        raise ConfigError.new("'toolkit' has no '#{name}' — expected one of: #{known.join(", ")}")
      end

      inner = value.as_h? || raise ConfigError.new(
        "'toolkit.#{name}' is not a block — expected bounds such as '#{bounds.first}' under it")

      inner.each_key do |key|
        bound = key.as_s? || raise ConfigError.new("'toolkit.#{name}' has a non-name key #{key.raw.inspect}")
        next if bounds.includes?(bound)
        raise ConfigError.new("'toolkit.#{name}' has no '#{bound}' — expected one of: #{bounds.join(", ")}")
      end
    end

    # Re-raised as a `ConfigError` so a bad bound reads like every other
    # problem in this file, rather than as a Crystal type complaint naming a
    # line in a document the operator did not write.
    private def self.from_yaml(node : YAML::Any) : FsUtils::Tools::Config
      FsUtils::Tools::Config.from_yaml(node.to_yaml)
    rescue error : YAML::ParseException
      raise ConfigError.new("'toolkit' holds a value the toolkit refused: #{error.message}")
    end

    private def self.known : Array(String)
      (SECTIONS.keys.to_a + TOP_LEVEL).sort
    end
  end
end
