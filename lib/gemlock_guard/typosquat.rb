# frozen_string_literal: true

module GemlockGuard
  # Names one typo away from a popular gem.
  module Typosquat
    POPULAR_SET = Set.new(POPULAR).freeze

    module_function

    # Optimal string alignment distance: insertions, deletions, substitutions and adjacent swaps.
    def distance(a, b)
      prev2 = nil
      prev = (0..b.size).to_a
      (1..a.size).each do |i|
        row = [i]
        (1..b.size).each do |j|
          row << cell(a, b, i, j, prev, prev2, row[j - 1])
        end
        prev2 = prev
        prev = row
      end
      prev[b.size]
    end

    def cell(a, b, i, j, prev, prev2, left)
      v = [prev[j] + 1, left + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].min
      swapped = i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]
      swapped ? [v, prev2[j - 2] + 1].min : v
    end

    # rubygems.org compares names case-insensitively and ignores - and _.
    def normalise(name) = name.downcase.delete("-_.")

    # The popular gem a name imitates, or nil.
    def imitates(name)
      return nil if POPULAR_SET.include?(name)

      n = normalise(name)
      POPULAR.find { |p| normalise(p) == n || near?(name, p) }
    end

    # Short names have too many legitimate one-letter neighbours (rack/crack,
    # rake/make), and a trailing digit is usually a major version or protocol
    # (oauth/oauth2, net-http/net-http2), not a typo.
    def near?(name, popular)
      return false if name.size < 5 || popular.size < 5
      return false if name.sub(/\d+\z/, "") == popular.sub(/\d+\z/, "")

      distance(name, popular) == 1
    end
  end
end
