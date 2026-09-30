# Performance benchmark: stress scenes with adjustable load to find the limits
# of the engine. Shows frame time (tick to tick, includes DragonRuby's drawing),
# engine time (the render call alone) and triangle counts, with a frame time
# graph. The auto benchmark raises the load of every scene step by step until
# the median frame time no longer fits 60 fps and lists the last load that
# did (median, so single hiccups like a GC pause don't end a run). Light,
# the optional C extension (D3D::Native) and mruby's GC mode can be toggled
# to compare.
class PerfDemo
  TARGET_MS = 1000.0 / 60
  # Median frame time that still counts as 60 fps (timer jitter allowance).
  PASS_MS = TARGET_MS * 1.06
  GRAPH_SAMPLES = 180
  WARMUP_FRAMES = 20
  MEASURE_FRAMES = 45
  LIGHT = { direction: [0.4, 1.0, 0.3], ambient: 0.3 }.freeze
  BACKGROUND = [18, 20, 28].freeze

  MouseState = Struct.new(:mouse_captured)

  # n rotating spheres (512 triangles each, about half facing the camera).
  class SpheresScene
    TEXTURE = 'sprites/blocks/stone.png'.freeze

    attr_accessor :textured

    def name
      @textured ? 'Spheres (textured)' : 'Spheres'
    end

    def unit
      'spheres'
    end

    def loads
      [1, 2, 4, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256]
    end

    def build(n)
      @mesh ||= D3D.sphere_mesh(radius: 0.8, segments: 16, rings: 16)
      side = Math.sqrt(n).ceil
      @models = Array.new(n) do |i|
        x = (i % side - (side - 1) / 2.0) * 2.2
        z = ((i / side).to_i - (side - 1) / 2.0) * 2.2
        D3D::Model.new(mesh: @mesh, position: D3D::Vec3.new(x, 0.0, z), texture: @textured ? TEXTURE : nil,
                       color: { r: 80 + (i * 37) % 150, g: 140, b: 220 - (i * 23) % 120, a: 255 })
      end
      @radius = 4.0 + side * 1.6
    end

    def render(args, time, light)
      @models.each do |m|
        m.rotation.y = time * 0.8
        m.mark_dirty!
      end
      tris = D3D.render(PerfDemo.orbit_camera(time, @radius, @radius * 0.55), @models, light: light)
      args.outputs.primitives << tris
      tris.size
    end
  end

  # size x size voxel terrain (grass, dirt, stone) from a height field.
  class VoxelScene
    def name
      'Voxel terrain'
    end

    def unit
      'blocks per side'
    end

    def loads
      [8, 12, 16, 20, 24, 32, 40, 48, 64]
    end

    def build(size)
      @world = D3D::VoxelWorld.new
      size.times do |x|
        size.times do |z|
          h = 2 + ((Math.sin(x * 0.35) + Math.cos(z * 0.3)) * 2.5 + 2.5).to_i
          (0..h).each do |y|
            type = y == h ? :grass : (y > h - 3 ? :dirt : :stone)
            @world.add_block(x, y, z, { r: 255, g: 255, b: 255, a: 255 }, texture: "sprites/blocks/#{type}.png")
          end
        end
      end
      @world.build_mesh
      @size = size
    end

    def render(args, time, light)
      c = @size / 2.0
      cam = PerfDemo.orbit_camera(time, @size * 0.9 + 6, @size * 0.55 + 6, c, 3.0, c)
      tris = D3D.render_voxel_world(cam, @world, light: light)
      args.outputs.primitives << tris
      tris.size
    end
  end

  # size x size cavern with pillars in a cell grid, SceneRenderer with portal
  # culling, textures and two moving point lights.
  class CellGridScene
    CS = 10.0

    def name

      'Cell grid cavern'

    end

    def unit
      'cells per side'
    end

    def loads
      [4, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 64]
    end

    def build(size)
      @grid = D3D::CellGrid.new(size + 4, 8, size + 4, cell_size: CS)
      @grid.carve(2, size + 1, 2, 5, 2, size + 1, :rock, [0.8, 0.75, 0.7])
      # Pillars every 4 cells (mruby has no Range#step).
      i = 4
      while i < size
        k = 4
        while k < size
          @grid.fill(i, i, 2, 5, k, k)
          k += 4
        end
        i += 4
      end
      @grid.roughen(2, size + 1, 2, 5, 2, size + 1, size * 2, D3D::Lcg.new(3))
      @grid.rebuild_faces
      @renderer ||= D3D::SceneRenderer.new(
        focal: 620, fog: 600,
        materials: { rock: { path: 'sprites/cell_grid/rock.png', size: 128 } }
      )
      @size = size
    end

    def render(args, time, light)
      span = (@size + 4) * CS
      mid = span / 2.0
      ang = time * 0.25
      pos = [mid - Math.cos(ang) * span * 0.3, 38.0, mid - Math.sin(ang) * span * 0.3]
      pose = D3D::Pose.new(pos, [mid - pos[0], -6.0, mid - pos[2]])
      lights = []
      if light
        lights << { pos: [mid + Math.cos(time) * 40, 40.0, mid + Math.sin(time) * 40], radius: 60,
                    color: [1.0, 0.5, 0.2], intensity: 0.9 }
        lights << { pos: [mid, 45.0, mid + Math.cos(time * 0.7) * 60], radius: 60,
                    color: [0.3, 0.6, 1.0], intensity: 0.9 }
      end
      @renderer.begin_frame(pose, lights: lights)
      @renderer.draw_grid(@grid)
      @renderer.flush(args.outputs)
      @renderer.triangle_count
    end
  end

  # Instances of a detailed OBJ model (models/README.md): Blub (14,208
  # triangles) or Jerry the Ogre (39,856), flat lit.
  class MeshScene
    # name, file, yaw that turns the model's front towards the camera (+z)
    MODELS = [['Blub', 'models/blub.obj', 0.0], ['Ogre', 'models/ogre.obj', Math::PI]].freeze
    # Front light: the models face the camera, and a light from above would
    # leave their front at ambient level.
    FRONT_LIGHT = { direction: [0.35, 0.55, 1.0], ambient: 0.3 }.freeze

    attr_reader :model_index

    def initialize
      @model_index = 0
      @meshes = {}
    end

    def name

      "Detailed mesh: #{MODELS[@model_index][0]}"

    end

    def unit
      'models'
    end

    def loads
      [1, 2, 3, 4, 6, 9, 12, 16]
    end

    def next_model!
      @model_index = (@model_index + 1) % MODELS.size
    end

    def build(n)
      mesh, scale = load_mesh(MODELS[@model_index][1])
      @yaw = MODELS[@model_index][2]
      side = Math.sqrt(n).ceil
      @models = Array.new(n) do |i|
        x = (i % side - (side - 1) / 2.0) * 2.4
        y = ((i / side).to_i - (side - 1) / 2.0) * 2.4
        m = D3D::Model.new(mesh: mesh, position: D3D::Vec3.new(x, y, 0.0),
                           color: { r: 225, g: 200, b: 170, a: 255 })
        m.set_scale(scale)
        m
      end
      @distance = 2.2 + side * 2.4
    end

    def render(args, time, light)
      @models.each do |m|
        # The ogre's back of the head is open, so swing instead of spinning.
        m.rotation.y = @yaw + Math.sin(time * 0.7) * 0.6
        m.mark_dirty!
      end
      cam = D3D::Camera.new(position: D3D::Vec3.new(0.0, 0.3, @distance))
      cam.look_at(D3D::Vec3.new(0.0, 0.0, 0.0))
      tris = D3D.render(cam, @models, light: light && FRONT_LIGHT)
      args.outputs.primitives << tris
      tris.size
    end

    private

    # Mesh centred on the origin and the scale that makes it ~2 units tall.
    def load_mesh(path)
      @meshes[path] ||= begin
        mesh = D3D.load_obj(path)
        vs = mesh.vertices
        min = [vs.map(&:x).min, vs.map(&:y).min, vs.map(&:z).min]
        max = [vs.map(&:x).max, vs.map(&:y).max, vs.map(&:z).max]
        c = [(min[0] + max[0]) / 2, (min[1] + max[1]) / 2, (min[2] + max[2]) / 2]
        vs.each do |v|
          v.x -= c[0]
          v.y -= c[1]
          v.z -= c[2]
        end
        extent = [max[0] - min[0], max[1] - min[1], max[2] - min[2]].max
        [mesh, extent > 0 ? 2.0 / extent : 1.0]
      end
    end
  end

  # One decimal without Float#round's binary noise (mruby prints 69.1 as
  # 69.09999999999999).
  def self.fmt(ms)
    q, r = (ms * 10).round.divmod(10)
    "#{q}.#{r}"
  end

  # mruby's GC mode. With big meshes held (e.g. the ogre) the default
  # generational mode ran a full collection about every 8th render call
  # (~17 ms spikes); incremental mode spreads the work out.
  def self.gc_mode
    GC.generational_mode ? 'generational' : 'incremental'
  end

  def self.orbit_camera(time, radius, height, cx = 0.0, cy = 0.0, cz = 0.0)
    ang = time * 0.3
    cam = D3D::Camera.new(position: D3D::Vec3.new(cx + Math.cos(ang) * radius, cy + height,
                                                  cz + Math.sin(ang) * radius))
    cam.look_at(D3D::Vec3.new(cx, cy, cz))
    cam
  end

  def self.title
    'Performance Benchmark'
  end

  def self.description
    'Stress scenes with adjustable load, frame timing and an auto benchmark'
  end

  def setup(args)
    args.state.camera = MouseState.new(false)
    @scenes = [SpheresScene.new, VoxelScene.new, CellGridScene.new, MeshScene.new]
    @levels = [4, 2, 3, 0]
    @scene_index = 0
    @light = true
    @time = 0.0
    @frames = []
    @engine = []
    @last_clock = nil
    @auto = nil
    @results = []
    rebuild
  end

  def tick(args)
    now = Time.now.to_f
    frame_ms = @last_clock ? (now - @last_clock) * 1000.0 : TARGET_MS
    @last_clock = now
    @time += 1.0 / 60

    @auto ? auto_step(args, frame_ms) : handle_input(args)

    args.outputs.background_color = BACKGROUND
    t0 = Time.now.to_f
    @tris = scene.render(args, @time, @light ? LIGHT : nil)
    engine_ms = (Time.now.to_f - t0) * 1000.0

    push(@frames, frame_ms)
    push(@engine, engine_ms)
    hud(args)
  end

  private

  def scene
    @scenes[@scene_index]
  end

  def load_value
    scene.loads[@levels[@scene_index]]
  end

  def rebuild
    scene.build(load_value)
    # Building can take a while; don't count it as a frame.
    @last_clock = nil
  end

  def push(list, value)
    list << value
    list.shift while list.size > GRAPH_SAMPLES
  end

  def handle_input(args)
    kb = args.inputs.keyboard
    if kb.key_down.right || kb.key_down.left
      @scene_index = (@scene_index + (kb.key_down.right ? 1 : -1)) % @scenes.size
      rebuild
    end
    if kb.key_down.up || kb.key_down.down
      level = @levels[@scene_index] + (kb.key_down.up ? 1 : -1)
      if level >= 0 && level < scene.loads.size
        @levels[@scene_index] = level
        rebuild
      end
    end
    if kb.key_down.m && scene.is_a?(MeshScene)
      scene.next_model!
      rebuild
    end
    if kb.key_down.t && scene.is_a?(SpheresScene)
      scene.textured = !scene.textured
      rebuild
    end
    @light = !@light if kb.key_down.l
    D3D::Native.enabled = !D3D::Native.enabled? if kb.key_down.c
    GC.generational_mode = !GC.generational_mode if kb.key_down.g
    start_auto if kb.key_down.b
  end

  # ------------------------------------------------------------ auto benchmark

  def start_auto
    @results = []
    @auto = { scene: 0, samples: [], frames: 0, passed: nil }
    begin_auto_scene
  end

  def begin_auto_scene
    @scene_index = @auto[:scene]
    @levels[@scene_index] = 0
    @auto[:passed] = nil
    begin_auto_level
  end

  def begin_auto_level
    @auto[:frames] = 0
    @auto[:samples] = []
    @auto[:engine] = []
    @auto[:tris] = []
    rebuild
  end

  def auto_step(args, frame_ms)
    if args.inputs.keyboard.key_down.b || args.inputs.keyboard.key_down.escape
      @auto = nil
      return
    end
    a = @auto
    a[:frames] += 1
    if a[:frames] > WARMUP_FRAMES && @last_clock
      a[:samples] << frame_ms
      a[:engine] << (@engine.last || 0)
      a[:tris] << (@tris || 0)
    end
    return if a[:samples].size < MEASURE_FRAMES

    med = median(a[:samples])
    measured = { load: load_value, frame_ms: med, engine_ms: median(a[:engine]), tris: a[:tris].max }
    if med <= PASS_MS
      a[:passed] = measured
      if @levels[@scene_index] + 1 < scene.loads.size
        @levels[@scene_index] += 1
        begin_auto_level
        return
      end
    end
    finish_auto_scene(measured)
  end

  # last: the final measurement, either the first load over budget or the
  # highest level (which passed).
  def finish_auto_scene(last)
    @results << { scene: scene.name, unit: scene.unit, passed: @auto[:passed], last: last,
                  maxed: last[:frame_ms] <= PASS_MS, native: D3D::Native.enabled?, light: @light,
                  gc: PerfDemo.gc_mode }
    log_result(@results.last)
    @auto[:scene] += 1
    if @auto[:scene] < @scenes.size
      begin_auto_scene
    else
      @auto = nil
      @scene_index = 0
      rebuild
    end
  end

  def log_result(r)
    puts "D3D benchmark (C ext #{r[:native] ? 'on' : 'off'}, light #{r[:light] ? 'on' : 'off'}, GC #{r[:gc]}) #{result_text(r)}"
  end

  # "Spheres: 12 spheres - 2722 tris, engine 8.2 ms, frame 17.5 ms"; when even
  # the lowest load misses 60 fps, its measurement with "over budget".
  def result_text(r)
    m = r[:passed] || r[:last]
    text = "#{r[:scene]}: #{m[:load]} #{r[:unit]}#{r[:maxed] ? '+' : ''}  -  #{m[:tris]} tris, " \
           "engine #{PerfDemo.fmt(m[:engine_ms])} ms, frame #{PerfDemo.fmt(m[:frame_ms])} ms"
    r[:passed] ? text : "#{text} (over budget)"
  end

  def median(list)
    return 0.0 if list.empty?

    sorted = list.sort
    sorted[(sorted.size / 2).to_i]
  end

  def average(list)
    list.empty? ? 0.0 : list.inject(0.0) { |acc, v| acc + v } / list.size
  end

  # ------------------------------------------------------------ HUD

  def hud(args)
    out = args.outputs
    frame = average(@frames.last(30))
    engine = average(@engine.last(30))
    native = if D3D::Native.enabled?
               'on'
             else
               D3D::Native.loaded? ? 'off' : 'not loaded'
             end
    out.primitives << { x: 0, y: 560, w: 470, h: 160, path: :solid, r: 0, g: 0, b: 0, a: 150 }
    lines = [
      "#{scene.name}  (#{@scene_index + 1}/#{@scenes.size})",
      "Load: #{load_value} #{scene.unit}   Triangles: #{@tris}",
      "Frame: #{PerfDemo.fmt(frame)} ms   Engine: #{PerfDemo.fmt(engine)} ms   #{args.gtk.current_framerate.round} fps",
      "Light: #{@light ? 'on' : 'off'} (L)   C ext: #{native} (C)   GC: #{PerfDemo.gc_mode} (G)"
    ]
    lines << (@auto ? "AUTO BENCHMARK running - B or ESC to stop" : 'B: auto benchmark')
    lines.each_with_index do |t, i|
      out.labels << { x: 10, y: 710 - i * 28, text: t, size_enum: i.zero? ? 1 : -1,
                      r: i == 4 && @auto ? 255 : 220, g: 220, b: i == 4 && @auto ? 120 : 230 }
    end
    unless @auto
      out.labels << { x: 640, y: 24, alignment_enum: 1, size_enum: -1, r: 190, g: 190, b: 200,
                       text: 'Left/Right: scene | Up/Down: load | M: mesh model | T: textured spheres | L: light | C: C ext | G: GC mode | B: auto benchmark | ESC: menu' }
    end
    graph(out)
    results(out) unless @results.empty?
  end

  # Frame time (bars) and engine time (dots) of the last GRAPH_SAMPLES ticks;
  # the line marks 16.7 ms (60 fps).
  def graph(out)
    x0 = 1270 - GRAPH_SAMPLES * 2
    y0 = 560
    scale = 3.0 # px per ms
    out.primitives << { x: x0 - 6, y: y0 - 6, w: GRAPH_SAMPLES * 2 + 12, h: 160, path: :solid, r: 0, g: 0, b: 0, a: 150 }
    @frames.each_with_index do |ms, i|
      h = [ms * scale, 148].min
      r, g = ms <= PASS_MS ? [90, 200] : (ms <= TARGET_MS * 2 ? [230, 190] : [240, 80])
      out.primitives << { x: x0 + i * 2, y: y0, w: 2, h: h, path: :solid, r: r, g: g, b: 90, a: 220 }
    end
    @engine.each_with_index do |ms, i|
      out.primitives << { x: x0 + i * 2, y: y0 + [ms * scale, 148].min, w: 2, h: 2, path: :solid,
                          r: 120, g: 180, b: 255 }
    end
    out.primitives << { x: x0, y: y0 + TARGET_MS * scale, w: GRAPH_SAMPLES * 2, h: 1, path: :solid,
                        r: 255, g: 255, b: 255, a: 160 }
    out.labels << { x: x0, y: y0 + 150, text: 'frame ms (bars), engine ms (dots), line = 60 fps',
                    size_enum: -3, r: 200, g: 200, b: 210 }
  end

  def results(out)
    x = 10
    y = 520
    h = 36 + @results.size * 24
    out.primitives << { x: 0, y: y - h + 12, w: 780, h: h, path: :solid, r: 0, g: 0, b: 0, a: 170 }
    r0 = @results.first
    out.labels << { x: x, y: y, size_enum: -1, r: 255, g: 220, b: 140,
                    text: "Highest load at 60 fps (C extension #{r0[:native] ? 'on' : 'off'}, light #{r0[:light] ? 'on' : 'off'}, GC #{r0[:gc]})" }
    @results.each_with_index do |r, i|
      text = result_text(r)
      out.labels << { x: x, y: y - 26 - i * 24, text: text, size_enum: -1, r: 220, g: 220, b: 230 }
    end
  end
end

Demos.register(PerfDemo)
