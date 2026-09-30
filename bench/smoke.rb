#!/usr/bin/env ruby
# Runs every demo headless in DragonRuby (mruby) for a few seconds, reports
# exceptions and saves one screenshot per demo, to catch mruby-only breakage
# and visual regressions that the CRuby tests can't see.
#
#   ruby bench/smoke.rb [--out DIR]     # screenshots go to DIR (default: $TMPDIR/d3d-smoke)
#
# Exit status: 0 all demos ran, 1 otherwise.
require "tmpdir"
require "fileutils"
require_relative "dragonruby"

idx = ARGV.index("--out")
out = File.expand_path(idx ? ARGV[idx + 1] : File.join(Dir.tmpdir, "d3d-smoke"))

work = Dir.mktmpdir("d3d-smoke-")
begin
  # Includes the optional C extension when built (bin/build-ext), so the demos
  # run the same code path as `bin/run`.
  game = Bench::DragonRuby.game_dir(work, "game", extra: ["sprites", "native", "models"])
  FileUtils.mkdir_p(File.join(game, "smoke"))
  FileUtils.cp(File.join(__dir__, "smoke_eval.rb"), File.join(game, "smoke_eval.rb"))
  log = Bench::DragonRuby.run(game, "smoke_eval.rb", no_tick: false, timeout: 180)
  report_path = File.join(game, "smoke/report.txt")
  report = File.exist?(report_path) ? File.read(report_path) : ""
  FileUtils.rm_rf(out)
  FileUtils.mkdir_p(out)
  Dir[File.join(game, "smoke/*.png")].each { |f| FileUtils.cp(f, out) }
  unless report.include?("DONE")
    puts "smoke: DragonRuby did not finish; log:"
    puts File.read(log).lines.last(30).join
    exit 1
  end
  puts report.sub("DONE\n", "")
  warnings = File.read(log).scan(/\* WARNING: (.+)$/).flatten.uniq
  warnings.each { |w| puts "DragonRuby warning: #{w}" }
  puts "screenshots: #{out}"
  exit(report.include?("FAIL") ? 1 : 0)
ensure
  FileUtils.rm_rf(work)
end
