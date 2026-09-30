#!/usr/bin/env ruby
# Correctness guard for optimizations: fingerprints the engine's output for the
# fixed scenes in golden_scenes.rb.
#
#   ruby bench/golden.rb                 # check against bench/golden.json
#   ruby bench/golden.rb --update        # rewrite bench/golden.json (explain why in the commit)
#   ruby bench/golden.rb --against REV   # compare full output with a git revision,
#                                        # floats within a tolerance (used by evaluate.rb)
#   ruby bench/golden.rb --dump --engine DIR   # internal: print canonical output as JSON
#
# Exit status: 0 match, 1 mismatch or error.
require "json"
require "digest"
require "open3"
require "tmpdir"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(ROOT) unless $LOAD_PATH.include?(ROOT)
GOLDEN_PATH = File.join(__dir__, "golden.json")
# Digests use floats rounded to this many decimals (screen px, colours).
DIGEST_DECIMALS = 2
# --against compares floats with this absolute/relative tolerance.
TOLERANCE = 1e-4

def option_value(flag)
  idx = ARGV.index(flag)
  idx ? ARGV[idx + 1] : nil
end

def load_engine(engine)
  if engine
    engine = File.expand_path(engine)
    Object.const_set(:D3D_ROOT, File.join(engine, "app/d3d"))
    require File.join(engine, "app/d3d/d3d.rb")
  else
    require "app/d3d/d3d.rb"
  end
  require_relative "scenes"
  require_relative "golden_scenes"
end

# Plain JSON-able data: floats stay floats, hashes become sorted pairs, engine
# objects become their data.
def canonical(value)
  case value
  when Float then value.zero? ? 0.0 : value
  when Integer, String, true, false, nil then value
  when Symbol then value.to_s
  when Array then value.map { |v| canonical(v) }
  when Hash then value.map { |k, v| [k.to_s, canonical(v)] }.sort_by(&:first)
  else
    if value.respond_to?(:x) && value.respond_to?(:y) && value.respond_to?(:z)
      [value.x, value.y, value.z].map { |v| canonical(v.to_f) }
    else
      value.class.name
    end
  end
end

def rounded(value)
  case value
  when Float
    r = value.round(DIGEST_DECIMALS)
    r.zero? ? 0.0 : r
  when Array then value.map { |v| rounded(v) }
  else value
  end
end

def dump_scenes
  GoldenScenes.all.each_with_object({}) do |(name, (ordered, fn)), out|
    data = canonical(fn.call)
    data = data.sort_by { |item| JSON.generate(rounded(item)) } if !ordered && data.is_a?(Array)
    out[name] = data
  rescue StandardError => e
    out[name] = { "error" => "#{e.class}: #{e.message}" }
  end
end

def fingerprint(data)
  count = data.is_a?(Array) ? data.size : 1
  { "count" => count, "digest" => Digest::SHA256.hexdigest(JSON.generate(rounded(data)))[0, 16] }
end

# Returns nil when a and b match within TOLERANCE, else a short path to the difference.
def diff(a, b, path = "")
  if a.is_a?(Numeric) && b.is_a?(Numeric)
    return nil if (a - b).abs <= TOLERANCE * [1.0, a.abs, b.abs].max

    return "#{path}: #{a} vs #{b}"
  end
  if a.is_a?(Array) && b.is_a?(Array)
    return "#{path}: #{a.size} vs #{b.size} entries" unless a.size == b.size

    a.each_with_index do |v, i|
      d = diff(v, b[i], "#{path}[#{i}]")
      return d if d
    end
    return nil
  end
  a == b ? nil : "#{path}: #{a.inspect[0, 80]} vs #{b.inspect[0, 80]}"
end

# ---------------------------------------------------------------- modes

if ARGV.include?("--dump")
  load_engine(option_value("--engine"))
  puts JSON.generate(dump_scenes)
  exit 0
end

if (rev = option_value("--against"))
  sha, err, status = Open3.capture3("git", "rev-parse", "--verify", "#{rev}^{commit}", chdir: ROOT)
  abort "Error: unknown revision #{rev}: #{err}" unless status.success?

  work = Dir.mktmpdir("d3d-golden-")
  begin
    archive, = Open3.capture2("git", "archive", "--format=tar", sha.strip, "app", chdir: ROOT, binmode: true)
    Open3.capture2("tar", "-x", "-C", work, stdin_data: archive, binmode: true)
    outputs = [work, ROOT].map do |dir|
      out, err, st = Open3.capture3("ruby", __FILE__, "--dump", "--engine", dir, chdir: ROOT)
      abort "Error: dump failed for #{dir}:\n#{err}" unless st.success?
      JSON.parse(out)
    end
  ensure
    FileUtils.rm_rf(work)
  end

  base, head = outputs
  failures = head.keys.map do |name|
    d = diff(base[name], head[name])
    d && "#{name}#{d}"
  end.compact
  if failures.empty?
    puts "golden: output matches #{rev} (#{head.size} scenes, tolerance #{TOLERANCE})"
    exit 0
  end
  puts "golden: output differs from #{rev}:"
  failures.each { |f| puts "  #{f}" }
  exit 1
end

load_engine(nil)
current = dump_scenes.transform_values { |data| fingerprint(data) }

if ARGV.include?("--update")
  File.write(GOLDEN_PATH, JSON.pretty_generate(current) + "\n")
  puts "golden: wrote #{current.size} fingerprints to #{GOLDEN_PATH}"
  exit 0
end

abort "golden: #{GOLDEN_PATH} missing, run with --update first" unless File.exist?(GOLDEN_PATH)
expected = JSON.parse(File.read(GOLDEN_PATH))
failures = (expected.keys | current.keys).map do |name|
  e = expected[name]
  c = current[name]
  next nil if e == c

  "#{name}: expected #{e ? "#{e['count']} items #{e['digest']}" : 'nothing'}, " \
    "got #{c ? "#{c['count']} items #{c['digest']}" : 'nothing'}"
end.compact

if failures.empty?
  puts "golden: #{current.size} scenes match"
  exit 0
end
puts "golden: #{failures.size} scene(s) changed:"
failures.each { |f| puts "  #{f}" }
puts "(if intended, run with --update and explain the change in the commit;"
puts " --against REV shows where the output differs)"
exit 1
