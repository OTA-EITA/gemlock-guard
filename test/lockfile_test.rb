# frozen_string_literal: true

require "test_helper"

class LockfileTest < Minitest::Test
  LOCK = <<~LOCK
    GIT
      remote: https://github.com/rails/rails.git
      revision: 0123456789abcdef0123456789abcdef01234567
      branch: main
      specs:
        actionpack (8.2.0.alpha)
          rack (>= 2.2.4)
        rails (8.2.0.alpha)

    GEM
      remote: https://rubygems.org/
      remote: https://gems.example.com/
      specs:
        nokogiri (1.18.0)
          racc (~> 1.4)
        nokogiri (1.18.0-x86_64-linux-gnu)
          racc (~> 1.4)
        racc (1.8.1)

    PLATFORMS
      ruby
      x86_64-linux-gnu

    DEPENDENCIES
      nokogiri
      rails!

    CHECKSUMS
      actionpack (8.2.0.alpha)
      nokogiri (1.18.0) sha256=abc
      nokogiri (1.18.0-x86_64-linux-gnu) sha256=def,md5=xyz
      racc (1.8.1)

    BUNDLED WITH
       4.0.23
  LOCK

  def setup
    @lock = GemlockGuard::Lockfile.new(LOCK, "app/Gemfile.lock")
  end

  def test_sources_and_options
    git, gem = @lock.sources

    assert_equal %w[GIT GEM], @lock.sources.map(&:type)
    assert_equal "main", git.options["branch"]
    assert_equal 1, git.line
    assert_equal ["https://rubygems.org/", "https://gems.example.com/"], gem.remotes
    assert_equal [11, 12], gem.option_lines["remote"]
    assert_predicate gem, :registry?
    refute_predicate git, :registry?
  end

  def test_specs_skip_dependency_lines
    assert_equal %w[actionpack rails nokogiri nokogiri racc], @lock.specs.map(&:name)
    native = @lock.specs[3]

    assert_equal "x86_64-linux-gnu", native.platform
    assert_equal "nokogiri-1.18.0-x86_64-linux-gnu", native.full_name
    assert_equal "nokogiri@1.18.0", native.id
    assert_equal 16, native.line
  end

  def test_checksums_platforms_and_bundler_version
    assert_predicate @lock, :checksums?
    assert_equal %w[sha256=def md5=xyz], @lock.checksums["nokogiri-1.18.0-x86_64-linux-gnu"].checksums
    assert_empty @lock.checksums["racc-1.8.1"].checksums
    assert_equal %w[ruby x86_64-linux-gnu], @lock.platforms
    assert_equal "4.0.23", @lock.bundled_with
  end

  def test_windows_line_endings_and_no_checksums
    lock = GemlockGuard::Lockfile.new(LOCK.split("\nCHECKSUMS").first.gsub("\n", "\r\n"))

    refute_predicate lock, :checksums?
    assert_equal "main", lock.sources.first.options["branch"]
    assert_equal 5, lock.specs.size
  end
end
