# frozen_string_literal: true

module GemlockGuard
  SEVERITIES = %w[high medium low].freeze
  RANK = { "high" => 3, "medium" => 2, "low" => 1 }.freeze

  # One problem found in a Gemfile, Gemfile.lock or .bundle/config.
  #
  # target is the gem (name@version) or the setting the finding is about.
  Finding = Data.define(:check, :severity, :target, :file, :line, :message, :help) do
    def initialize(check:, severity:, target:, file:, line:, message:, help: "")
      super
    end

    def rank = RANK.fetch(severity)
  end
end
