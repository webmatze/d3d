module D3D
  class Mesh
    attr_accessor :uvs, :normals
    attr_reader :vertices, :faces

    def initialize(vertices: [], uvs: [], normals: [], faces: [])
      @vertices = vertices
      @uvs = uvs
      @normals = normals
      @faces = faces
    end

    def vertices=(value)
      @vertices = value
      invalidate_normals!
    end

    def faces=(value)
      @faces = value
      invalidate_normals!
    end

    # Unit outward normal [x, y, z] per face, from the winding (faces wind
    # clockwise seen from the front). Cached; call invalidate_normals! after
    # moving vertices in place (also resets face_cull_data and native_data).
    def face_normals
      @face_normals ||= @faces.map do |face|
        vi = face[:v]
        a = @vertices[vi[0]]
        b = @vertices[vi[1]]
        c = @vertices[vi[2]]
        e1x = b.x - a.x
        e1y = b.y - a.y
        e1z = b.z - a.z
        e2x = c.x - a.x
        e2y = c.y - a.y
        e2z = c.z - a.z
        nx = e2y * e1z - e2z * e1y
        ny = e2z * e1x - e2x * e1z
        nz = e2x * e1y - e2y * e1x
        len = Math.sqrt(nx * nx + ny * ny + nz * nz)
        len > 0 ? [nx / len, ny / len, nz / len] : [0.0, 0.0, 0.0]
      end
    end

    def invalidate_normals!
      @face_normals = nil
      @face_cull_data = nil
      @native_data = nil
    end

    # Handle of the optional C extension (D3D::Ext.pack_mesh) holding a copy
    # of the vertices, face_cull_data and the faces' uv indices; only used
    # when D3D::Native is enabled. Cached alongside face_cull_data.
    def native_data
      @native_data ||= begin
        uv_indices = [[], [], []]
        @faces.each do |f|
          uv = f[:uv]
          3.times { |k| uv_indices[k] << (uv && uv[k]) }
        end
        Ext.pack_mesh(@vertices.map(&:x), @vertices.map(&:y), @vertices.map(&:z),
                      *face_cull_data, *uv_indices)
      end
    end

    # Flat per-face arrays for the renderer's back face cull:
    # [i0s, i1s, i2s, v0x, v0y, v0z, nx, ny, nz] (vertex indices, first
    # corner position, face normal). Cached alongside face_normals.
    def face_cull_data
      @face_cull_data ||= begin
        fns = face_normals
        i0s = []
        i1s = []
        i2s = []
        v0x = []
        v0y = []
        v0z = []
        nxs = []
        nys = []
        nzs = []
        @faces.each_with_index do |face, fi|
          vi = face[:v]
          v0 = @vertices[vi[0]]
          fn = fns[fi]
          i0s << vi[0]
          i1s << vi[1]
          i2s << vi[2]
          v0x << v0.x
          v0y << v0.y
          v0z << v0.z
          nxs << fn[0]
          nys << fn[1]
          nzs << fn[2]
        end
        [i0s, i1s, i2s, v0x, v0y, v0z, nxs, nys, nzs]
      end
    end

    def dup
      Mesh.new(
        vertices: @vertices.map(&:dup),
        uvs: @uvs.map(&:dup),
        normals: @normals.map(&:dup),
        faces: @faces.map { |f| f.map(&:dup) }
      )
    end

    def self.cube
      vertices = [
        Vec3.new(-0.5, -0.5, -0.5),
        Vec3.new( 0.5, -0.5, -0.5),
        Vec3.new( 0.5,  0.5, -0.5),
        Vec3.new(-0.5,  0.5, -0.5),
        Vec3.new(-0.5, -0.5,  0.5),
        Vec3.new( 0.5, -0.5,  0.5),
        Vec3.new( 0.5,  0.5,  0.5),
        Vec3.new(-0.5,  0.5,  0.5)
      ]

      uvs = [
        [0, 0], [1, 0], [1, 1], [0, 1]
      ]

      normals = [
        Vec3.new( 0,  0, -1),
        Vec3.new( 0,  0,  1),
        Vec3.new( 0, -1,  0),
        Vec3.new( 0,  1,  0),
        Vec3.new(-1,  0,  0),
        Vec3.new( 1,  0,  0)
      ]

      faces = [
        # Front face (z = -0.5)
        { v: [0, 1, 2], uv: [0, 1, 2], n: [0, 0, 0] },
        { v: [0, 2, 3], uv: [0, 2, 3], n: [0, 0, 0] },
        # Back face (z = 0.5)
        { v: [5, 4, 7], uv: [0, 1, 2], n: [1, 1, 1] },
        { v: [5, 7, 6], uv: [0, 2, 3], n: [1, 1, 1] },
        # Bottom face (y = -0.5)
        { v: [4, 5, 1], uv: [0, 1, 2], n: [2, 2, 2] },
        { v: [4, 1, 0], uv: [0, 2, 3], n: [2, 2, 2] },
        # Top face (y = 0.5)
        { v: [3, 2, 6], uv: [0, 1, 2], n: [3, 3, 3] },
        { v: [3, 6, 7], uv: [0, 2, 3], n: [3, 3, 3] },
        # Left face (x = -0.5)
        { v: [4, 0, 3], uv: [0, 1, 2], n: [4, 4, 4] },
        { v: [4, 3, 7], uv: [0, 2, 3], n: [4, 4, 4] },
        # Right face (x = 0.5)
        { v: [1, 5, 6], uv: [0, 1, 2], n: [5, 5, 5] },
        { v: [1, 6, 2], uv: [0, 2, 3], n: [5, 5, 5] }
      ]

      Mesh.new(vertices: vertices, uvs: uvs, normals: normals, faces: faces)
    end

    def self.plane(width: 1, depth: 1, segments_x: 1, segments_z: 1)
      vertices = []
      uvs = []
      faces = []

      (segments_z + 1).times do |z|
        (segments_x + 1).times do |x|
          px = (x.to_f / segments_x - 0.5) * width
          pz = (z.to_f / segments_z - 0.5) * depth
          vertices << Vec3.new(px, 0, pz)
          uvs << [x.to_f / segments_x, z.to_f / segments_z]
        end
      end

      normals = [Vec3.new(0, 1, 0)]

      segments_z.times do |z|
        segments_x.times do |x|
          i = z * (segments_x + 1) + x
          faces << { v: [i, i + 1, i + segments_x + 2], uv: [i, i + 1, i + segments_x + 2], n: [0, 0, 0] }
          faces << { v: [i, i + segments_x + 2, i + segments_x + 1], uv: [i, i + segments_x + 2, i + segments_x + 1], n: [0, 0, 0] }
        end
      end

      Mesh.new(vertices: vertices, uvs: uvs, normals: normals, faces: faces)
    end

    def self.sphere(radius: 1, segments: 16, rings: 16)
      vertices = []
      uvs = []
      normals = []
      faces = []

      (rings + 1).times do |ring|
        phi = Math::PI * ring / rings
        (segments + 1).times do |seg|
          theta = 2 * Math::PI * seg / segments

          x = radius * Math.sin(phi) * Math.cos(theta)
          y = radius * Math.cos(phi)
          z = radius * Math.sin(phi) * Math.sin(theta)

          vertices << Vec3.new(x, y, z)
          normals << Vec3.new(x, y, z).normalize
          uvs << [seg.to_f / segments, ring.to_f / rings]
        end
      end

      rings.times do |ring|
        segments.times do |seg|
          i = ring * (segments + 1) + seg
          i_next = i + segments + 1

          if ring != 0
            faces << { v: [i, i_next, i + 1], uv: [i, i_next, i + 1], n: [i, i_next, i + 1] }
          end
          if ring != rings - 1
            faces << { v: [i + 1, i_next, i_next + 1], uv: [i + 1, i_next, i_next + 1], n: [i + 1, i_next, i_next + 1] }
          end
        end
      end

      Mesh.new(vertices: vertices, uvs: uvs, normals: normals, faces: faces)
    end
  end
end
