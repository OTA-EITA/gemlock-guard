# frozen_string_literal: true

require "test_helper"

class TyposquatTest < Minitest::Test
  T = GemlockGuard::Typosquat

  def test_distance
    assert_equal 3, T.distance("kitten", "sitting")
    assert_equal 1, T.distance("ab", "ba")
    assert_equal 3, T.distance("", "abc")
    assert_equal 0, T.distance("rails", "rails")
  end

  def test_imitations
    assert_equal "nokogiri", T.imitates("nokogirl")
    assert_equal "rspec-mocks", T.imitates("rspec-mokcs")
    assert_equal "rest-client", T.imitates("rest_client")
    assert_equal "activesupport", T.imitates("ActiveSupport")
  end

  def test_legitimate_names
    %w[rails sass sassc erubi erubis oauth oauth2 rack rake racc thor pry mysql2 my-own-gem].each do |name|
      assert_nil T.imitates(name), name
    end
  end
end
