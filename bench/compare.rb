#!/usr/bin/env ruby
# A/B benchmark: the engine at a git revision (base) vs the working tree (head).
#
#   ruby bench/compare.rb [BASE=HEAD] [--filter X] [--pairs 3] [--rounds 5]
#                         [--floor 5] [--json] [--mruby [--native]]
#
# Runs base and head alternately in fresh processes (A B, B A, A B, ...) and
# compares per pair ratios, so clock and temperature drift cancel out. Both
# sides run the benchmark cases from the working tree; only app/ differs.
# --mruby measures inside DragonRuby instead of CRuby (slower, ground truth).
# --native (with --mruby) loads the optional C extension on the head side only
# (native/ from bin/build-ext), so the A/B shows what the extension gains.
# Exit status: 0 ok, 2 if any case got slower, 1 on usage/setup errors.
require "json"
require "open3"
require "tmpdir"
require "fileutils"
require_relative "ab_stats"
require_relative "dragonruby"

ROOT = File.expand_path("..", __dir__)

def option_value(flag, default = nil)
  idx = ARGV.index(flag)
  return default unless idx

  value = ARGV[idx + 1]
  abort "Error: #{flag} requires a value." if value.nil? || value.start_with?("--")
  value
end

VALUE_FLAGS = %w[--filter --pairs --rounds --floor].freeze
positional = ARGV.each_with_index.reject do |arg, i|
  arg.start_with?("--") || VALUE_FLAGS.include?(ARGV[i - 1]) && i > 0
end.map(&:first)

base_rev = positional.first || "HEAD"
filter = option_value("--filter")
pairs = option_value("--pairs", "3").to_i
rounds = option_value("--rounds", "5").to_i
floor = option_value("--floor", Bench::Report::FLOOR_PCT.to_s).to_f
as_json = ARGV.include?("--json")
mruby = ARGV.include?("--mruby")
native = ARGV.include?("--native")
abort "Error: --native needs --mruby (the C extension only loads in DragonRuby)." if native && !mruby
if native && !Dir.exist?(File.join(ROOT, "native"))
  abort "Error: --native needs a built extension; run bin/build-ext first."
end

def sh!(cmd, chdir: ROOT)
  out, err, status = Open3.capture3(*cmd, chdir: chdir)
  abort "Error: #{cmd.join(' ')} failed:\n#{err}" unless status.success?
  out
end

base_sha = sh!(["git", "rev-parse", "--verify", "#{base_rev}^{commit}"]).strip
dirty = !sh!(["git", "status", "--porcelain", "--", "app"]).strip.empty?
head_label = "working tree#{dirty ? ' (uncommitted changes)' : ''}"

# ---------------------------------------------------------------- runners

# Returns { case_name => { ns:, allocs: } or { error: } }.
def run_cruby(engine_dir, filter, rounds)
  cmd = ["ruby", File.join(ROOT, "bench/bench.rb"), "--json", "--no-baseline", "--quick",
         "--rounds", rounds.to_s, "--engine", engine_dir]
  cmd += ["--filter", filter] if filter
  out, err, status = Open3.capture3(*cmd, chdir: ROOT)
  abort "Error: benchmark run failed for #{engine_dir}:\n#{err}" unless status.success?

  JSON.parse(out).each_with_object({}) do |row, h|
    h[row["name"]] = row["error"] ? { error: row["error"] } : { ns: row["current_ns"], allocs: row["allocs_per_op"] }
  end
end

def run_mruby(game_dir, filter, rounds, native: false)
  File.write(File.join(game_dir, "bench/mruby_config.txt"),
             "filter=#{filter}\nrounds=#{rounds}\nnative=#{native ? 1 : 0}\n")
  results_path = File.join(game_dir, "bench/mruby_results.tsv")
  FileUtils.rm_f(results_path)
  log = Bench::DragonRuby.run(game_dir, "bench/mruby_runner.rb")
  text = File.exist?(results_path) ? File.read(results_path) : ""
  abort "Error: DragonRuby run failed (log: #{log}):\n#{text}" unless text.include?("DONE")

  text.lines.map { |l| l.chomp.split("\t", 3) }.each_with_object({}) do |(name, ns, rest), h|
    next if name == "DONE"

    h[name] = ns == "ERROR" ? { error: rest } : { ns: ns.to_f, allocs: nil }
  end
