#!/usr/bin/env ruby
# One command to judge an engine change (the working tree) against a revision:
#
#   ruby bench/evaluate.rb [--base REV=HEAD] [--filter X] [--pairs 3] [--mruby [--native]]
#                          [--allow-output-change] [--json]
#
# 1. all tests (tests/*.rb)
# 2. golden: engine output must match REV (bench/golden.rb --against REV)
# 3. A/B timing vs REV in CRuby (bench/compare.rb); with --mruby also in
#    DragonRuby plus a demo smoke test (bench/smoke.rb); --native loads the
#    optional C extension on the head side of the DragonRuby A/B
#
# decision "keep" requires: tests pass, output unchanged (unless
# --allow-output-change), at least one case faster (in CRuby, or with --mruby
# in either runtime, so mruby-only changes can be kept), none slower (in
# either runtime), and no case allocating more objects per op.
# Exit status: 0 keep, 3 reject.
require "json"
require "open3"

ROOT = File.expand_path("..", __dir__)
ALLOC_TOLERANCE_PCT = 1.0

def option_value(flag, default = nil)
  idx = ARGV.index(flag)
  return default unless idx

  value = ARGV[idx + 1]
  abort "Error: #{flag} requires a value." if value.nil? || value.start_with?("--")
  value
end

base = option_value("--base", "HEAD")
filter = option_value("--filter")
pairs = option_value("--pairs", "3")
mruby = ARGV.include?("--mruby")
native = ARGV.include?("--native")
abort "Error: --native needs --mruby." if native && !mruby
allow_output_change = ARGV.include?("--allow-output-change")
as_json = ARGV.include?("--json")

def run(*cmd)
  out, err, status = Open3.capture3(*cmd, chdir: ROOT)
  [out + err, status]
end

def log(msg)
  warn "evaluate: #{msg}"
end

result = { base: base, tests: nil, golden: nil, warnings: [] }

# ---------------------------------------------------------------- tests
log "running tests"
failed_tests = Dir[File.join(ROOT, "tests/*.rb")].sort.reject do |file|
  _out, status = run("ruby", file)
  status.success?
end.map { |f| File.basename(f) }
result[:tests] = failed_tests.empty? ? "pass" : "fail"
result[:failed_tests] = failed_tests

# ---------------------------------------------------------------- golden
log "comparing engine output with #{base}"
golden_out, golden_status = run("ruby", "bench/golden.rb", "--against", base)
result[:golden] = golden_status.success? ? "match" : "differs"
result[:golden_details] = golden_out.strip unless golden_status.success?
if golden_status.success?
  check_out, check_status = run("ruby", "bench/golden.rb")
  unless check_status.success?
    result[:warnings] << "bench/golden.json is stale (output matches #{base} within tolerance); " \
                         "run ruby bench/golden.rb --update\n#{check_out.strip}"
  end
elsif allow_output_change
  result[:warnings] << "engine output differs from #{base} (allowed by --allow-output-change)"
end
golden_ok = golden_status.success? || allow_output_change

# ---------------------------------------------------------------- timing
def compare(base, filter, pairs, mruby, native: false)
  cmd = ["ruby", "bench/compare.rb", base, "--json", "--pairs", pairs]
  cmd += ["--filter", filter] if filter
  cmd << "--mruby" if mruby
  cmd << "--native" if native
  out, err, status = Open3.capture3(*cmd, chdir: ROOT)
  abort "Error: compare.rb failed:\n#{err}" unless [0, 2].include?(status.exitstatus)
  JSON.parse(out)
end

if result[:tests] == "pass" && golden_ok
  log "A/B timing vs #{base} (CRuby)"
  cruby = compare(base, filter, pairs, false)
  result[:score] = cruby["score"]
  result[:faster] = cruby["faster"]
  result[:slower] = cruby["slower"]
  result[:cases] = cruby["cases"]
  result[:alloc_regressions] = cruby["cases"].select do |c|
    c["base_allocs"] && c["head_allocs"] &&
      c["head_allocs"] > c["base_allocs"] * (1 + ALLOC_TOLERANCE_PCT / 100.0) &&
      c["head_allocs"] - c["base_allocs"] >= 1
  end.map { |c| "#{c['name']}: #{c['base_allocs'].round} -> #{c['head_allocs'].round}" }

  if mruby
    log "A/B timing vs #{base} (DragonRuby mruby#{native ? ', head with C extension' : ''})"
    mr = compare(base, filter, pairs, true, native: native)
    log "demo smoke test in DragonRuby"
    smoke_out, smoke_status = run("ruby", "bench/smoke.rb")
    result[:mruby] = { score: mr["score"], faster: mr["faster"], slower: mr["slower"], cases: mr["cases"],
                       smoke: smoke_status.success? ? "pass" : "fail", smoke_report: smoke_out.strip }
  end
end

# ---------------------------------------------------------------- decision
reason =
  if result[:tests] != "pass"
    "tests failed: #{failed_tests.join(', ')}"
  elsif !golden_ok
    "engine output changed (see golden_details)"
  elsif !result[:slower].empty?
    "slower: #{result[:slower].join(', ')}"
  elsif result[:mruby] && result[:mruby][:smoke] != "pass"
    "demo smoke test failed in DragonRuby"
  elsif result[:mruby] && !result[:mruby][:slower].empty?
    "slower in mruby: #{result[:mruby][:slower].join(', ')}"
  elsif !result[:alloc_regressions].empty?
    "more allocations: #{result[:alloc_regressions].join(', ')}"
  elsif result[:faster].empty? && (!result[:mruby] || result[:mruby][:faster].empty?)
    "no case measurably faster"
  end
result[:decision] = reason ? "reject" : "keep"
faster = result[:faster] ? result[:faster].dup : []
faster += result[:mruby][:faster].map { |n| "#{n} (mruby)" } if result[:mruby]
result[:reason] = reason || "faster: #{faster.join(', ')}"

if as_json
  puts JSON.pretty_generate(result)
else
  puts "tests:  #{result[:tests]}#{failed_tests.empty? ? '' : " (#{failed_tests.join(', ')})"}"
  puts "golden: #{result[:golden]}"
  puts result[:golden_details] if result[:golden_details]
  if result[:cases]
    puts format("score:  %.3f (CRuby, geometric mean head/base)", result[:score] || 1.0)
    result[:cases].each do |c|
      next if c["verdict"] == "within_noise"

      line = c["verdict"] == "unavailable" ? c["error"] : format("%+.1f%% ±%.1f%%", c["delta_pct"], c["noise"])
      puts "  #{c['name']}: #{c['verdict']} #{line}"
    end
    puts "  alloc regressions: #{result[:alloc_regressions].join(', ')}" unless result[:alloc_regressions].empty?
  end
  if result[:mruby]
    puts format("mruby:  %.3f, faster: %s, slower: %s", result[:mruby][:score] || 1.0,
                result[:mruby][:faster].join(", "), result[:mruby][:slower].join(", "))
    result[:mruby][:cases].each do |c|
      next if c["verdict"] == "within_noise"

      line = c["verdict"] == "unavailable" ? c["error"] : format("%+.1f%% ±%.1f%%", c["delta_pct"], c["noise"])
      puts "  #{c['name']}: #{c['verdict']} #{line}"
    end
    puts "smoke:  #{result[:mruby][:smoke]}"
    puts result[:mruby][:smoke_report]
  end
  result[:warnings].each { |w| puts "warning: #{w}" }
  puts "DECISION: #{result[:decision]} (#{result[:reason]})"
end

exit(result[:decision] == "keep" ? 0 : 3)
