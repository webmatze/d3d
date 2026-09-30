#!/usr/bin/env ruby
require "json"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(ROOT) unless $LOAD_PATH.include?(ROOT)

def option_value(flag)
  idx = ARGV.index(flag)
  return nil unless idx

  value = ARGV[idx + 1]
  if value.nil? || value.start_with?("--")
    warn "Error: #{flag} requires a value."
    exit 1
  end
  value
end

save = ARGV.include?("--save")
as_json = ARGV.include?("--json")
no_baseline = ARGV.include?("--no-baseline")
fail_on_regression = ARGV.include?("--fail-on-regression")
filter = option_value("--filter")
# --engine DIR loads app/d3d from another checkout (used by compare.rb); the
# cases and scenes always come from this checkout so both sides do the same work.
engine = option_value("--engine")
rounds = (option_value("--rounds") || 8).to_i
quick = ARGV.include?("--quick")

if engine
  engine = File.expand_path(engine)
  Object.const_set(:D3D_ROOT, File.join(engine, "app/d3d"))
  require File.join(engine, "app/d3d/d3d.rb")
else
  require "app/d3d/d3d.rb"
end

require_relative "harness"
require_relative "report"
require_relative "baseline"
require_relative "scenes"
Dir[File.join(__dir__, "cases", "*.rb")].sort.each { |f| require f }

BASELINE_PATH = File.join(__dir__, "baseline.json")

cases = Bench::Registry.cases
cases = cases.select { |c| c.name.include?(filter) } if filter

if cases.empty?
  warn "No benchmark cases matched#{filter ? " filter #{filter.inspect}" : ''}."
  exit 1
end

timing = quick ? { target_time: 0.1, warmup_time: 0.1 } : {}
results = cases.map do |c|
  begin
    stats = Bench::Timer.measure(setup: c.setup, body: c.body, rounds: rounds, **timing)
    { name: c.name, ns_per_op: stats[:ns_per_op], noise: stats[:noise], allocs_per_op: stats[:allocs_per_op] }
  rescue StandardError, ScriptError => e
    # A case may use API the engine under test doesn't have (e.g. an older
    # checkout in compare.rb); report it instead of aborting the whole run.
    { name: c.name, error: "#{e.class}: #{e.message}" }
  end
end

ok_results = results.reject { |r| r[:error] }
Bench::Baseline.save(BASELINE_PATH, ok_results) if save

baseline = no_baseline ? nil : Bench::Baseline.load(BASELINE_PATH)
rows = results.map do |r|
  next { name: r[:name], error: r[:error], verdict: :error } if r[:error]

  base = baseline && baseline[r[:name]]
  base_ns = base && base["ns_per_op"]
  delta = Bench::Report.delta_percent(base_ns, r[:ns_per_op])
  {
    name: r[:name],
    baseline_ns: base_ns,
    current_ns: r[:ns_per_op],
    delta_pct: delta,
    noise: r[:noise],
    allocs_per_op: r[:allocs_per_op],
    verdict: Bench::Report.verdict(delta, r[:noise])
  }
end

if as_json
  puts JSON.pretty_generate(rows)
else
  puts Bench::Report.format_table(rows.reject { |row| row[:error] })
  rows.select { |row| row[:error] }.each { |row| puts "error: #{row[:name]}: #{row[:error]}" }
end

exit 2 if fail_on_regression && rows.any? { |row| row[:verdict] == :slower }
