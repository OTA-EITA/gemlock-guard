# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  skip "/test/"
  coverage(:line) do
    minimum 95
    minimum 85, per: :file
  end
  coverage(:branch) { minimum 85 }
end

require "minitest/autorun"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require_relative "../lib/gemlock_guard"

module TestHelper
  FIXTURES = File.expand_path("fixtures", __dir__)
  ROOT = File.expand_path("..", __dir__)
  NOW = Time.utc(2026, 10, 25, 12)

  # A Project built from strings, in a temporary directory outside any git repository.
  def project(gemfile: "source \"https://rubygems.org\"\n", lock: nil, config: nil, dir: Dir.tmpdir)
    GemlockGuard::Project.new(
      dir:,
      gemfile: GemlockGuard::Gemfile.new(gemfile),
      lockfile: (GemlockGuard::Lockfile.new(lock) if lock),
      bundle_config: (GemlockGuard::BundleConfig.new(config) if config)
    )
  end

  def run_checks(project, **)
    GemlockGuard::Checks.new(now: NOW, **).run(project)
  end

  def ids(findings) = findings.map(&:check)

  def lock_with(specs, remote: "https://rubygems.org/")
    "GEM\n  remote: #{remote}\n  specs:\n#{specs.map { |s| "    #{s}\n" }.join}\nPLATFORMS\n  ruby\n"
  end
end

# A stand-in for rubygems.org: release dates and gemspecs from plain hashes.
class FakeRegistry
  attr_reader :calls

  def initialize(versions: {}, specs: {}, error: nil)
    @versions = versions
    @specs = specs
    @error = error
    @calls = []
  end

  def versions(name)
    @calls << name
    raise @error if @error

    @versions[name]
  end

  def spec(name, version, platform)
    @calls << "#{name}-#{version}-#{platform}"
    value = @specs["#{name}-#{version}"]
    raise value if value.is_a?(Exception)

    value
  end
end
