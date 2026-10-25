# frozen_string_literal: true

require_relative "lib/gemlock_guard/version"

Gem::Specification.new do |spec|
  spec.name = "gemlock-guard"
  spec.version = GemlockGuard::VERSION
  spec.authors = ["OTA-EITA"]
  spec.summary = "Supply-chain checks for Gemfile and Gemfile.lock that bundler-audit doesn't do"
  spec.description = "Finds freshly released gems, plain HTTP and ambiguous sources, git gems on moving branches, " \
                     "missing lockfile checksums and typosquats in Gemfile and Gemfile.lock. No runtime dependencies."
  spec.homepage = "https://github.com/OTA-EITA/gemlock-guard"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE"]
  spec.bindir = "exe"
  spec.executables = ["gemlock-guard"]
  spec.require_paths = ["lib"]
end
