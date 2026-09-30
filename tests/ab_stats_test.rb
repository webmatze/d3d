require "minitest/autorun"
require_relative "../bench/ab_stats"

class AbStatsTest < Minitest::Test
  def test_uniform_drift_cancels_out_in_pair_ratios
    # the machine gets 20% slower between pairs, the code is identical
    stats = Bench::AbStats.compare_case([100.0, 120.0, 144.0], [101.0, 121.0, 145.0])
    assert_in_delta 0.8, stats[:delta_pct], 0.2
    assert_equal :within_noise, stats[:verdict]
  end

  def test_consistent_speedup_is_faster
    stats = Bench::AbStats.compare_case([100.0, 110.0, 105.0], [80.0, 88.0, 84.0])
    assert_in_delta(-20.0, stats[:delta_pct], 0.01)
    assert_equal :faster, stats[:verdict]
    assert_equal 80.0, stats[:head_ns]
  end

  def test_inconsistent_pairs_widen_the_noise_band
    stats = Bench::AbStats.compare_case([100.0, 100.0, 100.0], [90.0, 70.0, 110.0])
    assert_equal :within_noise, stats[:verdict]
  end

  def test_score_is_geometric_mean
    assert_in_delta 1.0, Bench::AbStats.score([0.5, 2.0]), 1e-9
    assert_nil Bench::AbStats.score([])
  end

  def test_alloc_delta
    assert_in_delta 50.0, Bench::AbStats.alloc_delta(100.0, 150.0), 1e-9
    assert_equal 0.0, Bench::AbStats.alloc_delta(0.0, 0.0)
    assert_nil Bench::AbStats.alloc_delta(nil, 3.0)
  end

  def test_median
    assert_equal 2.0, Bench::AbStats.median([3.0, 1.0, 2.0])
    assert_equal 2.5, Bench::AbStats.median([4.0, 1.0, 2.0, 3.0])
  end
end