end

# ---------------------------------------------------------------- setup

work = Dir.mktmpdir("d3d-compare-")
begin
  base_dir = File.join(work, "base")
  FileUtils.mkdir_p(base_dir)
  archive = sh!(["git", "archive", "--format=tar", base_sha, "app"])
  Open3.capture2("tar", "-x", "-C", base_dir, stdin_data: archive, binmode: true)

  head_dir = ROOT
  if mruby
    # DragonRuby needs a whole game dir; both sides get the working tree's bench/.
    head_dir = Bench::DragonRuby.game_dir(work, "head", extra: native ? ["bench", "native"] : ["bench"])
    FileUtils.cp_r(File.join(ROOT, "bench"), base_dir)
    FileUtils.cp_r(File.join(ROOT, "metadata"), base_dir) if File.directory?(File.join(ROOT, "metadata"))
    Bench::DragonRuby.disable_shaders(base_dir)
  end

  runs = { base: [], head: [] }
  pairs.times do |i|
    order = i.even? ? %i[base head] : %i[head base]
    order.each do |side|
      dir = side == :base ? base_dir : head_dir
      warn "compare: pair #{i + 1}/#{pairs}, #{side}#{mruby ? ' (mruby)' : ''}"
      runs[side] << if mruby
                      run_mruby(dir, filter, rounds, native: native && side == :head)
                    else
                      run_cruby(dir, filter, rounds)
                    end
    end
  end
ensure
  FileUtils.rm_rf(work)
end

# ---------------------------------------------------------------- analysis

names = runs[:head].first.keys
rows = names.map do |name|
  base_runs = runs[:base].map { |r| r[name] }
  head_runs = runs[:head].map { |r| r[name] }
  failed = (base_runs + head_runs).find { |r| r.nil? || r[:error] }
  if failed
    next { name: name, verdict: "unavailable", error: failed ? failed[:error] : "missing" }
  end

  stats = Bench::AbStats.compare_case(base_runs.map { |r| r[:ns] }, head_runs.map { |r| r[:ns] }, floor)
  base_allocs = base_runs.first[:allocs]
  head_allocs = head_runs.first[:allocs]
  stats.merge(name: name, verdict: stats[:verdict].to_s,
              base_allocs: base_allocs, head_allocs: head_allocs,
              alloc_delta_pct: Bench::AbStats.alloc_delta(base_allocs, head_allocs))
end

compared = rows.reject { |r| r[:verdict] == "unavailable" }
score = Bench::AbStats.score(compared.map { |r| r[:ratio] })
result = {
  base: base_sha,
  head: head_label,
  runtime: mruby ? "mruby" : "cruby",
  pairs: pairs,
  floor_pct: floor,
  score: score,
  faster: compared.select { |r| r[:verdict] == "faster" }.map { |r| r[:name] },
  slower: compared.select { |r| r[:verdict] == "slower" }.map { |r| r[:name] },
  cases: rows
}

if as_json
  puts JSON.pretty_generate(result)
else
  fmt = "%-30s %13s %13s %8s %7s  %-12s %s"
  puts "base #{base_sha[0, 10]} vs #{head_label} (#{result[:runtime]}, #{pairs} pairs)"
  puts format(fmt, "case", "base ns/op", "head ns/op", "delta", "noise", "verdict", "allocs/op")
  puts "-" * 104
  rows.each do |r|
    if r[:verdict] == "unavailable"
      puts format("%-30s unavailable: %s", r[:name], r[:error])
      next
    end
    allocs = if r[:base_allocs]
               d = r[:alloc_delta_pct]
               "#{r[:base_allocs].round} -> #{r[:head_allocs].round}#{d && d.abs > 0.5 ? format(' (%+.0f%%)', d) : ''}"
             else
               "-"
             end
    puts format(fmt, r[:name], format("%.1f", r[:base_ns]), format("%.1f", r[:head_ns]),
                format("%+.1f%%", r[:delta_pct]), format("±%.1f%%", r[:noise]), r[:verdict], allocs)
  end
  puts
  puts format("score (geometric mean head/base): %.3f   faster: %d   slower: %d",
              score || 1.0, result[:faster].size, result[:slower].size)
end

exit 2 unless result[:slower].empty?
