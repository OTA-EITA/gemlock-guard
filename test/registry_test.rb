# frozen_string_literal: true

require "test_helper"

class RegistryTest < Minitest::Test
  R = GemlockGuard::Registry

  def response(code, body = "", headers = {}) = R::Response.new(code: code.to_s, body:, headers:)

  def registry(&handler)
    @slept = []
    @requests = []
    http = lambda do |uri|
      @requests << uri.to_s
      handler.call(uri)
    end
    R.new(http:, sleeper: ->(s) { @slept << s }, per_second: 1000)
  end

  def test_serves
    assert R.serves?("https://rubygems.org/")
    assert R.serves?("https://index.rubygems.org")
    refute R.serves?("https://gems.example.com/")
    refute R.serves?("not a url ::")
  end

  def test_versions_are_cached
    body = JSON.generate([{ "number" => "1.0", "platform" => "ruby", "created_at" => "2026-10-20T00:00:00.000Z" },
                          { "number" => "1.0", "platform" => "java", "created_at" => "2026-10-21T00:00:00.000Z" }])
    reg = registry { response(200, body) }

    assert_equal Time.utc(2026, 10, 21), reg.versions("a b")[%w[1.0 java]]
    reg.versions("a b")

    assert_equal ["https://rubygems.org/api/v1/versions/a+b.json"], @requests
  end

  def test_not_found
    reg = registry { response(404) }

    assert_nil reg.versions("nope")
    assert_nil reg.spec("nope", "1.0", nil)
  end

  def test_retries_with_retry_after_then_gives_up
    codes = [429, 503, 200]
    reg = registry { response(codes.shift, "[]", "retry-after" => "3") }

    assert_empty reg.versions("a")
    assert_equal([3, 3], @slept.select { |s| s >= 1 })

    reg = registry { response(500) }
    error = assert_raises(RuntimeError) { reg.versions("b") }

    assert_match "HTTP 500", error.message
    assert_equal([0.5, 1.0], @slept.select { |s| s >= 0.5 })
  end

  def test_other_errors
    assert_raises(RuntimeError) { registry { response(403) }.versions("a") }
  end

  def test_redirects
    reg = registry do |uri|
      uri.host == "rubygems.org" ? response(302, "", "location" => "https://cdn.example/x.json") : response(200, "[]")
    end

    assert_empty reg.versions("a")
    assert_equal "https://cdn.example/x.json", @requests.last
    assert_raises(RuntimeError) { registry { response(301) }.versions("a") }
    assert_raises(RuntimeError) { registry { response(301, "", "location" => "/again") }.versions("a") }
  end

  def test_refuses_plain_http
    reg = R.new(base: "http://rubygems.org", http: ->(_) { flunk })

    assert_raises(RuntimeError) { reg.versions("a") }
  end

  def test_spec_reads_the_gem_package
    gem = build_gem
    reg = registry { |uri| response(uri.path.end_with?("demo-1.0.0-x86_64-linux.gem") ? 200 : 404, gem) }
    spec = reg.spec("demo", "1.0.0", "x86_64-linux")

    assert_equal ["ext/extconf.rb"], spec.extensions
    assert_nil reg.spec("demo", "1.0.0", "ruby")
  end

  def test_network_errors_mean_offline
    reg = R.new(base: "https://127.0.0.1:1", timeout: 2)

    error = assert_raises(GemlockGuard::Offline) { reg.versions("a") }
    assert_match "127.0.0.1", error.message
  end

  def test_real_requests_go_through_net_http
    skip "set GEMLOCK_GUARD_NETWORK=1 to query rubygems.org" unless ENV["GEMLOCK_GUARD_NETWORK"]

    assert_operator R.new.versions("rake").size, :>, 10
  end

  private

  def build_gem
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("ext")
        File.write("ext/extconf.rb", "")
        spec = Gem::Specification.new do |s|
          s.name = "demo"
          s.version = "1.0.0"
          s.summary = "demo"
          s.authors = ["x"]
          s.files = ["ext/extconf.rb"]
          s.extensions = ["ext/extconf.rb"]
        end
        file = Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) { Gem::Package.build(spec) }
        File.binread(file)
      end
    end
  end
end
