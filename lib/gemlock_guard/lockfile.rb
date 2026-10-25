# frozen_string_literal: true

module GemlockGuard
  # Reads Gemfile.lock as text, the way Bundler's LockfileParser splits it,
  # without loading Bundler or evaluating anything.
  #
  # Sections start at column 0 (GEM, GIT, PATH, PLUGIN SOURCE, PLATFORMS,
  # DEPENDENCIES, CHECKSUMS, RUBY VERSION, BUNDLED WITH). Source sections hold
  # "  key: value" options and, after "  specs:", one gem per 4-space line.
  class Lockfile
    SOURCE_TYPES = ["GEM", "GIT", "PATH", "PLUGIN SOURCE"].freeze
    # Same shape as Bundler::LockfileParser::NAME_VERSION.
    NAME_VERSION = /\A( {2}| {4}| {6})(?! )(.*?)(?: \(([^-]*)(?:-(.*))?\))?(!)?(?: ([^ ]+))?\z/

    # A GEM, GIT, PATH or PLUGIN SOURCE section.
    Source = Struct.new(:type, :line, :options, :option_lines, :specs, keyword_init: true) do
      def remotes = Array(options["remote"])
      def remote = remotes.first
      def registry? = type == "GEM"
    end

    # A locked gem: one line under "  specs:".
    Spec = Struct.new(:name, :version, :platform, :line, :source, keyword_init: true) do
      def full_name = platform ? "#{name}-#{version}-#{platform}" : "#{name}-#{version}"
      def id = "#{name}@#{version}"
    end

    # A CHECKSUMS entry; checksums is empty when Bundler wrote the gem without one.
    Checksum = Struct.new(:full_name, :checksums, :line, keyword_init: true)

    attr_reader :path, :sources, :checksums, :platforms, :bundled_with

    def initialize(text, path = "Gemfile.lock")
      @path = path
      @sources = []
      @checksums = nil
      @platforms = []
      @bundled_with = nil
      parse(text)
    end

    def specs = sources.flat_map(&:specs)

    # True when the lockfile has a CHECKSUMS section (Bundler 2.6+ with
    # lockfile_checksums, the default for new lockfiles since Bundler 4.0).
    def checksums? = !checksums.nil?

    private

    def parse(text)
      section = nil
      source = nil
      in_specs = false
      text.each_line.with_index(1) do |raw, lineno|
        line = raw.chomp.delete_suffix("\r")
        next if line.strip.empty?

        if line.match?(/\A\S/)
          section = line.strip
          source = nil
          in_specs = false
          if SOURCE_TYPES.include?(section)
            source = Source.new(type: section, line: lineno, options: {}, option_lines: {}, specs: [])
            @sources << source
          elsif section == "CHECKSUMS"
            @checksums = {}
          end
          next
        end

        if source
          in_specs = parse_source_line(source, line, lineno, in_specs)
        elsif section == "CHECKSUMS"
          parse_checksum(line, lineno)
        elsif section == "PLATFORMS"
          @platforms << line.strip
        elsif section == "BUNDLED WITH"
          @bundled_with = line.strip
        end
      end
    end

    def parse_source_line(source, line, lineno, in_specs)
      return true if line == "  specs:"

      if !in_specs && (m = line.match(/\A {2}([a-z_]+): (.*)\z/i))
        key = m[1]
        value = m[2]
        source.options[key] = source.options.key?(key) ? [*source.options[key], value] : value
        (source.option_lines[key] ||= []) << lineno
        return false
      end

      m = line.match(NAME_VERSION)
      if in_specs && m && m[1].size == 4 && m[3]
        source.specs << Spec.new(name: m[2], version: m[3], platform: m[4], line: lineno, source:)
      end
      in_specs
    end

    def parse_checksum(line, lineno)
      m = line.match(NAME_VERSION)
      return unless m && m[1].size == 2 && m[3]

      full_name = m[4] ? "#{m[2]}-#{m[3]}-#{m[4]}" : "#{m[2]}-#{m[3]}"
      @checksums[full_name] = Checksum.new(full_name:, checksums: m[6].to_s.split(","), line: lineno)
    end
  end
end
