# frozen_string_literal: true

module GemlockGuard
  # Scans a Gemfile line by line for the declarations the checks need.
  #
  # A Gemfile is Ruby code, but evaluating it would run that code, so this only
  # recognises the common literal forms: `source "url"` (global),
  # `source "url" do` (scoped to a block) and git URLs given to `gem`.
  class Gemfile
    Source = Struct.new(:url, :line, :global, keyword_init: true)
    GitGem = Struct.new(:name, :url, :line, keyword_init: true)

    SOURCE = /\A\s*source[\s(]+(?<q>["'])(?<url>[^"']+)\k<q>(?<rest>.*)\z/
    GIT_GEM = /\A\s*gem[\s(]+(?<q>["'])(?<name>[^"']+)\k<q>.*\bgit(?::|["']?\s*=>)\s*(?<q2>["'])(?<url>[^"']+)\k<q2>/

    attr_reader :path, :sources, :git_gems

    def initialize(text, path = "Gemfile")
      @path = path
      @sources = []
      @git_gems = []
      text.each_line.with_index(1) do |raw, lineno|
        line = raw.rstrip
        next if line.lstrip.start_with?("#")

        if (m = line.match(SOURCE))
          rest = m[:rest].sub(/\s#.*\z/, "")
          # `do ... end`, or a brace block right after the URL (not a hash of options).
          scoped = rest.match?(/\bdo\b/) || rest.match?(/\A\)?\s*\{/)
          @sources << Source.new(url: m[:url], line: lineno, global: !scoped)
        elsif (m = line.match(GIT_GEM))
          @git_gems << GitGem.new(name: m[:name], url: m[:url], line: lineno)
        end
      end
    end

    def global_sources = sources.select(&:global)
  end
end
