# frozen_string_literal: true

module GemlockGuard
  # Reads the project's .bundle/config, written by `bundle config set --local`.
  #
  # Bundler stores it as flat YAML (BUNDLE_KEY: "value"); a line scan reads
  # that without parsing arbitrary YAML.
  class BundleConfig
    Setting = Struct.new(:key, :value, :line, keyword_init: true)

    attr_reader :path, :settings

    def initialize(text, path = ".bundle/config")
      @path = path
      @settings = {}
      text.each_line.with_index(1) do |raw, lineno|
        m = raw.match(/\A(BUNDLE_[A-Z0-9_]+):\s*(?:"([^"]*)"|'([^']*)'|(\S+))/)
        next unless m

        @settings[m[1]] = Setting.new(key: m[1], value: m[2] || m[3] || m[4], line: lineno)
      end
    end

    def [](key) = settings[key]
  end
end
