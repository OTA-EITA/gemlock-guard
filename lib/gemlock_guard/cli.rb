# frozen_string_literal: true

module GemlockGuard
  # Command line entry point. Returns the exit status: 0 clean, 1 findings at
  # or above --fail-on, 2 usage or input errors.
  module CLI
    USAGE = <<~TXT
      usage: gemlock-guard [options] [path ...]

      Checks Gemfile, Gemfile.lock and .bundle/config for supply-chain risks. Paths
      default to the current directory; directories are searched for Gemfiles.

      options:
        --online               also query rubygems.org for release dates (GG006)
        --min-age <days>       with --online, report versions released fewer than this many days ago (default: 7)
        --format <format>      text, json, markdown or sarif (default: text)
        --fail-on <severity>   exit 1 on findings at least this severe: high, medium, low or none (default: medium)
        --sarif-file <file>    also write a SARIF report to this file
        --markdown-file <file> also write a Markdown report to this file
        --list-checks          print the checks and exit
        --version              print the version and exit
        -h, --help             show this help
    TXT

    module_function

    class UsageError < StandardError; end

    def run(argv, out: $stdout, err: $stderr, cwd: Dir.pwd, now: Time.now, registry: nil)
      opts = parse(argv.dup, out)
      return opts if opts.is_a?(Integer)

      registry = opts[:online] ? registry || Registry.new : nil
      checks = Checks.new(min_age: opts[:min_age], now:, registry:, warn: ->(m) { err.puts(m) })
      findings, count = scan(opts[:paths], File.realpath(cwd), checks)
      if count.zero?
        err.puts "error: no Gemfile found"
        return 2
      end

      out.write(Report.render(findings, opts[:format], count))
      opts[:files].each { |format, file| File.write(file, Report.render(findings, format, count)) }
      failed?(findings, opts[:fail_on]) ? 1 : 0
    rescue UsageError => e
      err.puts "error: #{e.message}", "", USAGE
      2
    rescue Errno::ENOENT, ArgumentError => e
      err.puts "error: #{e.message}"
      2
    end

    def scan(paths, cwd, checks)
      findings = []
      count = 0
      (paths.empty? ? ["."] : paths).each do |path|
        abs = File.expand_path(path, cwd)
        Project.discover(File.exist?(abs) ? File.realpath(abs) : abs).each do |dir|
          findings.concat(checks.run(Project.load(dir, display(dir, cwd))))
          count += 1
        end
      end
      [findings, count]
    end

    def failed?(findings, fail_on)
      fail_on != "none" && findings.any? { |f| f.rank >= RANK.fetch(fail_on) }
    end

    # Returns the options, or an exit status when the command is already done.
    def parse(argv, out)
      opts = { online: false, min_age: 7, format: "text", fail_on: "medium", paths: [], files: {} }
      until argv.empty?
        arg = argv.shift
        case arg
        when "-h", "--help" then return emit(out, USAGE)
        when "--version" then return emit(out, "gemlock-guard #{VERSION}\n")
        when "--list-checks" then return emit(out, list_checks)
        when "--online" then opts[:online] = true
        when "--min-age", "--format", "--fail-on", "--sarif-file", "--markdown-file" then option(opts, arg, argv.shift)
        else
          raise UsageError, "unknown option #{arg}" if arg.start_with?("-")

          opts[:paths] << arg
        end
      end
      opts
    end

    def emit(out, text)
      out.write(text)
      0
    end

    def list_checks
      Checks::ALL.map { |id, (sev, title, desc)| "#{id}  #{sev.ljust(6)}  #{title}: #{desc}\n" }.join
    end

    def option(opts, name, value)
      raise UsageError, "#{name} needs a value" if value.nil?

      case name
      when "--min-age"
        raise UsageError, "--min-age must be a whole number of days" unless value.match?(/\A\d+\z/)

        opts[:min_age] = value.to_i
      when "--format"
        allowed!(value, Report::FORMATS, "unknown format \"#{value}\" (want #{Report::FORMATS.join(", ")})")
        opts[:format] = value
      when "--sarif-file", "--markdown-file"
        opts[:files][name[/\w+/]] = value
      else
        allowed!(value, [*SEVERITIES, "none"], "--fail-on must be high, medium, low or none, got \"#{value}\"")
        opts[:fail_on] = value
      end
    end

    def allowed!(value, list, message)
      raise UsageError, message unless list.include?(value)
    end

    def display(dir, cwd)
      return "." if dir == cwd

      dir.start_with?("#{cwd}/") ? dir.delete_prefix("#{cwd}/") : dir
    end
  end
end
