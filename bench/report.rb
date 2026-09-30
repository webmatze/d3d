module Bench
  module Report
    FLOOR_PCT = 5.0

    module_function

    # Percent change from baseline to current. Negative = faster (less time).
    # Returns nil when there is no usable baseline.
    def delta_percent(baseline_ns, current_ns)
      return nil if baseline_ns.nil? || baseline_ns.zero?
      (current_ns - baseline_ns) / baseline_ns * 100.0
    end

    # Classify a delta against the noise band and a minimum floor.
    def verdict(delta_pct, noise_pct, floor_pct = FLOOR_PCT)
      return :new if delta_pct.nil?
      threshold = [noise_pct || 0.0, floor_pct].max
      return :within_noise if delta_pct.abs <= threshold
      delta_pct < 0 ? :faster : :slower
    end

    # rows: [{ name:, baseline_ns:, current_ns:, delta_pct:, noise:, verdict: }]
    def format_table(rows)
      # columns: name, baseline ns/op, current ns/op, delta%, verdict
      fmt = "%-34s %14s %14s %9s  %s"
      header = format(fmt, "case", "baseline ns/op", "current ns/op", "delta%", "verdict")
      lines = [header, "-" * header.length]

      counts = { faster: 0, slower: 0, within_noise: 0, new: 0 }
      rows.each do |row|
        counts[row[:verdict]] += 1 if counts.key?(row[:verdict])
        base = row[:baseline_ns] ? format("%.1f", row[:baseline_ns]) : "-"
        cur = row[:current_ns] ? format("%.1f", row[:current_ns]) : "-"
        delta = row[:delta_pct] ? format("%+.1f%%", row[:delta_pct]) : "-"
        lines << format(fmt, row[:name], base, cur, delta, row[:verdict].to_s)
      end

      lines << ""
      lines << "summary: #{counts[:faster]} faster, #{counts[:slower]} slower, " \
               "#{counts[:within_noise]} within-noise, #{counts[:new]} new"
      lines.join("\n")
    end
  end
end
