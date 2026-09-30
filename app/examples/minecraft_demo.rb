# Minecraft-style voxel world demo: terrain generation, survival-style player
# physics, block breaking/placing with a hotbar.
class MinecraftDemo
  PLACEABLE_BLOCKS = [:grass, :dirt, :stone, :wood, :leaves].freeze
  REACH = 4.5
  # Sunlight from above: tops are brightest, sides and undersides darker.
  # (No fog: textures are tinted multiplicatively and can't fade to sky blue.)
  SUN = { direction: [0.4, 1.0, 0.25], ambient: 0.55 }.freeze
  SKY = [135, 190, 235].freeze

  def self.title
    "Minecraft World"
  end

  def self.description
    "Voxel terrain with player physics, block breaking and placing"
  end

  def setup(args)
    args.state.camera = D3D::Camera.new(
      position: D3D::Vec3.new(8, 15, 25),
      fov: 70
    )
    args.state.voxel_world = generate_world
    spawn_y = terrain_height(8, 8) + 1
    args.state.player = Player.new(8.5, spawn_y, 8.5)
    args.state.selected_block = :dirt
    args.state.camera.capture_mouse!(args)
    args.state.was_captured = true
  end

  def tick(args)
    args.state.dt = 1.0 / 60.0
    args.state.camera.first_person_look(args)
    args.state.player.update(args, args.state.voxel_world, args.state.camera)

    args.state.target_block = args.state.voxel_world.raycast(
      args.state.camera.position, args.state.camera.forward, REACH
    )
    handle_block_interaction(args)

    args.outputs.background_color = SKY
    args.outputs.primitives << D3D.render_voxel_world(args.state.camera, args.state.voxel_world, light: SUN)
    render_block_outline(args)
    render_ui(args)
  end

  # ============================================
  # PLAYER (gameplay layer on top of D3D::VoxelBody physics)
  # ============================================
  class Player
    # Minecraft constants (blocks are 1m)
    EYE_HEIGHT = 1.62
    JUMP_VELOCITY = 8.4
    WALK_SPEED = 4.317
    SPRINT_SPEED = 5.612
    SNEAK_SPEED = 1.31
    SPRINT_FOV_BOOST = 10

    attr_reader :sprinting, :sneaking

    def initialize(x, y, z)
      @body = D3D::VoxelBody.new(x, y, z, width: 0.6, height: 1.8,
                                          gravity: 32.0, terminal_velocity: -78.0)
      @sprinting = false
      @sneaking = false
      @last_w_down = -100
      @base_fov = nil
    end

    def on_ground
      @body.on_ground
    end

    def update(args, world, camera)
      dt = args.state.dt
      kb = args.inputs.keyboard

      # Sneak / sprint state (Minecraft: sprint via Ctrl or double-tap W; sneak cancels sprint)
      @sneaking = kb.key_held.shift ? true : false
      if kb.key_down.w
        @sprinting = true if args.tick_count - @last_w_down <= 15 && !@sneaking
        @last_w_down = args.tick_count
      end
      @sprinting = true if kb.key_held.control && kb.key_held.w && !@sneaking
      @sprinting = false if @sneaking || !(kb.key_held.w || kb.key_held.up)

      # Wish direction relative to camera yaw, horizontal only
      fwd = camera.forward
      fwd.y = 0
      fwd = fwd.length_squared > 0 ? fwd.normalize : D3D::Vec3.new(0, 0, -1)
      rgt = camera.right

      wish = D3D::Vec3.new(0, 0, 0)
      wish = wish + fwd if kb.key_held.w || kb.key_held.up
      wish = wish - fwd if kb.key_held.s || kb.key_held.down
      wish = wish - rgt if kb.key_held.a || kb.key_held.left
      wish = wish + rgt if kb.key_held.d || kb.key_held.right

      speed = @sneaking ? SNEAK_SPEED : (@sprinting ? SPRINT_SPEED : WALK_SPEED)
      if wish.length_squared > 0
        wish = wish.normalize
        @body.velocity.x = wish.x * speed
        @body.velocity.z = wish.z * speed
      else
        @body.velocity.x = 0
        @body.velocity.z = 0
      end

      # Jump
      @body.velocity.y = JUMP_VELOCITY if kb.key_held.space && @body.on_ground

      # Physics: gravity + axis-by-axis collision (sneak prevents walking off edges)
      @body.move(world, dt, prevent_falling: @sneaking)

      # Safety net: fell out of the world
      if @body.position.y < -20
        @body.position = D3D::Vec3.new(8.5, 15, 8.5)
        @body.velocity = D3D::Vec3.new(0, 0, 0)
      end

      # Sprint FOV boost like Minecraft
      @base_fov ||= camera.fov
      target_fov = @sprinting ? @base_fov + SPRINT_FOV_BOOST : @base_fov
      camera.fov = camera.fov + (target_fov - camera.fov) * 0.3 if (camera.fov - target_fov).abs > 0.1

      camera.position = eye_position
    end

    def eye_position
      eye = @sneaking ? EYE_HEIGHT - 0.27 : EYE_HEIGHT
      pos = @body.position
      D3D::Vec3.new(pos.x, pos.y + eye, pos.z)
    end

    def intersects_block?(bx, by, bz)
      @body.intersects_block?(bx, by, bz)
    end
  end

  private

  # ============================================
  # BLOCK BREAKING / PLACING
  # ============================================
  def handle_block_interaction(args)
    camera = args.state.camera
    world = args.state.voxel_world
    mouse = args.inputs.mouse

    # Block selection hotbar (1-5)
    number_keys = [:one, :two, :three, :four, :five]
    PLACEABLE_BLOCKS.each_with_index do |type, i|
      args.state.selected_block = type if args.inputs.keyboard.key_down.send(number_keys[i])
    end

    unless camera.mouse_captured
      args.state.was_captured = false
      return
    end

    # Ignore the click that captured the mouse
    if !args.state.was_captured
      args.state.was_captured = true
      args.state.prev_left = mouse.button_left
      args.state.prev_right = mouse.button_right
      return
    end

    # Edge detection for mouse buttons
    left_down = mouse.button_left && !args.state.prev_left
    right_down = mouse.button_right && !args.state.prev_right
    args.state.prev_left = mouse.button_left
    args.state.prev_right = mouse.button_right

    return unless left_down || right_down

    hit = args.state.target_block
    return unless hit

    if left_down
      block = world.get_block(hit[:x], hit[:y], hit[:z])
      # Bedrock is unbreakable, like in Minecraft
      unless block && block[:texture].to_s.include?("bedrock")
        world.remove_block(hit[:x], hit[:y], hit[:z])
        world.rebuild!
      end
    elsif right_down
      px = hit[:x] + hit[:normal][0]
      py = hit[:y] + hit[:normal][1]
      pz = hit[:z] + hit[:normal][2]
      # Don't place a block inside the player
      unless args.state.player.intersects_block?(px, py, pz) || world.has_block?(px, py, pz)
        type = args.state.selected_block
        world.add_block(px, py, pz, block_color(type), texture: block_texture(type))
        world.rebuild!
      end
    end
  end

  # ============================================
  # WORLD GENERATION
  # ============================================
  def generate_world
    world = D3D::VoxelWorld.new
    world_size = 16

    world_size.times do |x|
      world_size.times do |z|
        height = terrain_height(x, z)

        (height + 1).times do |y|
          block_type = block_type_at(y, height)
          color = block_color(block_type)
          texture = block_texture(block_type)
          world.add_block(x, y, z, color, texture: texture)
        end
      end
    end

    add_trees(world, world_size)
    world.build_mesh
    world
  end

  def terrain_height(x, z)
    base = 3
    h1 = Math.sin(x * 0.3) * 2
    h2 = Math.cos(z * 0.4) * 2
    h3 = Math.sin((x + z) * 0.2) * 1.5
    (base + h1 + h2 + h3).to_i.clamp(1, 8)
  end

  def block_type_at(y, surface_height)
    if y == surface_height
      :grass
    elsif y >= surface_height - 2
      :dirt
    elsif y == 0
      :bedrock
    else
      :stone
    end
  end

  def block_color(type)
    case type
    when :grass then { r: 86, g: 152, b: 59, a: 255 }
    when :dirt then { r: 134, g: 96, b: 67, a: 255 }
    when :stone then { r: 128, g: 128, b: 128, a: 255 }
    when :bedrock then { r: 60, g: 60, b: 60, a: 255 }
    when :wood then { r: 156, g: 110, b: 60, a: 255 }
    when :leaves then { r: 56, g: 118, b: 40, a: 220 }
    else { r: 255, g: 0, b: 255, a: 255 }
    end
  end

  def block_texture(type)
    case type
    when :grass then "sprites/blocks/grass.png"
    when :dirt then "sprites/blocks/dirt.png"
    when :stone then "sprites/blocks/stone.png"
    when :bedrock then "sprites/blocks/bedrock.png"
    when :wood then "sprites/blocks/wood.png"
    when :leaves then "sprites/blocks/leaves.png"
    else nil
    end
  end

  def add_trees(world, world_size)
    [[3, 5], [7, 3], [12, 8], [5, 12], [10, 14], [14, 4]].each do |tx, tz|
      next if tx >= world_size || tz >= world_size

      ground_height = terrain_height(tx, tz)
      trunk_height = 4 + (tx * tz) % 2

      trunk_height.times do |i|
        world.add_block(tx, ground_height + 1 + i, tz, block_color(:wood), texture: block_texture(:wood))
      end

      tree_top = ground_height + 1 + trunk_height
      (-2..2).each do |dx|
        (-2..2).each do |dz|
          (-1..2).each do |dy|
            dist = dx.abs + dz.abs
            next if dist > 3 || (dy == 2 && dist > 1) || (dy == -1 && dist > 2)
            next if dx == 0 && dz == 0 && dy < 1

            world.add_block(tx + dx, tree_top + dy, tz + dz, block_color(:leaves), texture: block_texture(:leaves))
          end
        end
      end
    end
  end

  # ============================================
  # RENDERING HELPERS / UI
  # ============================================

  # Outline around the targeted face of the block under the crosshair
  def render_block_outline(args)
    hit = args.state.target_block
    return unless hit

    corners = D3D::VoxelWorld.face_corners(hit)
    return unless corners

    points = corners.map { |cx, cy, cz| D3D::Renderer.project_point(args.state.camera, cx, cy, cz) }
    return if points.any?(&:nil?)

    4.times do |i|
      pa = points[i]
      pb = points[(i + 1) % 4]
      args.outputs.primitives << {
        x: pa[0], y: pa[1], x2: pb[0], y2: pb[1],
        r: 20, g: 20, b: 20, a: 200,
        primitive_marker: :line
      }
    end
  end

  def render_ui(args)
    vw = args.state.voxel_world
    mesh = vw.mesh_data
    face_count = mesh ? mesh[:faces].size : 0

    args.outputs.labels << { x: 10, y: 710, text: "Minecraft-style World (Optimized)", size_enum: 2, r: 255, g: 255, b: 255 }
    args.outputs.labels << { x: 10, y: 680, text: "WASD: Move | Space: Jump | Shift: Sneak | Ctrl/Double-W: Sprint | LMB: Break | RMB: Place | 1-5: Block | ESC: Release mouse", size_enum: 0, r: 200, g: 200, b: 200 }
    args.outputs.labels << { x: 10, y: 655, text: "Camera: #{format_vec3(args.state.camera.position)} | Block: #{args.state.selected_block}", size_enum: 0, r: 200, g: 200, b: 200 }
    args.outputs.labels << { x: 10, y: 630, text: "Blocks: #{vw.block_count} | Visible faces: #{face_count}", size_enum: 0, r: 200, g: 200, b: 200 }
    args.outputs.labels << { x: 1270, y: 20, text: "#{args.gtk.current_framerate.to_i} FPS", size_enum: 0, r: 200, g: 200, b: 200, alignment_enum: 2 }
    args.outputs.labels << { x: 640, y: 100, text: "Click to capture mouse", size_enum: 1, r: 255, g: 255, b: 255, alignment_enum: 1 } unless args.state.camera.mouse_captured

    # Crosshair (as primitives after the 3D world, so it renders in front)
    args.outputs.primitives << { x: 640 - 8, y: 360 - 1, w: 16, h: 2, r: 255, g: 255, b: 255, a: 180, path: :solid }
    args.outputs.primitives << { x: 640 - 1, y: 360 - 8, w: 2, h: 16, r: 255, g: 255, b: 255, a: 180, path: :solid }
  end

  def format_vec3(v)
    "(#{v.x.round(2)}, #{v.y.round(2)}, #{v.z.round(2)})"
  end
end

Demos.register(MinecraftDemo)
