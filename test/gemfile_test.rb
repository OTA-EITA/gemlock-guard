# frozen_string_literal: true

require "test_helper"

class GemfileTest < Minitest::Test
  def test_global_and_scoped_sources
    gemfile = GemlockGuard::Gemfile.new(<<~RUBY)
      source "https://rubygems.org" # do not change
      source('https://gems.example.com') do
        gem "private"
      end
      source "https://other.example.com" do; end
      source "https://legacy.example.com", { cooldown: 0 }
      # source "http://commented.example.com"
    RUBY

    assert_equal ["https://rubygems.org", "https://gems.example.com", "https://other.example.com",
                  "https://legacy.example.com"], gemfile.sources.map(&:url)
    assert_equal [1, 6], gemfile.global_sources.map(&:line)
  end

  def test_git_gems
    gemfile = GemlockGuard::Gemfile.new(<<~RUBY)
      gem "a", git: "git://example.com/a.git"
      gem("b", :git => 'http://example.com/b.git', branch: "main")
      gem "c", github: "acme/c"
      gem "d", "~> 1.0"
    RUBY

    assert_equal([%w[a git://example.com/a.git], %w[b http://example.com/b.git]], gemfile.git_gems.map { |g| [g.name, g.url] })
  end
end
