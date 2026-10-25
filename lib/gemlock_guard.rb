# frozen_string_literal: true

require_relative "gemlock_guard/version"
require_relative "gemlock_guard/finding"
require_relative "gemlock_guard/lockfile"
require_relative "gemlock_guard/gemfile"
require_relative "gemlock_guard/bundle_config"
require_relative "gemlock_guard/project"
require_relative "gemlock_guard/popular"
require_relative "gemlock_guard/typosquat"
require_relative "gemlock_guard/registry"
require_relative "gemlock_guard/checks"
require_relative "gemlock_guard/report"
require_relative "gemlock_guard/cli"

# Supply-chain checks for Gemfile and Gemfile.lock.
module GemlockGuard
end
