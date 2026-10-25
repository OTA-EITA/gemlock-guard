# frozen_string_literal: true

require "test_helper"

class BundleConfigTest < Minitest::Test
  def test_reads_quoted_and_bare_values
    config = GemlockGuard::BundleConfig.new(<<~YAML)
      ---
      BUNDLE_PATH: "vendor/bundle"
      BUNDLE_SSL_VERIFY_MODE: '0'
      BUNDLE_JOBS: 4
      not a setting
    YAML

    assert_equal "vendor/bundle", config["BUNDLE_PATH"].value
    assert_equal "0", config["BUNDLE_SSL_VERIFY_MODE"].value
    assert_equal 3, config["BUNDLE_SSL_VERIFY_MODE"].line
    assert_equal "4", config["BUNDLE_JOBS"].value
    assert_nil config["BUNDLE_FROZEN"]
  end
end
