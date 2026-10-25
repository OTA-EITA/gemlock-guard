# frozen_string_literal: true

module GemlockGuard
  # The checks, run against one Project.
  class Checks
    # id => [severity, title, description]
    ALL = {
      "GG001" => ["high", "Plain HTTP source",
                  "A gem source or git repository is fetched over http:// or git://, so its contents can be swapped in transit."],
      "GG002" => ["medium", "Ambiguous gem source",
                  "Several global sources, or one lockfile GEM section with several remotes: any of them can supply " \
                  "any gem, which is how dependency confusion works."],
      "GG003" => ["medium", "Git gem on a moving ref",
                  "A gem comes from a git branch, so `bundle update` takes whatever was pushed last; low for tags."],
      "GG004" => ["medium", "Path gem outside the repository",
                  "A gem is loaded from a directory outside this repository, so what gets installed depends on the machine."],
      "GG005" => ["medium", "Missing checksum",
                  "The lockfile records checksums, but a gem from a registry has none, so a tampered package goes unnoticed."],
      "GG006" => ["medium", "Freshly released",
                  "The locked version was released less than the cooldown period ago (--online); " \
                  "high when it builds a native extension or ships a RubyGems plugin, which run code during install."],
      "GG007" => ["high", "Verification disabled in .bundle/config",
                  "The project's Bundler config turns off TLS certificate checks or gem checksum validation."],
      "GG008" => ["medium", "Possible typosquat", "A gem name is one typo away from a popular gem."]
    }.freeze

    INSECURE = %r{\A(?:http|git)://}i

    def initialize(min_age: 7, now: Time.now, registry: nil, threads: 4, warn: ->(_) {})
      @min_age = min_age
      @now = now
      @registry = registry
      @threads = threads
      @warn = warn
      @offline = false
    end

    def run(project)
      @out = []
      @project = project
      lock = project.lockfile
      check_gemfile(project.gemfile, lock)
      check_lockfile(lock) if lock
      check_bundle_config(project.bundle_config) if project.bundle_config
      check_freshness(lock) if lock && @registry
      @out.sort_by { |f| [-f.rank, f.file, f.line, f.check] }
    end

    private

    def add(check, target, file, line, message, help, severity = nil)
      @out << Finding.new(check:, severity: severity || ALL.fetch(check)[0], target:, file:, line:, message:, help:)
    end

    def check_gemfile(gemfile, lock)
      gemfile.global_sources.drop(1).each do |s|
        add("GG002", s.url, gemfile.path, s.line,
            "the Gemfile has #{gemfile.global_sources.size} global sources: any of them may supply any gem",
            'Keep one global source and put the other gems in a `source "..." do` block.')
      end
      # With a lockfile, transport is checked on what Bundler actually locked.
      return if lock

      gemfile.sources.each do |s|
        insecure(s.url, gemfile.path, s.line, "source #{s.url}") if s.url.match?(INSECURE)
      end
      gemfile.git_gems.each do |g|
        insecure(g.url, gemfile.path, g.line, "#{g.name} from #{g.url}") if g.url.match?(INSECURE)
      end
    end

    def insecure(url, file, line, what)
      git = url.downcase.start_with?("git://")
      add("GG001", url, file, line,
          "#{what} is fetched over #{git ? "the unauthenticated git:// protocol" : "plain HTTP"}",
          "Use https:// so the gems cannot be swapped in transit.")
    end

    def check_lockfile(lock)
      lock.sources.each do |source|
        check_transport(lock, source)
        check_remotes(lock, source) if source.registry?
        check_git(lock, source) if source.type == "GIT"
        check_path(lock, source) if source.type == "PATH"
      end
      check_checksums(lock) if lock.checksums?
      check_typosquats(lock)
    end

    def check_transport(lock, source)
      lines = source.option_lines.fetch("remote", [source.line])
      names = source.specs.map(&:name).uniq
      source.remotes.each_with_index do |remote, i|
        next unless remote.match?(INSECURE)

        what = source.registry? ? "remote #{remote} (#{names.size} gem(s))" : "#{list(names)} from #{remote}"
        insecure(remote, lock.path, lines[i] || source.line, what)
      end
    end

    def check_remotes(lock, source)
      return if source.remotes.size < 2

      add("GG002", source.remotes.join(" "), lock.path, source.line,
          "one GEM section has #{source.remotes.size} remotes (#{source.remotes.join(", ")}): " \
          "Bundler may take any of its gems from any of them",
          'Regenerate the lockfile with each private gem in its own `source "..." do` block.')
    end

    def list(names) = names.size > 3 ? "#{names.first(3).join(", ")} and #{names.size - 3} more" : names.join(", ")

    def check_git(lock, source)
      return if source.specs.empty?

      opts = source.options
      names = list(source.specs.map(&:name).uniq)
      what = "#{names} from #{source.remote}"
      line = source.line
      help = 'Pin it with `ref: "<full commit SHA>"`, or use a release from a gem registry.'
      ref = opts["ref"]
      if opts["tag"]
        add("GG003", source.remote, lock.path, line, "#{what} follows tag #{opts["tag"]}, which can be moved", help, "low")
      elsif ref&.match?(/\A(?:\h{40}|\h{64})\z/)
        nil
      elsif ref&.match?(/\A\h{7,39}\z/)
        add("GG003", source.remote, lock.path, line, "#{what} is pinned to the abbreviated ref #{ref}", help, "low")
      else
        branch = opts["branch"] || ref
        add("GG003", source.remote, lock.path, line,
            "#{what} tracks #{branch ? "branch #{branch}" : "the default branch"}: " \
            "`bundle update` installs whatever was pushed last", help)
      end
    end

    def check_path(lock, source)
      remote = source.remote.to_s
      abs = File.expand_path(remote, @project.dir)
      root = @project.root
      return if abs == root || abs.start_with?("#{root}/")

      add("GG004", remote, lock.path, source.line,
          "#{list(source.specs.map(&:name).uniq)} is loaded from #{remote}, outside this repository",
          "Vendor the gem into the repository or publish it, so every machine installs the same code.")
    end

    def check_checksums(lock)
      lock.sources.select(&:registry?).flat_map(&:specs).each do |spec|
        entry = lock.checksums[spec.full_name]
        next if entry && !entry.checksums.empty?

        problem = entry ? "has an empty CHECKSUMS entry" : "is missing from the CHECKSUMS section"
        add("GG005", spec.id, lock.path, entry ? entry.line : spec.line, "#{spec.full_name} #{problem}",
            "Run `bundle lock --add-checksums` to record it; recent Bundlers refuse frozen installs without it.")
      end
    end

    def check_typosquats(lock)
      seen = {}
      lock.sources.reject { |s| s.type == "PATH" }.flat_map(&:specs).each do |spec|
        next if seen[spec.name]

        seen[spec.name] = true
        target = Typosquat.imitates(spec.name) or next
        add("GG008", spec.id, lock.path, spec.line, "#{spec.name} looks like a typo of the popular gem #{target}",
            "Check that #{spec.name} is really intended; typosquats imitate popular names to get installed by mistake.")
      end
    end

    def check_bundle_config(config)
      if (s = config["BUNDLE_SSL_VERIFY_MODE"]) && s.value == "0"
        add("GG007", s.key, config.path, s.line, "#{s.key} is 0: Bundler does not verify TLS certificates",
            "Remove it: bundle config unset --local ssl_verify_mode")
      end
      if (s = config["BUNDLE_DISABLE_CHECKSUM_VALIDATION"]) && s.value == "true"
        add("GG007", s.key, config.path, s.line, "#{s.key} is true: gems are installed even when their checksum does not match",
            "Remove it: bundle config unset --local disable_checksum_validation")
      end
    end

    # GG006, against rubygems.org.
    def check_freshness(lock)
      groups = from_rubygems_org(lock).group_by { |s| [s.name, s.version] }
      return if @offline || groups.empty?

      versions = fetch_all(groups.keys.map(&:first).uniq) { |name| @registry.versions(name) }
      return if versions.nil?

      cutoff = @now - (@min_age * 86_400)
      groups.each do |(name, version), variants|
        released = variants.filter_map { |s| released_at(versions[name], version, s.platform) }.max
        fresh(lock, variants, released) if released && released > cutoff
      end
    end

    def from_rubygems_org(lock)
      lock.sources.select { |s| s.registry? && s.remotes.any? { |r| Registry.serves?(r) } }.flat_map(&:specs)
    end

    def fresh(lock, variants, released)
      spec = variants.first
      runs = runs_code(variants)
      days = ((@now - released) / 86_400).floor
      age = days < 1 ? "less than a day" : "#{days} day(s)"
      add("GG006", spec.id, lock.path, spec.line,
          "#{spec.id} was released #{age} ago#{" and #{runs}, which runs code during install" if runs}",
          "Most hijacked releases are found and yanked within days. Hold it back until it is #{@min_age} days old: " \
          "`bundle update #{spec.name} --cooldown #{@min_age}` (Bundler 4.0.13+).",
          runs ? "high" : nil)
    end

    def released_at(versions, version, platform)
      return nil if versions.nil?

      versions[[version, platform || "ruby"]] || versions.find { |(number, _), _| number == version }&.last
    end

    # Precompiled platform gems do not build anything, so the plain ruby
    # variant is the one to look at when the lockfile has it.
    def runs_code(variants)
      s = variants.find { |v| v.platform.nil? } || variants.first
      spec = begin
        @registry.spec(s.name, s.version, s.platform)
      rescue StandardError => e
        @warn.call("warning: GG006: could not read the metadata of #{s.full_name}: #{e.message}")
        nil
      end
      return nil unless spec
      return "builds a native extension" if Array(spec.extensions).any?

      "ships a RubyGems plugin" if Array(spec.files).any? { |f| File.basename(f).start_with?("rubygems_plugin.") }
    end

    # Fetches with a small thread pool; nil when the registry cannot be reached.
    def fetch_all(names)
      queue = Queue.new
      names.each { |n| queue << n }
      results = {}
      failed = []
      mutex = Mutex.new
      workers = Array.new([@threads, names.size].min) do
        Thread.new do
          while (name = begin
            queue.pop(true)
          rescue ThreadError
            nil
          end)
            break if @offline

            begin
              value = yield(name)
              mutex.synchronize { results[name] = value }
            rescue Offline => e
              mutex.synchronize { went_offline(e) }
            rescue StandardError => e
              mutex.synchronize { failed << "#{name} (#{e.message})" }
            end
          end
        end
      end
      workers.each(&:join)
      return nil if @offline

      @warn.call("warning: GG006: could not check #{failed.size} gem(s): #{failed.first(5).join(", ")}") unless failed.empty?
      results
    end

    def went_offline(error)
      return if @offline

      @offline = true
      @warn.call("warning: rubygems.org could not be reached (#{error.message}); GG006 (freshly released) was skipped")
    end
  end
end
