module D3D
  # Axis-aligned character/entity body for VoxelWorld: an AABB (width x height,
  # position = feet center) moved axis by axis with collision resolution.
  # Gameplay concerns (input, sprint, FOV, ...) stay in the application.
  class VoxelBody
    SKIN = 0.001

    attr_accessor :position, :velocity, :width, :height, :gravity, :terminal_velocity
    attr_reader :on_ground

    def initialize(x, y, z, width: 0.6, height: 1.8, gravity: 32.0, terminal_velocity: -78.0)
      @position = Vec3.new(x, y, z)
      @velocity = Vec3.new(0, 0, 0)
      @width = width
      @height = height
      @gravity = gravity
      @terminal_velocity = terminal_velocity
      @on_ground = false
    end

    # Integrates gravity and moves the body axis by axis through the world.
    # prevent_falling: while on the ground, refuse horizontal moves that would
    # leave the body without ground below (Minecraft-style sneaking).
    def move(world, dt, prevent_falling: false)
      @velocity.y -= @gravity * dt
      @velocity.y = @terminal_velocity if @velocity.y < @terminal_velocity

      edge_guard = prevent_falling && @on_ground
      move_axis(world, :x, @velocity.x * dt, edge_guard: edge_guard)
      move_axis(world, :z, @velocity.z * dt, edge_guard: edge_guard)
      move_y(world, @velocity.y * dt)
      self
    end

    def colliding?(world)
      half = @width / 2.0
      px = @position.x
      py = @position.y
      pz = @position.z
      world.aabb_intersects_xyz?(px - half, py, pz - half, px + half, py + @height, pz + half)
    end

    def intersects_block?(bx, by, bz)
      half = @width / 2.0
      @position.x + half > bx && @position.x - half < bx + 1 &&
        @position.y + @height > by && @position.y < by + 1 &&
        @position.z + half > bz && @position.z - half < bz + 1
    end

    # True if there is a block directly under the feet.
    def ground_below?(world)
      half = @width / 2.0
      eps = 0.0001
      by = (@position.y - 0.05).floor
      min_x = (@position.x - half).floor
      max_x = (@position.x + half - eps).floor
      min_z = (@position.z - half).floor
      max_z = (@position.z + half - eps).floor

      bx = min_x
      while bx <= max_x
        bz = min_z
        while bz <= max_z
          return true if world.has_block?(bx, by, bz)
          bz += 1
        end
        bx += 1
      end
      false
    end

    def aabb_min
      half = @width / 2.0
      Vec3.new(@position.x - half, @position.y, @position.z - half)
    end

    def aabb_max
      half = @width / 2.0
      Vec3.new(@position.x + half, @position.y + @height, @position.z + half)
    end

    private

    def move_axis(world, axis, amount, edge_guard: false)
      return if amount == 0

      old = axis == :x ? @position.x : @position.z

      if axis == :x
        @position.x += amount
      else
        @position.z += amount
      end

      if colliding?(world)
        half = @width / 2.0
        snapped =
          if amount > 0
            (old + amount + half).floor - half - SKIN
          else
            (old + amount - half).floor + 1 + half + SKIN
          end

        if axis == :x
          @position.x = snapped
          @velocity.x = 0
        else
          @position.z = snapped
          @velocity.z = 0
        end
      elsif edge_guard && !ground_below?(world)
        if axis == :x
          @position.x = old
          @velocity.x = 0
        else
          @position.z = old
          @velocity.z = 0
        end
      end
    end

    def move_y(world, amount)
      @position.y += amount
      @on_ground = false

      return unless colliding?(world)

      if amount < 0
        @position.y = @position.y.floor + 1
        @on_ground = true
      else
        @position.y = (@position.y + @height).floor - @height - SKIN
      end
      @velocity.y = 0
    end
  end
end
