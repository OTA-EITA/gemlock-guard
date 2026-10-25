# frozen_string_literal: true

module GemlockGuard
  # The Gemfile, Gemfile.lock and .bundle/config of one directory.
  #
  # Bundler also accepts gems.rb / gems.locked; both spellings are read.
  class Project
    GEMFILES = { "Gemfile" => "Gemfile.lock", "gems.rb" => "gems.locked" }.freeze

    attr_reader :dir, :display_dir, :gemfile, :lockfile, :bundle_config

    # Test fixtures are meant to be bad; scan them by naming the path explicitly.
    SKIP_DIRS = %w[.git vendor node_modules fixtures testdata tmp].freeze

    def self.gemfile_in(dir) = GEMFILES.keys.find { |name| File.file?(File.join(dir, name)) }

    # Directories holding a Gemfile, skipping vendored code, VCS data and test fixtures.
    def self.discover(path)
      if File.file?(path)
        name = File.basename(path)
        return GEMFILES.to_a.flatten.include?(name) ? [File.dirname(path)] : []
      end
      raise Errno::ENOENT, path unless File.directory?(path)

      found = gemfile_in(path) ? [path] : []
      Dir.children(path).sort.each do |entry|
        full = File.join(path, entry)
        next if SKIP_DIRS.include?(entry) || !File.directory?(full) || File.symlink?(full)

        found.concat(discover(full))
      end
      found
    end

    # dir is the absolute directory; display_dir is how paths are shown in reports.
    def self.load(dir, display_dir)
      name = gemfile_in(dir) or raise ArgumentError, "#{dir}: no Gemfile"
      show = ->(file) { display_dir.empty? || display_dir == "." ? file : File.join(display_dir, file) }
      lock = File.join(dir, GEMFILES.fetch(name))
      config = File.join(dir, ".bundle", "config")
      new(
        dir:,
        display_dir:,
        gemfile: Gemfile.new(read(File.join(dir, name)), show.call(name)),
        lockfile: (Lockfile.new(read(lock), show.call(GEMFILES.fetch(name))) if File.file?(lock)),
        bundle_config: (BundleConfig.new(read(config), show.call(".bundle/config")) if File.file?(config))
      )
    end

    def self.read(path) = File.read(path, encoding: "UTF-8")

    def initialize(dir:, gemfile:, display_dir: ".", lockfile: nil, bundle_config: nil)
      @dir = dir
      @display_dir = display_dir
      @gemfile = gemfile
      @lockfile = lockfile
      @bundle_config = bundle_config
    end

    # The enclosing git work tree, or the project directory when there is none.
    def root
      @root ||= begin
        d = File.expand_path(dir)
        d = File.dirname(d) until File.exist?(File.join(d, ".git")) || File.dirname(d) == d
        File.exist?(File.join(d, ".git")) ? d : File.expand_path(dir)
      end
    end
  end
end
