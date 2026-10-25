# frozen_string_literal: true

require "json"

module GemlockGuard
  # Renders findings as text, JSON, Markdown or SARIF 2.1.0.
  module Report
    FORMATS = %w[text json markdown sarif].freeze
    LEVEL = { "high" => "error", "medium" => "warning", "low" => "note" }.freeze
    SCORE = { "high" => "8.0", "medium" => "5.0", "low" => "2.0" }.freeze

    module_function

    def render(findings, format, projects)
      case format
      when "json" then "#{JSON.pretty_generate(findings: findings.map(&:to_h), summary: counts(findings))}\n"
      when "markdown" then markdown(findings, projects)
      when "sarif" then "#{JSON.pretty_generate(sarif(findings))}\n"
      else text(findings, projects)
      end
    end

    def counts(findings)
      SEVERITIES.to_h { |s| [s.to_sym, findings.count { |f| f.severity == s }] }
    end

    def summary(findings, projects)
      c = counts(findings)
      "#{projects} project(s), #{findings.size} finding(s): #{c[:high]} high, #{c[:medium]} medium, #{c[:low]} low"
    end

    def text(findings, projects)
      lines = findings.map { |f| format("%s:%d  %-6s %s  %s", f.file, f.line, f.severity.upcase, f.check, f.message) }
      [*lines, lines.empty? ? "No problems found." : "", summary(findings, projects), ""].join("\n")
    end

    def markdown(findings, projects)
      icon = if findings.any? { |f| f.severity == "high" } then "🛑"
             elsif findings.any? then "⚠️"
             else "✅"
             end
      out = ["### #{icon} gemlock-guard", "", summary(findings, projects), ""]
      unless findings.empty?
        esc = ->(s) { s.gsub("|", "\\|") }
        out << "| Severity | Check | Target | Problem | What to do |" << "|---|---|---|---|---|"
        findings.each do |f|
          out << "| #{f.severity} | #{f.check} | `#{esc.call(f.target)}` | #{esc.call(f.message)} | #{esc.call(f.help)} |"
        end
      end
      "#{out.join("\n")}\n"
    end

    def sarif(findings)
      rules = Checks::ALL.map do |id, (severity, title, description)|
        {
          id:, name: title,
          shortDescription: { text: title }, fullDescription: { text: description },
          defaultConfiguration: { level: LEVEL.fetch(severity) },
          properties: { tags: %w[security bundler supply-chain], "security-severity": SCORE.fetch(severity) }
        }
      end
      results = findings.map do |f|
        {
          ruleId: f.check, level: LEVEL.fetch(f.severity),
          message: { text: f.help.empty? ? f.message : "#{f.message}. #{f.help}" },
          locations: [{ physicalLocation: { artifactLocation: { uri: f.file }, region: { startLine: f.line } } }]
        }
      end
      {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        version: "2.1.0",
        runs: [{
          tool: { driver: { name: "gemlock-guard", version: VERSION,
                            informationUri: "https://github.com/OTA-EITA/gemlock-guard", rules: } },
          results:
        }]
      }
    end
  end
end
