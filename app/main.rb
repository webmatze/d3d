require 'app/d3d/d3d.rb'

# mruby's default generational GC ran a full collection about every 8th frame
# once big meshes were loaded (~17 ms spikes); incremental mode spreads the
# work and was also 13-15% faster without them (see README, Performance Tips).
GC.generational_mode = false if GC.respond_to?(:generational_mode=)

# Optional C extension (D3D Pro, needs DragonRuby Indie or Pro); the engine
# falls back to pure Ruby when it isn't available.
D3D::Native.load

require 'app/demo_registry.rb'

# Demos register themselves with Demos.register at the bottom of their file.
# To add a new demo: create a class in app/examples/ and require it here.
require 'app/examples/basic_demo.rb'
require 'app/examples/minecraft_demo.rb'
require 'app/examples/postfx_demo.rb'
require 'app/examples/perf_demo.rb'

def tick(args)
  Demos.tick(args)
end
