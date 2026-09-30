# Runs the benchmark cases inside DragonRuby (mruby), headless:
#
#   SDL_VIDEODRIVER=dummy dragonruby <game_dir> --eval bench/mruby_runner.rb --no-tick
#
# compare.rb --mruby drives this. It reads bench/mruby_config.txt
# ("filter=..." / "rounds=..." / "native=1" lines) and writes bench/mruby_results.tsv:
# "name<TAB>ns_per_op<TAB>noise" or "name<TAB>ERROR<TAB>message" per case,
# followed by a final "DONE" line.
CASE_FILES = %w[math_bench render_bench voxel_bench physics_bench cell_grid_bench].freeze

def mruby_bench_config
  cfg = {}
  text = $gtk.read_file("bench/mruby_config.txt") || ""
  text.split("\n").each do |line|
    key, value = line.split("=", 2)
    cfg[key.strip] = value.strip if key && value
  end
  cfg
end

def run_mruby_bench
  require "bench/harness.rb"
  require "bench/scenes.rb"
  CASE_FILES.each { |f| require "bench/cases/#{f}.rb" }

  cfg = mruby_bench_config
  # Fixed GC mode for both sides of an A/B, whatever app/main.rb sets:
  # "gc=generational" in the config, incremental otherwise (as the demos use).
  GC.generational_mode = cfg["gc"] == "generational" if GC.respond_to?(:generational_mode=)
  GC.start
  if cfg["native"] == "1" && !(D3D.constants.include?(:Native) && D3D::Native.load)
    raise "native=1 but the C extension did not load (run bin/build-ext)"
  end
  filter = cfg["filter"]
  rounds = (cfg["rounds"] || "5").to_i
  lines = []
  Bench::Registry.cases.each do |c|
    next if filter && !filter.empty? && !c.name.include?(filter)

    begin
      stats = Bench::Timer.measure(setup: c.setup, body: c.body, rounds: rounds,
                                   target_time: 0.2, warmup_time: 0.2)
      lines << "#{c.name}\t#{stats[:ns_per_op]}\t#{stats[:noise]}"
    rescue StandardError => e
      lines << "#{c.name}\tERROR\t#{e.class}: #{e.message}"
    end
  end
  lines << "DONE"
  $gtk.write_file("bench/mruby_results.tsv", lines.join("\n") + "\n")
end

begin
  run_mruby_bench
rescue Exception => e # rubocop:disable Lint/RescueException -- must always quit
  $gtk.write_file("bench/mruby_results.tsv", "FATAL\t#{e.class}: #{e.message}\n")
end
$gtk.request_quit
