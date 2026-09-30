module D3D
  class FlatTri
    attr_reader :a, :b, :c, :color, :normal, :double_sided, :emissive

    def initialize(a, b, c, color, normal, double_sided, emissive)
      @a = a
      @b = b
      @c = c
      @color = color
      @normal = normal
      @double_sided = double_sided
      @emissive = emissive
    end
  end

  # Low poly, flat shaded mesh with a colour per triangle, drawn by
  # SceneRenderer#draw_mesh. Local space: +x right, +y up, +z forward.
  class FlatMesh
    attr_reader :verts, :tris, :radius

    def initialize
      @verts = []
      @tris = []
      @radius = 0.0
    end

    def vert(x, y, z)
      @verts << [x.to_f, y.to_f, z.to_f]
      l = Math.sqrt(x * x + y * y + z * z)
      @radius = l if l > @radius
      @verts.size - 1
    end

    # Adds a triangle whose winding is fixed so that its normal points away from
    # `inside` (the centre of the convex part it belongs to).
    def tri(a, b, c, color, inside: [0, 0, 0], double_sided: false, emissive: false)
      pa = @verts[a]
      n = V.norm(V.cross(V.sub(@verts[b], pa), V.sub(@verts[c], pa)))
      centroid = V.scale(V.add(V.add(pa, @verts[b]), @verts[c]), 1.0 / 3)
      if V.dot(n, V.sub(centroid, inside)) < 0
        b, c = c, b
        n = V.scale(n, -1)
      end
      @tris << FlatTri.new(a, b, c, color, n, double_sided, emissive)
    end

    def quad(a, b, c, d, color, **opts)
      tri(a, b, c, color, **opts)
      tri(a, c, d, color, **opts)
    end

    # Axis aligned box centred on (cx, cy, cz) with half extents sx, sy, sz.
    # `color` is used for the front (+z) face, `side_color` for the others.
    def box(cx, cy, cz, sx, sy, sz, color, side_color = nil, **opts)
      side_color ||= color
      v = []
      [-1, 1].each do |z|
        [-1, 1].each do |y|
          [-1, 1].each do |x|
            v << vert(cx + x * sx, cy + y * sy, cz + z * sz)
          end
        end
      end
      inside = [cx, cy, cz]
      quad(v[0], v[1], v[3], v[2], side_color, inside: inside, **opts) # back
      quad(v[4], v[5], v[7], v[6], color, inside: inside, **opts)      # front
      quad(v[0], v[1], v[5], v[4], side_color, inside: inside, **opts) # bottom
      quad(v[2], v[3], v[7], v[6], side_color, inside: inside, **opts) # top
      quad(v[0], v[2], v[6], v[4], side_color, inside: inside, **opts) # left
      quad(v[1], v[3], v[7], v[5], side_color, inside: inside, **opts) # right
      self
    end

    # Double cone: `sides` ring vertices of radius r, tips at +front and -back
    # along `axis` (:z or :y). Back-facing cone triangles are drawn 30% darker.
    def bipyramid(sides, r, front, back, colors, center: [0, 0, 0], axis: :z, **opts)
      ring = sides.times.map do |n|
        a = Math::PI * 2 * n / sides
        x = Math.cos(a) * r
        y = Math.sin(a) * r
        if axis == :z
          vert(center[0] + x, center[1] + y, center[2])
        else
          vert(center[0] + x, center[1], center[2] + y)
        end
      end
      if axis == :z
        tip_f = vert(center[0], center[1], center[2] + front)
        tip_b = vert(center[0], center[1], center[2] - back)
      else
        tip_f = vert(center[0], center[1] + front, center[2])
        tip_b = vert(center[0], center[1] - back, center[2])
      end
      sides.times do |n|
        m = (n + 1) % sides
        col = colors[n % colors.size]
        tri(ring[n], ring[m], tip_f, col, inside: center, **opts)
        tri(ring[n], ring[m], tip_b, col.map { |c| c * 0.7 }, inside: center, **opts)
      end
      self
    end
  end
end
