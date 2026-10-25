# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "rubygems/package"
require "stringio"
require "time"
require "uri"

module GemlockGuard
  # Raised when rubygems.org cannot be reached at all; the online check is
  # then skipped for the rest of the run.
  class Offline < StandardError; end

  # Reads release dates and gem metadata from rubygems.org.
  #
  # - GET /api/v1/versions/<gem>.json lists every non-yanked version with its
  #   created_at (https://guides.rubygems.org/rubygems-org-api/).
  # - For the few versions that turn out to be fresh, the .gem itself is
  #   downloaded and its metadata read with Gem::Package, the same way
  #   `gem install` reads it, to learn whether it builds a native extension.
  #   The abbreviated gemspecs under /quick/ leave `extensions` empty.
  #
  # Each gem is fetched once per run. Requests are spaced to stay under the
  # documented limit of 10 requests per second for the API
  # (https://guides.rubygems.org/rubygems-org-rate-limits/), and 429 / 5xx
  # responses are retried with backoff, honouring Retry-After.
  class Registry
    BASE = "https://rubygems.org"
    HOSTS = %w[rubygems.org www.rubygems.org index.rubygems.org].freeze
    NETWORK_ERRORS = [SocketError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError].freeze
    MAX_GEM_BYTES = 64 * 1024 * 1024

    Response = Struct.new(:code, :body, :headers, keyword_init: true) do
      def [](name) = headers.to_h[name.downcase]
    end

    def self.serves?(remote)
      HOSTS.include?(URI(remote.to_s).host.to_s.downcase)
    rescue URI::InvalidURIError
      false
    end

    # http, for tests, is called with a URI and returns a Response.
    def initialize(base: BASE, per_second: 8, retries: 2, timeout: 20, http: nil, sleeper: ->(s) { sleep(s) })
      @base = URI(base)
      @interval = 1.0 / per_second
      @retries = retries
      @timeout = timeout
      @http = http
      @sleep = sleeper
      @versions = {}
      @specs = {}
      @lock = Mutex.new
      @next_at = 0.0
    end

    # { [version, platform] => Time } for a gem, or nil when rubygems.org does not know it.
    def versions(name)
      cached(@versions, name) do
        body = get(@base + "/api/v1/versions/#{escape(name)}.json")
        next nil if body.nil?

        JSON.parse(body).to_h do |v|
          [[v["number"], v["platform"] || "ruby"], Time.iso8601(v["created_at"])]
        end
      end
    end

    # The Gem::Specification inside one released .gem, or nil when it is not there.
    def spec(name, version, platform)
      file = platform.nil? || platform == "ruby" ? "#{name}-#{version}" : "#{name}-#{version}-#{platform}"
      cached(@specs, file) do
        body = get(@base + "/gems/#{escape(file)}.gem")
        next nil if body.nil?

        Gem::Package.new(StringIO.new(body)).spec
      end
    end

    private

    def cached(store, key)
      @lock.synchronize { return store[key] if store.key?(key) }
      value = yield
      @lock.synchronize { store[key] = value }
    end

    def escape(name) = URI.encode_www_form_component(name)

    def throttle
      wait = @lock.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        start = [@next_at, now].max
        @next_at = start + @interval
        start - now
      end
      @sleep.call(wait) if wait.positive?
    end

    def get(uri, redirects: 3)
      attempt = 0
      loop do
        throttle
        res = request(uri)
        case res.code.to_i
        when 200 then return res.body
        when 404 then return nil
        when 301, 302, 303, 307, 308
          raise "GET #{uri}: too many redirects" if redirects.zero? || res["location"].nil?

          return get(uri + res["location"], redirects: redirects - 1)
        when 429, 500..599
          raise "GET #{uri}: HTTP #{res.code}" if attempt >= @retries

          @sleep.call(retry_after(res) || (0.5 * (2**attempt)))
          attempt += 1
        else
          raise "GET #{uri}: HTTP #{res.code}"
        end
      end
    end

    def retry_after(res)
      v = res["retry-after"]
      v&.match?(/\A\d+\z/) ? [v.to_i, 30].min : nil
    end

    def request(uri)
      raise "refusing to fetch #{uri} without TLS" unless uri.scheme == "https"
      return @http.call(uri) if @http

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: @timeout, read_timeout: @timeout) do |h|
        res = h.request_get(uri.request_uri, "User-Agent" => "gemlock-guard/#{VERSION}")
        body = res.body.to_s
        raise "GET #{uri}: response larger than #{MAX_GEM_BYTES} bytes" if body.bytesize > MAX_GEM_BYTES

        Response.new(code: res.code, body:, headers: res.each_header.to_h)
      end
    rescue *NETWORK_ERRORS => e
      raise Offline, "#{uri.host}: #{e.message}"
    end
  end
end
