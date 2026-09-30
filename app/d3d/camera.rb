module D3D
  class Camera
    attr_accessor :position, :pitch, :yaw, :fov, :near, :far, :aspect
    attr_accessor :move_speed, :look_sensitivity, :mouse_captured

    def initialize(position: nil, fov: 70, near: 0.1, far: 1000, aspect: nil)
      @position = position || Vec3.new(0, 0, 0)
      @pitch = 0.0
      @yaw = 0.0
      @fov = fov
      @near = near
      @far = far
      @aspect = aspect || (D3D::SCREEN_WIDTH.to_f / D3D::SCREEN_HEIGHT)

      @move_speed = 5.0
      @look_sensitivity = 0.002
      @mouse_captured = false

      @view_matrix = nil
      @projection_matrix = nil
      @view_dirty = true
      @projection_dirty = true
    end

    def position=(value)
      @position = value
      @view_dirty = true
    end

    def invalidate_view!
      @view_dirty = true
    end

    def look_at(target, up = Vec3.up)
      direction = (target - @position).normalize
      @pitch = Math.asin(-direction.y)
      @yaw = Math.atan2(direction.x, -direction.z)
      @view_dirty = true
      self
    end

    def forward
      Vec3.new(
        Math.sin(@yaw) * Math.cos(@pitch),
        -Math.sin(@pitch),
        -Math.cos(@yaw) * Math.cos(@pitch)
      )
    end

    def right
      Vec3.new(
        Math.cos(@yaw),
        0,
        Math.sin(@yaw)
      )
    end

    def up
      right.cross(forward).normalize
    end

    def get_view_matrix
      if @view_dirty || @view_matrix.nil?
        @view_matrix = calculate_view_matrix
        @view_dirty = false
      end
      @view_matrix
    end

    def get_projection_matrix
      if @projection_dirty || @projection_matrix.nil?
        @projection_matrix = Mat4.perspective(@fov, @aspect, @near, @far)
        @projection_dirty = false
      end
      @projection_matrix
    end

    def fov=(value)
      @fov = value
      @projection_dirty = true
    end

    def near=(value)
      @near = value
      @projection_dirty = true
    end

    def far=(value)
      @far = value
      @projection_dirty = true
    end

    def aspect=(value)
      @aspect = value
      @projection_dirty = true
    end

    def first_person_movement(args)
      dt = args.state.dt || (1.0 / 60.0)
      speed = @move_speed * dt

      kb = args.inputs.keyboard

      move_dir = Vec3.zero
      fwd = forward
      fwd.y = 0
      fwd = fwd.normalize

      rgt = right

      if kb.key_held.w || kb.key_held.up
        move_dir = move_dir + fwd
      end
      if kb.key_held.s || kb.key_held.down
        move_dir = move_dir - fwd
      end
      if kb.key_held.a || kb.key_held.left
        move_dir = move_dir - rgt
      end
      if kb.key_held.d || kb.key_held.right
        move_dir = move_dir + rgt
      end
      if kb.key_held.space
        move_dir.y += 1
      end
      if kb.key_held.shift
        move_dir.y -= 1
      end

      if move_dir.length_squared > 0
        move_dir = move_dir.normalize * speed
        @position = @position + move_dir
        @view_dirty = true
      end

      self
    end

    def capture_mouse!(args)
      @mouse_captured = true
      # Grab mode 2: confine + hide cursor + relative mouse mode (endless turning)
      args.gtk.set_mouse_grab 2 rescue nil
    end

    def release_mouse!(args)
      @mouse_captured = false
      args.gtk.set_mouse_grab 0 rescue nil
    end

    def first_person_look(args)
      mouse = args.inputs.mouse

      capture_mouse!(args) if mouse.click && !@mouse_captured

      release_mouse!(args) if args.inputs.keyboard.key_down.escape

      if @mouse_captured
        dx = mouse.relative_x || 0
        dy = mouse.relative_y || 0

        @yaw += dx * @look_sensitivity
        @pitch -= dy * @look_sensitivity

        max_pitch = Math::PI / 2 - 0.01
        @pitch = [[@pitch, -max_pitch].max, max_pitch].min

        @view_dirty = true if dx != 0 || dy != 0
      end

      self
    end

    def screen_to_ray(screen_x, screen_y)
      ndc_x = (2.0 * screen_x / D3D::SCREEN_WIDTH) - 1.0
      ndc_y = (2.0 * screen_y / D3D::SCREEN_HEIGHT) - 1.0

      fov_rad = @fov * Math::PI / 180.0
      tan_half_fov = Math.tan(fov_rad / 2.0)

      ray_dir = Vec3.new(
        ndc_x * @aspect * tan_half_fov,
        ndc_y * tan_half_fov,
        -1.0
      )

      cos_yaw = Math.cos(@yaw)
      sin_yaw = Math.sin(@yaw)
      cos_pitch = Math.cos(@pitch)
      sin_pitch = Math.sin(@pitch)

      rotated = Vec3.new(
        ray_dir.x * cos_yaw + ray_dir.z * sin_yaw,
        ray_dir.x * sin_yaw * sin_pitch + ray_dir.y * cos_pitch - ray_dir.z * cos_yaw * sin_pitch,
        -ray_dir.x * sin_yaw * cos_pitch + ray_dir.y * sin_pitch + ray_dir.z * cos_yaw * cos_pitch
      )

      rotated.normalize
    end

    private

    def calculate_view_matrix
      pos = @position
      px = pos.x
      py = pos.y
      pz = pos.z
      cos_pitch = Math.cos(@pitch)
      # target = position + forward (same expressions as #forward)
      tx = px + Math.sin(@yaw) * cos_pitch
      ty = py + -Math.sin(@pitch)
      tz = pz + -Math.cos(@yaw) * cos_pitch
      Mat4.look_at_scalar(px, py, pz, tx, ty, tz, 0.0, 1.0, 0.0)
    end
  end
end
