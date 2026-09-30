# Evaluated inside DragonRuby by smoke.rb (with ticking enabled): replaces the
# game's tick to start every registered demo in turn, run it for FRAMES ticks,
# take a screenshot and record exceptions. Writes smoke/report.txt, then quits.
SMOKE_FRAMES = 90
$smoke = { demo: 0, frames: 0, log: [], failed: false }

def tick(args)
  s = $smoke
  demos = Demos.demos
  klass = demos[s[:demo]]
  Demos.send(:start_demo, args, klass) if s[:frames] == 0
  begin
    Demos.tick(args)
    s[:frames] += 1
  rescue Exception => e # rubocop:disable Lint/RescueException -- report everything
    s[:log] << "FAIL #{klass.title}: #{e.class}: #{e.message} | #{e.backtrace.to_a.first(4).join(' | ')}"
    s[:failed] = true
    s[:frames] = SMOKE_FRAMES
  end
  if s[:frames] == SMOKE_FRAMES - 30
    # a: 255 disables the screenshot chroma key; without it pure black pixels
    # (e.g. fog fading into a [0, 0, 0] background) are saved transparent and
    # image viewers show them as white.
    args.outputs.screenshots << { x: 0, y: 0, w: 1280, h: 720, path: "smoke/demo_#{s[:demo] + 1}.png", a: 255 }
  end
  return if s[:frames] < SMOKE_FRAMES

  s[:log] << "ok #{klass.title} (#{SMOKE_FRAMES} frames, screenshot smoke/demo_#{s[:demo] + 1}.png)" unless s[:failed]
  s[:failed] = false
  s[:demo] += 1
  s[:frames] = 0
  Demos.instance_variable_set(:@active, nil)
  return if s[:demo] < demos.size

  $gtk.write_file("smoke/report.txt", s[:log].join("\n") + "\nDONE\n")
  $gtk.request_quit
end
