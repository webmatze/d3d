module D3D
  class VoxelWorld
    attr_reader :blocks, :mesh_data

    # Face definitions: [vertex offsets for 2 triangles, normal direction check offset, UV coordinates]
    # Each face has 6 vertices (2 triangles) defined as offsets from block position
    # UV coordinates are normalized 0-1 range
    FACES = {
      # Top face (+Y) - check if block above is empty
      top: {
        check: [0, 1, 0],
        vertices: [
          # Triangle 1
          [0, 1, 0], [1, 1, 0], [1, 1, 1],
          # Triangle 2
          [0, 1, 0], [1, 1, 1], [0, 1, 1]
        ],
        uvs: [
          # Triangle 1: bottom-left, bottom-right, top-right
          [0, 0], [1, 0], [1, 1],
          # Triangle 2: bottom-left, top-right, top-left
          [0, 0], [1, 1], [0, 1]
        ]
      },
      # Bottom face (-Y) - check if block below is empty
      bottom: {
        check: [0, -1, 0],
        vertices: [
          [0, 0, 1], [1, 0, 1], [1, 0, 0],
          [0, 0, 1], [1, 0, 0], [0, 0, 0]
        ],
        uvs: [
          [0, 1], [1, 1], [1, 0],
          [0, 1], [1, 0], [0, 0]
        ]
      },
      # Front face (+Z) - check if block in front is empty
      front: {
        check: [0, 0, 1],
        vertices: [
          [0, 0, 1], [0, 1, 1], [1, 1, 1],
          [0, 0, 1], [1, 1, 1], [1, 0, 1]
        ],
        uvs: [
          [0, 0], [0, 1], [1, 1],
          [0, 0], [1, 1], [1, 0]
        ]
      },
      # Back face (-Z) - check if block behind is empty
      back: {
        check: [0, 0, -1],
        vertices: [
          [1, 0, 0], [1, 1, 0], [0, 1, 0],
          [1, 0, 0], [0, 1, 0], [0, 0, 0]
        ],
        uvs: [
          [0, 0], [0, 1], [1, 1],
          [0, 0], [1, 1], [1, 0]
        ]
      },
      # Right face (+X) - check if block to right is empty
      right: {
        check: [1, 0, 0],
        vertices: [
          [1, 0, 1], [1, 1, 1], [1, 1, 0],
          [1, 0, 1], [1, 1, 0], [1, 0, 0]
        ],
        uvs: [
          [0, 0], [0, 1], [1, 1],
          [0, 0], [1, 1], [1, 0]
        ]
      },
      # Left face (-X) - check if block to left is empty
      left: {
        check: [-1, 0, 0],
        vertices: [
          [0, 0, 0], [0, 1, 0], [0, 1, 1],
          [0, 0, 0], [0, 1, 1], [0, 0, 1]
        ],
        uvs: [
          [0, 0], [0, 1], [1, 1],
          [0, 0], [1, 1], [1, 0]
        ]
      }
    }.freeze

    # Block keys pack x/y/z into one Integer (20 bits per axis, 60 bits
    # total) so lookups allocate no Strings and stay within mruby's 64-bit
    # fixnums. Supported coordinate range per axis: -524288..524287.
    KEY_OFFSET = 1 << 19
    KEY_SPAN = 1 << 20

    # FACES as a flat array of [check, vertices, uvs, neighbor key delta],
    # so build_mesh can find neighbors with one Integer add per face.
    FACE_LIST = FACES.values.map do |face|
      check = face[:check]
      delta = (check[0] * KEY_SPAN + check[1]) * KEY_SPAN + check[2]
      [check, face[:vertices], face[:uvs], delta].freeze
    end.freeze

    def initialize
      @blocks = {}  # Spatial hash: packed Integer key (see block_key) => color_hash
      @mesh_data = nil
      @dirty = true
    end

    def add_block(x, y, z, color, texture: nil)
      key = block_key(x.to_i, y.to_i, z.to_i)
      @blocks[key] = {
        x: x.to_i,
        y: y.to_i,
        z: z.to_i,
        r: color[:r],
        g: color[:g],
        b: color[:b],
        a: color[:a] || 255,
        texture: texture
      }
      @dirty = true
    end

    def remove_block(x, y, z)
      @blocks.delete(block_key(x.to_i, y.to_i, z.to_i))
      @dirty = true
    end

    def has_block?(x, y, z)
      @blocks.key?(block_key(x.to_i, y.to_i, z.to_i))
    end

    def get_block(x, y, z)
      @blocks[block_key(x.to_i, y.to_i, z.to_i)]
    end

    def block_count
      @blocks.size
    end

    def build_mesh
      return @mesh_data unless @dirty

      # Build arrays of vertices and faces for exposed faces only
      vertices = []
      faces = []

      blocks = @blocks
      blocks.each do |key, block|
        bx, by, bz = block[:x], block[:y], block[:z]
        r, g, b, a = block[:r], block[:g], block[:b], block[:a]
        texture = block[:texture]

        FACE_LIST.each do |check, verts, uvs, delta|
          # Only add face if no neighbor block exists
          next if blocks.key?(key + delta)

          base_idx = vertices.size

          # Add 6 vertices for this face (2 triangles)
          verts.each do |v_offset|
            vertices << [
              bx + v_offset[0],
              by + v_offset[1],
              bz + v_offset[2]
            ]
          end

          # Add 2 triangle faces with color, texture, and UVs
          faces << {
            v: [base_idx, base_idx + 1, base_idx + 2],
            uv: [uvs[0], uvs[1], uvs[2]],
            n: check,
            texture: texture,
            r: r, g: g, b: b, a: a
          }
          faces << {
            v: [base_idx + 3, base_idx + 4, base_idx + 5],
            uv: [uvs[3], uvs[4], uvs[5]],
            n: check,
            texture: texture,
            r: r, g: g, b: b, a: a
          }
        end
      end

      @mesh_data = { vertices: vertices, faces: faces }
      @dirty = false
      @mesh_data
    end

    def rebuild!
      @dirty = true
      build_mesh
    end

    # The four corners of a block face, given a raycast hit
    # ({ x:, y:, z:, normal: [nx, ny, nz] }). Corners are returned in edge-loop
    # order as [x, y, z] arrays, pushed `lift` outward along the normal to
    # avoid z-fighting. Returns nil for a zero normal.
    def self.face_corners(hit, lift: 0.004)
      nx, ny, nz = hit[:normal]
      return nil if nx == 0 && ny == 0 && nz == 0

      face_offset = ->(n, base) { n > 0 ? base + 1 + lift : base - lift }

      if nx != 0
        fx = face_offset.call(nx, hit[:x])
        [[fx, hit[:y], hit[:z]], [fx, hit[:y] + 1, hit[:z]],
         [fx, hit[:y] + 1, hit[:z] + 1], [fx, hit[:y], hit[:z] + 1]]
      elsif ny != 0
        fy = face_offset.call(ny, hit[:y])
        [[hit[:x], fy, hit[:z]], [hit[:x] + 1, fy, hit[:z]],
         [hit[:x] + 1, fy, hit[:z] + 1], [hit[:x], fy, hit[:z] + 1]]
      else
        fz = face_offset.call(nz, hit[:z])
        [[hit[:x], hit[:y], fz], [hit[:x] + 1, hit[:y], fz],
         [hit[:x] + 1, hit[:y] + 1, fz], [hit[:x], hit[:y] + 1, fz]]
      end
    end

    # True if the AABB (min/max as Vec3) overlaps any block. Boxes that only
    # touch a block face (e.g. standing exactly on top) do not intersect.
    def aabb_intersects?(min, max)
      aabb_intersects_xyz?(min.x, min.y, min.z, max.x, max.y, max.z)
    end

    # Scalar variant of aabb_intersects? (no Vec3 needed). Walks the covered
    # cells with while loops and builds the packed key from per-axis parts.
    def aabb_intersects_xyz?(min_x, min_y, min_z, max_x, max_y, max_z)
      eps = 1e-9
      x0 = min_x.floor
      x1 = (max_x - eps).floor
      y0 = min_y.floor
      y1 = (max_y - eps).floor
      z0 = min_z.floor
      z1 = (max_z - eps).floor
      return false if x0 > x1 || y0 > y1 || z0 > z1

      blocks = @blocks
      span = KEY_SPAN
      span2 = KEY_SPAN * KEY_SPAN
      offset = KEY_OFFSET
      ypart0 = (y0 + offset) * span
      zpart0 = z0 + offset

      bx = x0
      while bx <= x1
        xpart = (bx + offset) * span2
        ypart = ypart0
        by = y0
        while by <= y1
          xy = xpart + ypart
          key = xy + zpart0
          bz = z0
          while bz <= z1
            return true if blocks.key?(key)
            key += 1
            bz += 1
          end
          ypart += span
          by += 1
        end
        bx += 1
      end
      false
    end

    # Voxel raycast (Amanatides & Woo DDA). Returns the first solid block hit
    # as { x:, y:, z:, normal: [nx, ny, nz], distance: } or nil.
    def raycast(origin, dir, max_distance)
      ox = origin.x
      oy = origin.y
      oz = origin.z
      dx = dir.x
      dy = dir.y
      dz = dir.z
      x = ox.floor
      y = oy.floor
      z = oz.floor

      step_x = dx > 0 ? 1 : -1
      step_y = dy > 0 ? 1 : -1
      step_z = dz > 0 ? 1 : -1

      inf = Float::INFINITY
      t_delta_x = dx == 0 ? inf : (1.0 / dx).abs
      t_delta_y = dy == 0 ? inf : (1.0 / dy).abs
      t_delta_z = dz == 0 ? inf : (1.0 / dz).abs

      t_max_x = dx == 0 ? inf : ((dx > 0 ? x + 1 - ox : ox - x) * t_delta_x)
      t_max_y = dy == 0 ? inf : ((dy > 0 ? y + 1 - oy : oy - y) * t_delta_y)
      t_max_z = dz == 0 ? inf : ((dz > 0 ? z + 1 - oz : oz - z) * t_delta_z)

      blocks = @blocks
      span = KEY_SPAN
      key = block_key(x, y, z)
      key_step_x = step_x * span * span
      key_step_y = step_y * span
      key_step_z = step_z

      # Last stepped axis: 0 = none (start cell), 1 = x, 2 = y, 3 = z.
      axis = 0
      t = 0.0

      while t <= max_distance
        if blocks.key?(key)
          normal =
            if axis == 1
              [-step_x, 0, 0]
            elsif axis == 2
              [0, -step_y, 0]
            elsif axis == 3
              [0, 0, -step_z]
            else
              [0, 0, 0]
            end
          return { x: x, y: y, z: z, normal: normal, distance: t }
        end

        if t_max_x < t_max_y && t_max_x < t_max_z
          x += step_x
          key += key_step_x
          t = t_max_x
          t_max_x += t_delta_x
          axis = 1
        elsif t_max_y < t_max_z
          y += step_y
          key += key_step_y
          t = t_max_y
          t_max_y += t_delta_y
          axis = 2
        else
          z += step_z
          key += key_step_z
          t = t_max_z
          t_max_z += t_delta_z
          axis = 3
        end
      end

      nil
    end

    private

    def block_key(x, y, z)
      ((x + KEY_OFFSET) * KEY_SPAN + (y + KEY_OFFSET)) * KEY_SPAN + (z + KEY_OFFSET)
    end
  end
end
