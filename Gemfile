# frozen_string_literal: true

# Bundler 4.0.13+ skips versions published less than 7 days ago when resolving.
source "https://rubygems.org", cooldown: 7

gemspec

group :development do
  gem "minitest", "~> 6.0"
  gem "rake", "~> 13.0"
  # parallel 2.x (a rubocop dependency) needs Ruby 3.3; the gem supports 3.2.
  gem "parallel", "~> 1.28", require: false
  gem "rubocop", "~> 1.90", require: false
  gem "rubocop-minitest", require: false
  # 1.3 needs Ruby 3.3; the gem supports 3.2.
  gem "simplecov", "~> 1.2.0", require: false
end
