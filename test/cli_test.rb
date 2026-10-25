# frozen_string_literal: true

require "test_helper"

class CLITest < Minitest::Test
  include TestHelper

  def cli(*args, registry: nil, cwd: ROOT)
    out = StringIO.new
    err = StringIO.new
    code = GemlockGuard::CLI.run(args, out:, err:, cwd:, now: NOW, registry:)
    [code, out.string, err.string]
  end

  def test_help_version_and_checks
    assert_equal 0, cli("--help")[0]
    assert_match "usage: gemlock-guard", cli("-h")[1]
    assert_equal "gemlock-guard #{GemlockGuard::VERSION}\n", cli("--version")[1]
    assert_equal GemlockGuard::Checks::ALL.size, cli("--list-checks")[1].lines.size
  end

  def test_usage_errors
    {
      ["--nope"] => "unknown option --nope",
      ["--min-age"] => "--min-age needs a value",
      ["--min-age", "-1"] => "whole number of days",
      ["--format", "xml"] => 'unknown format "xml"',
      ["--fail-on", "critical"] => '--fail-on must be high, medium, low or none, got "critical"'
    }.each do |args, message|
      code, _, err = cli(*args)

      assert_equal 2, code, args.inspect
      assert_includes err, message
      assert_includes err, "usage:"
    end
  end

  def test_missing_paths
    code, _, err = cli("does/not/exist")

    assert_equal 2, code
    assert_match "No such file or directory", err
    assert_equal [2, "", "error: no Gemfile found\n"], cli("Rakefile")
  end

  def test_scans_this_repository_and_skips_fixtures
    code, out, = cli

    assert_equal 0, code
    assert_equal "No problems found.\n1 project(s), 0 finding(s): 0 high, 0 medium, 0 low\n", out
  end

  def test_fixtures_when_named
    code, out, = cli("test/fixtures")

    assert_equal 1, code
    assert_includes out, "test/fixtures/risky/Gemfile.lock:22  HIGH   GG001  remote http://gems.acme.internal/ (5 gem(s))"
    assert_includes out, "test/fixtures/nolock/Gemfile:1  HIGH   GG001"
    assert_includes out, "3 project(s), 15 finding(s): 6 high, 8 medium, 1 low"
  end

  def test_files_and_absolute_paths
    _, out, = cli("--fail-on", "none", File.join(FIXTURES, "nolock", "Gemfile"))

    assert_includes out, "\ntest/fixtures/nolock/Gemfile:4"
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Gemfile"), "source \"http://rubygems.org\"\n")

      assert_includes cli(dir)[1], "#{File.realpath(dir)}/Gemfile:1"
    end
    _, out, = cli("--fail-on", "none", "test/fixtures/clean/Gemfile.lock")

    assert_includes out, "1 project(s), 0 finding(s)"
    assert_equal 0, cli("--fail-on", "none", ".", cwd: File.join(FIXTURES, "risky"))[0]
    assert_includes cli(cwd: File.join(FIXTURES, "risky"))[1], "\nGemfile.lock:22"
  end

  def test_fail_on
    assert_equal 1, cli("--fail-on", "high", "test/fixtures/risky")[0]
    assert_equal 0, cli("--fail-on", "high", "test/fixtures/clean")[0]
    assert_equal 1, cli("--fail-on", "low", "test/fixtures/risky")[0]
  end

  def test_json
    data = JSON.parse(cli("--format", "json", "test/fixtures/risky")[1])

    assert_equal({ "high" => 4, "medium" => 8, "low" => 1 }, data["summary"])
    assert_equal %w[check severity target file line message help], data["findings"].first.keys
  end

  def test_markdown
    assert_includes cli("--format", "markdown", "test/fixtures/risky")[1], "### 🛑 gemlock-guard"
    assert_includes cli("--format", "markdown", "test/fixtures/clean")[1], "### ✅ gemlock-guard"
    gemfile = File.join(FIXTURES, "risky")
    out = cli("--format", "markdown", "--fail-on", "none", cwd: gemfile)[1]

    assert_includes out, "| medium | GG008 | `nokogirl@1.0.0` |"
  end

  def test_markdown_with_only_warnings
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Gemfile"), "source \"https://a.example\"\nsource \"https://b.example\"\n")

      assert_includes cli("--format", "markdown", cwd: dir)[1], "### ⚠️ gemlock-guard"
    end
  end

  def test_sarif
    sarif = JSON.parse(cli("--format", "sarif", "test/fixtures/risky")[1])
    run = sarif["runs"].first

    assert_equal "2.1.0", sarif["version"]
    assert_equal(GemlockGuard::Checks::ALL.keys, run["tool"]["driver"]["rules"].map { |r| r["id"] })
    assert_equal 13, run["results"].size
    assert_equal({ "uri" => "test/fixtures/risky/.bundle/config" },
                 run["results"].first["locations"].first["physicalLocation"]["artifactLocation"])
  end

  def test_report_files
    Dir.mktmpdir do |dir|
      sarif = File.join(dir, "out.sarif")
      markdown = File.join(dir, "out.md")
      code, out, = cli("--sarif-file", sarif, "--markdown-file", markdown, "test/fixtures/risky")

      assert_equal 1, code
      assert_includes out, "13 finding(s)"
      assert_equal 13, JSON.parse(File.read(sarif))["runs"].first["results"].size
      assert_includes File.read(markdown), "### 🛑 gemlock-guard"
    end
  end

  def test_online
    registry = FakeRegistry.new(versions: { "rack" => { ["3.2.7", "ruby"] => NOW - 3600 } },
                                specs: { "rack-3.2.7" => Gem::Specification.new })

    assert_includes cli("--online", "--min-age", "3", "test/fixtures/clean", registry:)[1], "GG006  rack@3.2.7 was released"
    # Without --online the registry is never asked.
    registry = FakeRegistry.new

    cli("test/fixtures/clean", registry:)

    assert_empty registry.calls
  end

  def test_gems_rb
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "gems.rb"), "source \"https://rubygems.org\"\n")
      File.write(File.join(dir, "gems.locked"), "GEM\n  remote: http://rubygems.org/\n  specs:\n    rack (3.0)\n")

      assert_includes cli(cwd: dir)[1], "gems.locked:2  HIGH   GG001"
    end
  end
end
