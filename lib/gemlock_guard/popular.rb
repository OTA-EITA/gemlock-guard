# frozen_string_literal: true

module GemlockGuard
  # Frequently depended-upon gems, the usual targets of typosquatting.
  # Similar names that are both legitimate (sass/sassc, erubi/erubis) are
  # listed together so they never flag each other; the last line holds such
  # names found as false positives by scanning real lockfiles.
  POPULAR = %w[
    rails railties activesupport activerecord activemodel actionpack actionview
    actionmailer actioncable activejob activestorage actiontext actionmailbox
    rack rack-test rack-cors rack-attack rack-protection rake bundler rubygems-update
    nokogiri loofah rails-html-sanitizer crass json oj multi_json yajl-ruby msgpack
    rspec rspec-core rspec-expectations rspec-mocks rspec-support rspec-rails
    minitest minitest-reporters test-unit simplecov webmock vcr capybara selenium-webdriver
    factory_bot factory_bot_rails faker timecop climate_control
    pry pry-byebug pry-rails byebug debug irb reline
    rubocop rubocop-ast rubocop-rails rubocop-performance rubocop-rspec standard
    puma unicorn passenger falcon sidekiq resque delayed_job good_job solid_queue
    redis redis-client hiredis connection_pool pg mysql2 sqlite3 trilogy sequel
    devise warden bcrypt jwt oauth oauth2 omniauth omniauth-oauth2 doorkeeper pundit cancancan
    faraday faraday-net_http httparty rest-client excon typhoeus http httpx
    addressable public_suffix mime-types mini_mime mail marcel
    aws-sdk-core aws-sdk-s3 google-protobuf googleapis-common-protos grpc
    thor i18n tzinfo tzinfo-data concurrent-ruby zeitwerk bootsnap listen
    sprockets sprockets-rails sass sassc sass-rails sassc-rails propshaft
    importmap-rails turbo-rails stimulus-rails jsbundling-rails cssbundling-rails webpacker
    haml slim erubi erubis builder tilt jbuilder kaminari will_paginate
    dotenv dotenv-rails figaro sentry-ruby sentry-rails newrelic_rpm rollbar honeybadger
    ffi nio4r websocket-driver mustermann sinatra roda hanami grape graphql
    carrierwave shrine image_processing mini_magick ruby-vips rmagick chunky_png
    net-ssh net-scp net-sftp net-http net-smtp net-imap net-pop uri cgi rexml psych racc rdoc
    octokit stripe twilio-ruby slack-ruby-client kramdown redcarpet commonmarker rouge
    rufus-scheduler whenever activeadmin administrate paper_trail ransack
    highline tty-prompt colorize rainbow awesome_print ruby-progressbar parallel
    ast parser regexp_parser unicode-display_width diff-lcs docile rubyzip
    ffaker
  ].freeze
end
