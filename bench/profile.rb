#!/usr/bin/env ruby
# Where does a benchmark case spend its work? Zero-dependency (CRuby stdlib).
#
#   ruby bench/profile.rb CASE [--iters 20] [--top 15]
#
# Prints per op:
#   - allocation sites (file:line, class), exact counts
#   - method calls (Ruby and C methods), exact counts
#   - executed engine source lines, exact counts (where the hot loops are)
# All counts are deterministic, so they are reliable targets for
# optimizations even when timing is noisy.
require "objspace"
$stdout.sync = true

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(ROOT) unless $LOAD_PATH.include?(ROOT)
require "app/d3d/d3d.rb"
require_relative "harness"
require_relative "scenes"
Dir[File.join(__dir__, "cases", "*.rb")].sort.each { |f| require f }

def option_value(flag, default)
  idx = ARGV.index(flag)
  idx ? ARGV[idx + 1] : default
end

name = ARGV.find { |a| !a.start_with?("--") && !%w[--iters --top].include?(ARGV[ARGV.index(a) - 1]) }
iters = option_value("--iters", "20").to_i
top = option_value("--top", "15").to_i
c = Bench::Registry.cases.find { |bc| bc.name == name }
unless c
  warn "usage: ruby bench/profile.rb CASE [--iters N] [--top N]"
  warn "cases: #{Bench::Registry.cases.map(&:name).join(', ')}"
  exit 1
end

fixture = c.setup ? c.setup.call : nil
3.times { c.body.call(fixture) } # warm up lazy caches

def short(path)
  path.to_s.sub("#{ROOT}/", "")
end

def print_table(title, rows, iters, top)
  puts title
  rows.sort_by { |_k, v| -v }.first(top).each do |key, count|
    puts format("  %10.1f  %s", count.to_f / iters, key)
  end
  puts
end

# ---------------------------------------------------------------- allocations
sites = Hash.new(0)
GC.disable
ObjectSpace.trace_object_allocations_start
iters.times { c.body.call(fixture) }
ObjectSpace.trace_object_allocations_stop
# Collect first, label later: allocating while walking the heap would make
# each_object visit its own garbage.
traced = []
ObjectSpace.each_object { |obj| traced << obj if ObjectSpace.allocation_sourcefile(obj) }
traced.each do |obj|
  sites["#{short(ObjectSpace.allocation_sourcefile(obj))}:#{ObjectSpace.allocation_sourceline(obj)} #{obj.class}"] += 1
end
traced = nil
ObjectSpace.trace_object_allocations_clear
GC.enable
total = sites.values.sum
puts "#{name}: #{format('%.1f', total.to_f / iters)} allocations per op (#{iters} ops)"
puts
print_table("allocations per op by site:", sites, iters, top)

# ---------------------------------------------------------------- calls
calls = Hash.new(0)
tp = TracePoint.new(:call, :c_call) do |t|
  calls["#{t.defined_class}##{t.method_id}"] += 1
end
tp.enable { iters.times { c.body.call(fixture) } }
print_table("method calls per op:", calls, iters, top)

# ---------------------------------------------------------------- lines
lines = Hash.new(0)
line_tp = TracePoint.new(:line) do |t|
  lines["#{short(t.path)}:#{t.lineno}"] += 1 if t.path.start_with?(ROOT)
end
line_tp.enable { iters.times { c.body.call(fixture) } }
print_table("executed engine lines per op (hot loops):", lines, iters, top)
