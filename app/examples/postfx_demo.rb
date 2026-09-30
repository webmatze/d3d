# Cell-grid mine with post-processing: a small carved mine rendered with
# SceneRenderer, flown with a 6DOF Pose, with flat shaded meshes, glowing orbs
# with point lights and a Tab automap (GridMap), plus a full-screen HLSL
# fragment shader (DragonRuby Pro 7.16+ early-access shaders, enabled with
# shaders=true in metadata/game_metadata.txt). The engine output is unchanged;
# the shader only post-processes the finished image, HUD included. Without
# shader support the mine is shown as is.
#
# All effects live in one shader and a uniform picks one: switching between
# shaders or turning one off at runtime is unreliable in DragonRuby 7.21 (the
# old shader sticks or comes back, and it has crashed in render_shader), so the
# shader path never changes while the demo runs.
class PostFxDemo
  CS = 10.0
  MOUSE_SENS = 0.0032
  TURN_RATE = 2.3
  THRUST = 115.0
  DRAG = 2.9
  RADIUS = 2.4

  SHADER = 'shaders/postfx/postfx.frag.hlsl'.freeze
  EFFECTS = ['Off', 'Glow + grade', 'CRT', 'Retro dither', 'Haze'].freeze
  EFFECT_KEYS = [:one, :two, :three, :four, :five].freeze

  # Minimal stand-in for the camera the demo registry checks on ESC.
  MouseState = Struct.new(:mouse_captured)

  # Requiring an .hlsl file raises unless the license is Pro and shaders=true
  # is set, so check first (headless bench/smoke runs keep shaders off).
  def self.shaders_enabled?
    cvar = $gtk.args.cvars['game_metadata.shaders']
    !!(cvar && cvar.value && $gtk.version_pro?)
  rescue StandardError
    false
  end

  SHADERS = shaders_enabled?

  # Fog starts darkening walls near the camera either way. With the C
  # extension the view reaches 400 (the whole mine renders in ~1.5 ms) and
  # the exponential fog lets far cells fade out slowly; the Ruby fallback
  # keeps the linear fog ending at 140 (a longer view costs it up to 18 ms).
  FOG = 140
  VIEW_NATIVE = 400

  def self.title
    'Cell Grid Mine + Post-FX'
  end

  def self.description
    '6DOF mine: portal culling, lights, meshes, automap; HLSL post effects with Pro'
  end

  def setup(args)
    @grid = build_grid
    @renderer = D3D::SceneRenderer.new(
      focal: 620, fog: FOG,
      view_distance: D3D::Native.enabled? ? VIEW_NATIVE : FOG,
      fog_mode: D3D::Native.enabled? ? :exponential : :linear,
      materials: {
        rock:  { path: 'sprites/cell_grid/rock.png', size: 128 },
        metal: { path: 'sprites/cell_grid/metal.png', size: 128 },
        tech:  { path: 'sprites/cell_grid/tech.png', size: 128 }
      }
    )
    @map = D3D::GridMap.new(@grid)
    @pose = D3D::Pose.new([55.0, 45.0, 30.0], [0.0, 0.0, 1.0])
    @vel = [0.0, 0.0, 0.0]
    @spin = [0.0, 0.0, 0.0]
    @show_map = false
    @time = 0.0
    @crystal = D3D::FlatMesh.new.bipyramid(6, 2.0, 3.0, 3.0, [[90, 200, 255], [60, 140, 220]], axis: :y)
    @crate = D3D::FlatMesh.new.box(0, 0, 0, 2.5, 2.5, 2.5, [200, 150, 80], [150, 110, 60])
    @effect = SHADERS ? 1 : 0
    @strength = 1.0
    args.state.camera = MouseState.new(false)
  end

  def tick(args)
    @time += 1.0 / 60
    kb = args.inputs.keyboard
    EFFECT_KEYS.each_with_index { |k, i| @effect = i if kb.key_down.send(k) }
    @strength = D3D.clamp(@strength - 0.1, 0.0, 1.0) if kb.key_down.n
    @strength = D3D.clamp(@strength + 0.1, 0.0, 1.0) if kb.key_down.m
    # Every tick, automap included, so the shader is never switched off.
    apply_shader(args) if SHADERS

    handle_mouse_capture(args)
    @show_map = !@show_map if kb.key_down.tab
    if @show_map
      @map.open(@pose) if kb.key_down.tab
      @map.update(args.inputs)
      args.outputs.background_color = [0, 0, 0]
      @map.render(args.outputs, @pose)
      hud(args, 'AUTOMAP  -  mouse / arrows / A D rotate, W S zoom, Tab back')
      return
    end

    fly(args)
    render(args)
    hud(args, 'Mouse / arrows: look | W S: thrust | A D: slide | R F: up/down | Q E: roll | Tab: map | click: capture mouse')
  end

  private

  def build_grid
    g = D3D::CellGrid.new(24, 12, 30, cell_size: CS)
    g.carve 3, 8, 3, 6, 2, 7, :metal, [1.0, 1.0, 1.05]      # start room
    g.carve 5, 6, 4, 5, 8, 14, :rock, [0.8, 0.7, 0.6]        # tunnel
    g.carve 2, 16, 2, 9, 15, 25, :rock, [0.8, 0.7, 0.6]      # cavern
    g.fill 8, 9, 2, 9, 19, 20                                # pillar
    g.carve 17, 21, 4, 7, 18, 22, :tech, [0.8, 0.9, 1.15]    # side vault
    g.roughen 2, 16, 2, 9, 15, 25, 20, D3D::Lcg.new(7)
    g.rebuild_faces
  end

  def apply_shader(args)
    args.outputs.shader = {
      path: SHADER,
      uniforms: [
        { type: :float, value: @time },
        { type: :float, value: 1280.0 },
        { type: :float, value: 720.0 },
        { type: :float, value: @strength },
        { type: :float, value: @effect.to_f }
      ]
    }
  end

  def handle_mouse_capture(args)
    cam = args.state.camera
    if args.inputs.mouse.click && !cam.mouse_captured
      cam.mouse_captured = true
      args.gtk.set_mouse_grab(2)
    elsif args.inputs.keyboard.key_down.escape && cam.mouse_captured
      cam.mouse_captured = false
      args.gtk.set_mouse_grab(0)
    end
  end

  def fly(args)
    kb = args.inputs.keyboard
    ms = args.inputs.mouse
    dt = 1.0 / 60
    want = [0.0, 0.0, 0.0]
    want[0] += 1 if kb.up_arrow
    want[0] -= 1 if kb.down_arrow
    want[1] += 1 if kb.right_arrow
    want[1] -= 1 if kb.left_arrow
    want[2] += 1 if kb.e
    want[2] -= 1 if kb.q
    3.times { |n| @spin[n] += (want[n] * TURN_RATE - @spin[n]) * 0.2 }
    mdx = args.state.camera.mouse_captured ? (ms.relative_x || 0) : 0
    mdy = args.state.camera.mouse_captured ? (ms.relative_y || 0) : 0
    @pose.yaw!(@spin[1] * dt + mdx * MOUSE_SENS)
    @pose.pitch!(@spin[0] * dt + mdy * MOUSE_SENS)
    @pose.roll!(@spin[2] * dt)
    @pose.orthonormalize!

    thrust = (kb.w ? 1 : 0) - (kb.s ? 1 : 0)
    slide_x = (kb.d ? 1 : 0) - (kb.a ? 1 : 0)
    slide_y = (kb.r ? 1 : 0) - (kb.f ? 1 : 0)
    acc = D3D::V.scale(@pose.fwd, thrust * THRUST)
    acc = D3D::V.madd(acc, @pose.right, slide_x * THRUST * 0.85)
    acc = D3D::V.madd(acc, @pose.up, slide_y * THRUST * 0.85)
    @vel = D3D::V.scale(D3D::V.madd(@vel, acc, dt), 1.0 - DRAG * dt)
    @pose.position = D3D::V.madd(@pose.position, @vel, dt)
    hit = @grid.collide_sphere(@pose.position, RADIUS)
    if hit
      vn = D3D::V.dot(@vel, hit)
      @vel = D3D::V.madd(@vel, hit, -vn * 1.4) if vn < 0
    end
  end

  def render(args)
    args.outputs.background_color = [0, 0, 0]
    orbs = [
      [[90.0 + Math.cos(@time) * 30, 55.0, 200.0 + Math.sin(@time) * 30], [255, 120, 40]],
      [[190.0, 55.0 + Math.sin(@time * 2) * 10, 200.0], [80, 160, 255]]
    ]
    lights = orbs.map { |p, c| { pos: p, radius: 45, color: c.map { |v| v / 255.0 }, intensity: 0.9 } }
    r = @renderer
    r.begin_frame(@pose, lights: lights)
    r.draw_grid(@grid)
    @map.explore(r.last_visible, @pose.position)

    spin_fwd = [Math.sin(@time), 0.0, Math.cos(@time)]
    right, up = D3D::V.basis_from_forward(spin_fwd)
    r.draw_mesh(@crystal, [150.0, 50.0, 230.0], right, up, spin_fwd, 1.0, @grid.tint_at([150.0, 50.0, 230.0]))
    r.draw_mesh(@crate, [60.0, 40.0, 60.0], right, up, spin_fwd, 1.0, @grid.tint_at([60.0, 40.0, 60.0]))
    orbs.each do |p, c|
      r.draw_glow(p, 8.0, c[0], c[1], c[2], 200)
      r.draw_glow(p, 2.5, 255, 255, 255)
    end
    r.flush(args.outputs)
  end

  def hud(args, text)
    args.outputs.labels << { x: 640, y: 30, text: text, size_enum: -1, alignment_enum: 1,
                             r: 200, g: 200, b: 210 }
    args.outputs.labels << { x: 10, y: 710, text: "#{args.gtk.current_framerate.round} fps  #{@renderer.triangle_count} tris",
                             size_enum: -1, r: 200, g: 200, b: 210 }
    status = if SHADERS
               "Effect: #{EFFECTS[@effect]} (1-5)  strength #{(@strength * 100).round}% (N M)"
             else
               'Shaders off: needs DragonRuby Pro and shaders=true in metadata/game_metadata.txt'
             end
    args.outputs.labels << { x: 1270, y: 710, text: status, size_enum: -1, alignment_enum: 2,
                             r: 255, g: 220, b: 140 }
  end
end

require PostFxDemo::SHADER if PostFxDemo::SHADERS

Demos.register(PostFxDemo)
