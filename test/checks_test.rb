# frozen_string_literal: true

require "test_helper"

class ChecksTest < Minitest::Test
  include TestHelper

  def test_risky_fixture
    dir = File.join(FIXTURES, "risky")
    findings = run_checks(GemlockGuard::Project.load(dir, "risky"))

    assert_equal %w[GG007 GG007 GG001 GG001 GG002 GG003 GG004 GG002 GG008 GG005 GG008 GG005 GG003], ids(findings)
    assert_equal (%w[high] * 4) + (%w[medium] * 8) + %w[low], findings.map(&:severity)
    assert_equal "risky/Gemfile.lock", findings[2].file
  end

  def test_clean_fixture
    assert_empty run_checks(GemlockGuard::Project.load(File.join(FIXTURES, "clean"), "."))
  end

  def test_plain_http_from_the_gemfile_only_without_a_lockfile
    gemfile = "source \"http://rubygems.org\"\ngem \"a\", git: \"git://example.com/a.git\"\ngem \"b\", git: \"https://example.com/b.git\"\n"
    findings = run_checks(project(gemfile:))

    assert_equal([%w[GG001 1], %w[GG001 2]], findings.map { |f| [f.check, f.line.to_s] })
    assert_match "plain HTTP", findings[0].message
    assert_match "git:// protocol", findings[1].message
    # With a lockfile, only what Bundler locked is checked.
    assert_empty run_checks(project(gemfile:, lock: lock_with([])))
  end

  def test_scoped_sources_are_not_ambiguous
    gemfile = "source \"https://rubygems.org\"\nsource \"https://gems.example.com\" do\n  gem \"x\"\nend\n"

    assert_empty run_checks(project(gemfile:))
  end

  def test_git_refs
    findings = git_findings({ "ref" => "0123456789abcdef0123456789abcdef01234567" })

    assert_empty findings
    assert_equal ["low"], git_findings({ "ref" => "0123abc" }).map(&:severity)
    assert_match "abbreviated ref", git_findings({ "ref" => "0123abc" }).first.message
    assert_match "branch stable", git_findings({ "ref" => "stable" }).first.message
    assert_match "the default branch", git_findings({}).first.message
    assert_equal ["medium"], git_findings({ "branch" => "main" }).map(&:severity)
  end

  def test_git_source_without_specs_is_ignored
    lock = "GIT\n  remote: https://example.com/x.git\n  revision: abc\n  branch: main\n  specs:\n"

    assert_empty run_checks(project(lock:))
  end

  def test_many_gems_from_one_git_source_are_summarised
    specs = %w[actioncable actionpack actionview activejob activesupport].map { |n| "    #{n} (8.2.0)\n" }.join
    lock = "GIT\n  remote: https://github.com/rails/rails.git\n  revision: abc\n  branch: main\n  specs:\n#{specs}"

    assert_match "actioncable, actionpack, actionview and 2 more from", run_checks(project(lock:)).first.message
  end

  def test_path_gems
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, ".git"))
      app = File.join(root, "apps", "web")
      FileUtils.mkdir_p(app)
      inside = path_lock("../../gems/shared")
      outside = path_lock("../../../elsewhere")

      assert_empty run_checks(project(lock: path_lock("."), dir: app))
      assert_empty run_checks(project(lock: inside, dir: app))
      assert_equal ["GG004"], ids(run_checks(project(lock: outside, dir: app)))
      assert_equal ["GG004"], ids(run_checks(project(lock: path_lock("/opt/gems/x"), dir: app)))
    end
  end

  def test_checksums
    lock = "#{lock_with(["a (1.0)", "b (2.0)", "c (3.0-x86_64-linux)"])}\nCHECKSUMS\n  a (1.0) sha256=aa\n  b (2.0)\n"
    findings = run_checks(project(lock:))

    assert_equal ["c-3.0-x86_64-linux is missing from the CHECKSUMS section", "b-2.0 has an empty CHECKSUMS entry"],
                 findings.map(&:message)
    # No CHECKSUMS section at all is Bundler's default before 4.0, not a finding.
    assert_empty run_checks(project(lock: lock_with(["a (1.0)"])))
  end

  def test_typosquats_are_reported_once_and_not_for_path_gems
    lock = "PATH\n  remote: .\n  specs:\n    nokogirl (0.1)\n\n#{lock_with(["sidekik (7.0)", "sidekik (7.0-java)"])}"

    assert_equal ["sidekik looks like a typo of the popular gem sidekiq"], run_checks(project(lock:)).map(&:message)
  end

  def test_bundle_config
    config = "---\nBUNDLE_SSL_VERIFY_MODE: \"1\"\nBUNDLE_DISABLE_CHECKSUM_VALIDATION: \"false\"\n"

    assert_empty run_checks(project(config:))
    assert_equal 2, run_checks(project(config: config.tr("1", "0").sub("false", "true"))).size
  end

  def test_fresh_versions
    registry = FakeRegistry.new(
      versions: {
        "fresh" => { ["1.0.0", "ruby"] => NOW - 3600 },
        "native" => { ["2.0.0", "ruby"] => NOW - (2 * 86_400), ["2.0.0", "x86_64-linux"] => NOW - (2 * 86_400) },
        "plugin" => { ["1.0.0", "ruby"] => NOW - 86_400 },
        "old" => { ["1.0.0", "ruby"] => NOW - (30 * 86_400) },
        "java-only" => { ["1.0.0", "java"] => NOW - 3600 }
      },
      specs: {
        "native-2.0.0" => Gem::Specification.new { |s| s.extensions = ["ext/extconf.rb"] },
        "plugin-1.0.0" => Gem::Specification.new { |s| s.files = ["lib/rubygems_plugin.rb"] },
        "fresh-1.0.0" => Gem::Specification.new
      }
    )
    lock = lock_with(["fresh (1.0.0)", "native (2.0.0)", "native (2.0.0-x86_64-linux)", "plugin (1.0.0)",
                      "old (1.0.0)", "unknown (1.0.0)", "java-only (1.0.0-java)"])
    findings = run_checks(project(lock:), registry:)

    assert_equal([["native@2.0.0", "high"], ["plugin@1.0.0", "high"], ["fresh@1.0.0", "medium"], ["java-only@1.0.0", "medium"]],
                 findings.map { |f| [f.target, f.severity] })
    assert_match "released less than a day ago", findings[2].message
    assert_match "released 2 day(s) ago and builds a native extension", findings[0].message
    assert_match "ships a RubyGems plugin", findings[1].message
    assert_includes registry.calls, "native-2.0.0-"
  end

  def test_min_age
    registry = FakeRegistry.new(versions: { "a" => { ["1.0", "ruby"] => NOW - (10 * 86_400) } })

    assert_empty run_checks(project(lock: lock_with(["a (1.0)"])), registry:)
    assert_equal ["GG006"], ids(run_checks(project(lock: lock_with(["a (1.0)"])), registry:, min_age: 14))
  end

  def test_private_remotes_are_not_queried
    registry = FakeRegistry.new

    run_checks(project(lock: lock_with(["a (1.0)"], remote: "https://gems.example.com/")), registry:)

    assert_empty registry.calls
  end

  def test_offline
    warnings = []
    registry = FakeRegistry.new(error: GemlockGuard::Offline.new("rubygems.org: getaddrinfo failed"))
    checks = GemlockGuard::Checks.new(now: NOW, registry:, warn: ->(m) { warnings << m })
    lock = lock_with(["a (1.0)", "b (1.0)"])

    assert_empty checks.run(project(lock:))
    assert_empty checks.run(project(lock:))
    assert_equal 1, warnings.size
    assert_match "could not be reached", warnings.first
  end

  def test_registry_errors_are_warnings
    warnings = []
    registry = FakeRegistry.new(error: RuntimeError.new("HTTP 503"))
    checks = GemlockGuard::Checks.new(now: NOW, registry:, warn: ->(m) { warnings << m })

    assert_empty checks.run(project(lock: lock_with(["a (1.0)"])))
    assert_match "could not check 1 gem(s): a (HTTP 503)", warnings.first
  end

  def test_unreadable_metadata_keeps_the_finding_at_medium
    warnings = []
    registry = FakeRegistry.new(versions: { "a" => { ["1.0", "ruby"] => NOW } },
                                specs: { "a-1.0" => RuntimeError.new("bad gem") })
    checks = GemlockGuard::Checks.new(now: NOW, registry:, warn: ->(m) { warnings << m })

    assert_equal ["medium"], checks.run(project(lock: lock_with(["a (1.0)"]))).map(&:severity)
    assert_match "could not read the metadata of a-1.0", warnings.first
  end

  private

  def git_findings(options)
    opts = options.map { |k, v| "  #{k}: #{v}\n" }.join
    lock = "GIT\n  remote: https://github.com/acme/x.git\n  revision: abc\n#{opts}  specs:\n    x (1.0)\n"
    run_checks(project(lock:))
  end

  def path_lock(remote) = "PATH\n  remote: #{remote}\n  specs:\n    x (0.1)\n"
end
