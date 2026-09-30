require "minitest/autorun"
require_relative "../bench/report"

class BenchReportTest < Minitest::Test
  def test_delta_percent_basic
    assert_in_delta(-20.0, Bench::Report.delta_percent(100.0, 80.0), 1e-9)
    assert_in_delta(25.0, Bench::Report.delta_percent(100.0, 125.0), 1e-9)
  end

  def test_delta_percent_nil_or_zero_baseline
    assert_nil Bench::Report.delta_percent(nil, 80.0)
    assert_nil Bench::Report.delta_percent(0.0, 80.0)
  end

  def test_verdict_within_noise_uses_floor
    # 1% change, no measured noise -> 5% floor dominates -> within noise
    assert_equal :within_noise, Bench::Report.verdict(1.0, 0.0)
  end

  def test_verdict_within_noise_uses_measured_noise
    # 3% change but measured noise band 5% -> within noise
    assert_equal :within_noise, Bench::Report.verdict(3.0, 5.0)
  end

  def test_verdict_faster_and_slower
    assert_equal :faster, Bench::Report.verdict(-8.0, 2.0)
    assert_equal :slower, Bench::Report.verdict(8.0, 2.0)
  end

  def test_verdict_new_when_delta_nil
    assert_equal :new, Bench::Report.verdict(nil, 0.0)
  end

  def test_format_table_includes_names_and_summary
    rows = [
      { name: "a/one", baseline_ns: 100.0, current_ns: 80.0, delta_pct: -20.0, noise: 1.0, verdict: :faster },
      { name: "b/two", baseline_ns: nil, current_ns: 5.0, delta_pct: nil, noise: 0.0, verdict: :new }
    ]
    out = Bench::Report.format_table(rows)
    assert_includes out, "a/one"
    assert_includes out, "b/two"
    assert_includes out, "summary:"
    assert_includes out, "1 faster"
    assert_includes out, "-20.0%"
    assert_includes out, "1 new"
  end
end
