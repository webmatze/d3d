require_relative "report"

module Bench
  # Statistics for interleaved A/B runs (compare.rb). Run i of the base and
  # run i of the candidate execute back to back, so each pair shares the same
  # machine state (clock speed, temperature, background load). Comparing per
  # pair ratios cancels the slow drift that makes a stored baseline unreliable.
  module AbStats
    module_function

    # base_runs / head_runs: per-run ns/op of one case, paired by index.
    # Returns delta (median pair ratio), noise (half the ratio range) and a
    # verdict from Report.verdict, all in percent.
    def compare_case(base_runs, head_runs, floor_pct = Report::FLOOR_PCT)
      ratios = base_runs.zip(head_runs).map { |a, b| b / a }
      ratio = median(ratios)
      delta = (ratio - 1.0) * 100.0
      noise = (ratios.max - ratios.min) / 2.0 * 100.0
      {
        base_ns: base_runs.min,
        head_ns: head_runs.min,
        ratio: ratio,
        delta_pct: delta,
        noise: noise,
        verdict: Report.verdict(delta, noise, floor_pct)
      }
    end

    # Percent change of allocations per op, nil when unknown.
    def alloc_delta(base_allocs, head_allocs)
      return nil if base_allocs.nil? || head_allocs.nil?
      return 0.0 if base_allocs.zero? && head_allocs.zero?
      return 100.0 if base_allocs.zero?

      (head_allocs - base_allocs) / base_allocs * 100.0
    end

    # Geometric mean of time ratios (head / base): < 1.0 means faster overall.
    def score(ratios)
      return nil if ratios.empty?

      Math.exp(ratios.map { |r| Math.log(r) }.sum / ratios.size)
    end

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end
  end
end
