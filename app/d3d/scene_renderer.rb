module D3D
  # Software renderer for 6DOF scenes: textured CellGrid walls, flat shaded
  # FlatMesh objects and additive glow billboards, all emitted as DragonRuby
  # triangle/rect sprites and sorted back to front (painter's algorithm).
  #
  # Per frame:
  #   renderer.begin_frame(pose, lights: [...])
  #   renderer.draw_grid(grid)
  #   renderer.draw_mesh(...) / renderer.draw_glow(...)
  #   renderer.flush(args.outputs)
  #
  # Features: portal flood-fill visibility (via CellGrid#visible_cells),
  # near-plane clipping with UV interpolation, distance based subdivision to
  # hide affine texture warping, fog, a camera headlight, coloured point lights
  # and sub-pixel seam padding.
  class SceneRenderer
    # materials: { symbol => { path: 'sprites/x.png', size: 128 } } used by grid faces.
    # lights passed to begin_frame: [{ pos: [x,y,z], radius:, color: [r,g,b] (0..1), intensity: }]
    # fog: distance of the darkening (see fog_mode); view_distance: how far
    # cells and meshes are drawn at all (defaults to fog).
    attr_reader :width, :height, :focal, :near, :fog, :view_distance, :fog_mode, :tan_x, :tan_y,
                :triangle_count, :last_visible, :camera_position
    attr_accessor :materials
    # Strength (0..1) and reach (world units) of the camera headlight on walls.
    # Can be changed between frames, e.g. dimmed inside dark rooms.
    attr_reader :headlight, :headlight_range

    def headlight=(v)
      @headlight = v.to_f
    end

    def headlight_range=(v)
      @headlight_range = v.to_f
    end

    # fog_mode :linear darkens to black at fog (then nothing further away is
    # visible, so view_distance should not exceed it); :exponential darkens
    # like the linear fog near the camera but only fades out (about 20% of
    # the brightness left at fog, 4% at twice that), for a view_distance
    # beyond fog.
    def initialize(width: 1280, height: 720, focal: nil, fov: 92.0, near: 0.4, fog: 140.0,
                   view_distance: nil, fog_mode: :linear,
                   headlight_range: 60.0, headlight: 0.7, ambient_scale: 1.05,
                   materials: {}, white_path: 'sprites/d3d/white.png', white_size: 8,
                   glow_path: 'sprites/d3d/glow.png')
      @width = width
      @height = height
      @half_w = width / 2.0
      @half_h = height / 2.0
      @focal = (focal || @half_w / Math.tan(fov * Math::PI / 360.0)).to_f
      @tan_x = @half_w / @focal
      @tan_y = @half_h / @focal
      @near = near.to_f
      @fog = fog.to_f
      @view_distance = (view_distance || fog).to_f
      @fog_mode = fog_mode
      raise ArgumentError, "fog_mode must be :linear or :exponential" unless [:linear, :exponential].include?(fog_mode)
      @headlight_range = headlight_range.to_f
      @headlight = headlight.to_f
      @ambient_scale = ambient_scale
      @materials = materials
      @white_path = white_path
      @white_size = white_size
      @glow_path = glow_path
      @list = []
      @triangle_count = 0
      @last_visible = []
      @camera_position = [0.0, 0.0, 0.0]
    end

    # ---------------------------------------------------------------- camera

    # pose: anything with position/right/up/fwd arrays (e.g. D3D::Pose).
    # ambient_boost: [r, g, b] added to every wall (alarm flashes etc.).
    def begin_frame(pose, lights: [], ambient_boost: [0.0, 0.0, 0.0])
      @camera_position = pose.position
      @px, @py, @pz = pose.position
      @rx, @ry, @rz = pose.right
      @ux, @uy, @uz = pose.up
      @fx, @fy, @fz = pose.fwd
      @lights = lights
      @boost = ambient_boost
      @list = []
      @triangle_count = 0
      self
    end

    # World point -> camera space [x right, y up, z forward].
    def to_cam(x, y, z)
      dx = x - @px
      dy = y - @py
      dz = z - @pz
      [dx * @rx + dy * @ry + dz * @rz,
       dx * @ux + dy * @uy + dz * @uz,
       dx * @fx + dy * @fy + dz * @fz]
    end

    # Camera basis as [rx, ry, rz, ux, uy, uz, fx, fy, fz] (right, up, fwd),
    # for callers that inline to_cam on hot paths.
    def camera_basis
      [@rx, @ry, @rz, @ux, @uy, @uz, @fx, @fy, @fz]
    end

    # World direction -> camera space (rotation only).
    def dir_to_cam(x, y, z)
      [x * @rx + y * @ry + z * @rz,
       x * @ux + y * @uy + z * @uz,
       x * @fx + y * @fy + z * @fz]
    end

    # Projects a world point to [screen_x, screen_y, depth], or nil if behind the camera.
    def project(pos)
      c = to_cam(pos[0], pos[1], pos[2])
      return nil if c[2] < @near
      [@half_w + c[0] * @focal / c[2], @half_h + c[1] * @focal / c[2], c[2]]
    end

    # ---------------------------------------------------------------- grid

    def draw_grid(grid)
      faces = grid.faces
      @last_visible = grid.visible_cells(self)
      return draw_grid_native(faces) if Native.enabled?

      @last_visible.each do |n|
        list = faces[n]
        next unless list
        list.each { |f| draw_face(f) }
      end
      self
    end

    # Draws one CellFace (or anything with normal/c0/eu/ev/center/material/shade).
    def draw_face(f)
      nrm = f.normal
      c0 = f.c0
      # back face culling
      return if (@px - c0[0]) * nrm[0] + (@py - c0[1]) * nrm[1] + (@pz - c0[2]) * nrm[2] <= 0

      ctr = f.center
      d = Math.sqrt((ctr[0] - @px)**2 + (ctr[1] - @py)**2 + (ctr[2] - @pz)**2)
      return if d > @view_distance + 10

      mat = @materials[f.material]
      return unless mat
      tex = mat[:size] || 128

      # Subdivide close faces to hide affine texture warping and sorting errors.
      sub = d < 14 ? 4 : (d < 30 ? 3 : (d < 60 ? 2 : 1))
      eu = f.eu
      ev = f.ev
      # Face origin and edge vectors in camera space (scalars, no arrays).
      px = @px
      py = @py
      pz = @pz
      rx = @rx
      ry = @ry
      rz = @rz
      upx = @ux
      upy = @uy
      upz = @uz
      fx = @fx
      fy = @fy
      fz = @fz
      dx = c0[0] - px
      dy = c0[1] - py
      dz = c0[2] - pz
      ox = dx * rx + dy * ry + dz * rz
      oy = dx * upx + dy * upy + dz * upz
      oz = dx * fx + dy * fy + dz * fz
      e0 = eu[0]
      e1 = eu[1]
      e2 = eu[2]
      ux = e0 * rx + e1 * ry + e2 * rz
      uy = e0 * upx + e1 * upy + e2 * upz
      uz = e0 * fx + e1 * fy + e2 * fz
      e0 = ev[0]
      e1 = ev[1]
      e2 = ev[2]
      vx = e0 * rx + e1 * ry + e2 * rz
      vy = e0 * upx + e1 * upy + e2 * upz
      vz = e0 * fx + e1 * fy + e2 * fz

      # Quick frustum reject of the whole face (corners o, o+u, o+u+v, o+v).
      near = @near
      x1 = ox + ux
      y1 = oy + uy
      z1 = oz + uz
      x2 = ox + ux + vx
      y2 = oy + uy + vy
      z2 = oz + uz + vz
      x3 = ox + vx
      y3 = oy + vy
      z3 = oz + vz
      return if oz < near && z1 < near && z2 < near && z3 < near
      tx = @tan_x
      return if ox > oz * tx && x1 > z1 * tx && x2 > z2 * tx && x3 > z3 * tx
      return if ox < -oz * tx && x1 < -z1 * tx && x2 < -z2 * tx && x3 < -z3 * tx
      ty = @tan_y
      return if oy > oz * ty && y1 > z1 * ty && y2 > z2 * ty && y3 > z3 * ty
      return if oy < -oz * ty && y1 < -z1 * ty && y2 < -z2 * ty && y3 < -z3 * ty

      shade = f.shade
      path = mat[:path]
      step = 1.0 / sub
      tstep = tex.to_f / sub

      # Shared (sub+1)^2 grid of camera space points, projected once.
      n1 = sub + 1
      gx = (@grid_x ||= [])
      gy = (@grid_y ||= [])
      gz = (@grid_z ||= [])
      gsx = (@grid_sx ||= [])
      gsy = (@grid_sy ||= [])
      focal = @focal
      hw = @half_w
      hh = @half_h
      k = 0
      i = 0
      while i < n1
        si = i * step
        bx = ox + ux * si
        by = oy + uy * si
        bz = oz + uz * si
        j = 0
        while j < n1
          tj = j * step
          cx = bx + vx * tj
          cy = by + vy * tj
          cz = bz + vz * tj
          gx[k] = cx
          gy[k] = cy
          gz[k] = cz
          if cz >= near
            iz = focal / cz
            gsx[k] = hw + cx * iz
            gsy[k] = hh + cy * iz
          end
          k += 1
          j += 1
        end
        i += 1
      end

      width = @width
      height = @height
      list = @list
      a = 0
      while a < sub
        sa = a * step
        ta0 = a * tstep
        ta1 = (a + 1) * tstep
        b = 0
        while b < sub
          tb = b * step
          tb0 = b * tstep
          tb1 = (b + 1) * tstep
          k0 = a * n1 + b
          k1 = k0 + n1
          k2 = k1 + 1
          k3 = k0 + 1

          # sub face centre in world space, for lighting and sorting
          sm = sa + step * 0.5
          tm = tb + step * 0.5
          wx = c0[0] + eu[0] * sm + ev[0] * tm
          wy = c0[1] + eu[1] * sm + ev[1] * tm
          wz = c0[2] + eu[2] * sm + ev[2] * tm
          dd = (wx - px)**2 + (wy - py)**2 + (wz - pz)**2

          if gz[k0] >= near && gz[k1] >= near && gz[k2] >= near && gz[k3] >= near
            sx0 = gsx[k0]
            sy0 = gsy[k0]
            sx1 = gsx[k1]
            sy1 = gsy[k1]
            sx2 = gsx[k2]
            sy2 = gsy[k2]
            sx3 = gsx[k3]
            sy3 = gsy[k3]
            unless (sx0 < 0 && sx1 < 0 && sx2 < 0 && sx3 < 0) ||
                   (sx0 > width && sx1 > width && sx2 > width && sx3 > width) ||
                   (sy0 < 0 && sy1 < 0 && sy2 < 0 && sy3 < 0) ||
                   (sy0 > height && sy1 > height && sy2 > height && sy3 > height)
              r, g, bl = light_at(wx, wy, wz, Math.sqrt(dd), shade)
              # pad! unrolled for the 4 vertex case
              mx = 0.0 + sx0
              mx += sx1
              mx += sx2
              mx += sx3
              mx /= 4
              my = 0.0 + sy0
              my += sy1
              my += sy2
              my += sy3
              my /= 4
              ddx = sx0 - mx
              ddy = sy0 - my
              l = Math.sqrt(ddx * ddx + ddy * ddy)
              unless l < 1e-3
                sx0 += ddx / l * 0.7
                sy0 += ddy / l * 0.7
              end
              ddx = sx1 - mx
              ddy = sy1 - my
              l = Math.sqrt(ddx * ddx + ddy * ddy)
              unless l < 1e-3
                sx1 += ddx / l * 0.7
                sy1 += ddy / l * 0.7
              end
              ddx = sx2 - mx
              ddy = sy2 - my
              l = Math.sqrt(ddx * ddx + ddy * ddy)
              unless l < 1e-3
                sx2 += ddx / l * 0.7
                sy2 += ddy / l * 0.7
              end
              ddx = sx3 - mx
              ddy = sy3 - my
              l = Math.sqrt(ddx * ddx + ddy * ddy)
              unless l < 1e-3
                sx3 += ddx / l * 0.7
                sy3 += ddy / l * 0.7
              end
              @triangle_count += 2
              list << [dd, {
                x: sx0, y: sy0, x2: sx1, y2: sy1, x3: sx2, y3: sy2,
                source_x: ta0, source_y: tb0,
                source_x2: ta1, source_y2: tb0,
                source_x3: ta1, source_y3: tb1,
                path: path, r: r, g: g, b: bl
              }]
              list << [dd, {
                x: sx0, y: sy0, x2: sx2, y2: sy2, x3: sx3, y3: sy3,
                source_x: ta0, source_y: tb0,
                source_x2: ta1, source_y2: tb1,
                source_x3: ta0, source_y3: tb1,
                path: path, r: r, g: g, b: bl
              }]
            end
          else
            # Crosses the near plane: generic clipping path.
            r, g, bl = light_at(wx, wy, wz, Math.sqrt(dd), shade)
            emit_textured([[gx[k0], gy[k0], gz[k0], ta0, tb0],
                           [gx[k1], gy[k1], gz[k1], ta1, tb0],
                           [gx[k2], gy[k2], gz[k2], ta1, tb1],
                           [gx[k3], gy[k3], gz[k3], ta0, tb1]], path, r, g, bl, dd)
          end
          b += 1
        end
        a += 1
      end
    end

    # draw_face for every face of the visible cells in C (the optional
    # extension, D3D::Ext.draw_cell_faces mirrors draw_face and light_at).
    def draw_grid_native(faces)
      lists = []
      @last_visible.each do |n|
        list = faces[n]
        lists << native_cell_faces(list) if list
      end
      lights = []
      @lights.each do |lt|
        pos = lt[:pos]
        c = lt[:color]
        lights.push(pos[0], pos[1], pos[2], lt[:radius], lt[:intensity], c[0], c[1], c[2])
      end
      # emit_textured (called back from C) counts its own triangles, so add
      # after the call: `@triangle_count += Ext...` would read the old value
      # first and lose them.
      added = Ext.draw_cell_faces(self, @list, lists, [
        @px, @py, @pz, @rx, @ry, @rz, @ux, @uy, @uz, @fx, @fy, @fz,
        @near, @fog, @view_distance, @fog_mode == :exponential ? 1 : 0,
        @tan_x, @tan_y, @focal, @half_w, @half_h, @width, @height,
        @headlight_range, @headlight, @ambient_scale, @boost[0], @boost[1], @boost[2]
      ], lights, @materials)
      @triangle_count += added
      self
    end

    # A cell's face list packed for D3D::Ext.draw_cell_faces: per face
    # normal, c0, eu, ev, center, shade, material. Cached by list identity;
    # CellGrid rebuilds a list object whenever its faces change.
    def native_cell_faces(list)
      cache = (@native_faces ||= {})
      entry = cache[list.object_id]
      return entry[1] if entry && entry[0].equal?(list)

      cache.clear if cache.size > 50_000
      packed = []
      list.each do |f|
        packed.concat(f.normal)
        packed.concat(f.c0)
        packed.concat(f.eu)
        packed.concat(f.ev)
        packed.concat(f.center)
        packed.concat(f.shade)
        packed << f.material
      end
      cache[list.object_id] = [list, packed]
      packed
    end

    # Returns 0..255 rgb for a surface point at distance dist from the camera.
    def light_at(x, y, z, dist, tint)
      if @fog_mode == :exponential
        fog = Math.exp(-1.25 * dist / @fog)
      else
        fog = 1.0 - dist / @fog
        return [0, 0, 0] if fog <= 0
      end
      fog = fog * (0.6 + 0.4 * fog)
      head = dist < @headlight_range ? (1.0 - dist / @headlight_range) * @headlight : 0.0
      r = (tint[0] * @ambient_scale + head) * fog + @boost[0]
      g = (tint[1] * @ambient_scale + head) * fog + @boost[1]
      b = (tint[2] * @ambient_scale + head) * fog + @boost[2]
      @lights.each do |lt|
        lx, ly, lz = lt[:pos]
        rad = lt[:radius]
        d2 = (lx - x)**2 + (ly - y)**2 + (lz - z)**2
        next if d2 >= rad * rad
        k = (1.0 - Math.sqrt(d2) / rad) * lt[:intensity]
        c = lt[:color]
        r += c[0] * k
        g += c[1] * k
        b += c[2] * k
      end
      [D3D.clamp(r * 255, 0, 255), D3D.clamp(g * 255, 0, 255), D3D.clamp(b * 255, 0, 255)]
    end

    # poly: camera space points [x, y, z, u, v]
    def emit_textured(poly, path, r, g, b, key)
      poly = clip_near(poly) if poly.any? { |p| p[2] < @near }
      return if poly.size < 3
      pts = poly.map do |p|
        iz = @focal / p[2]
        [@half_w + p[0] * iz, @half_h + p[1] * iz, p[3], p[4]]
      end
      return if offscreen?(pts)
      pad!(pts)
      a = pts[0]
      (1...pts.size - 1).each do |n|
        b1 = pts[n]
        c1 = pts[n + 1]
        @triangle_count += 1
        @list << [key, {
          x: a[0], y: a[1], x2: b1[0], y2: b1[1], x3: c1[0], y3: c1[1],
          source_x: a[2], source_y: a[3],
          source_x2: b1[2], source_y2: b1[3],
          source_x3: c1[2], source_y3: c1[3],
          path: path, r: r, g: g, b: b
        }]
      end
    end

    # Pushes projected vertices ~0.7px away from the polygon centre so that
    # neighbouring triangles overlap instead of leaving hairline cracks.
    def pad!(pts)
      cx = 0.0
      cy = 0.0
      pts.each do |p|
        cx += p[0]
        cy += p[1]
      end
      cx /= pts.size
      cy /= pts.size
      pts.each do |p|
        dx = p[0] - cx
        dy = p[1] - cy
        l = Math.sqrt(dx * dx + dy * dy)
        next if l < 1e-3
        p[0] += dx / l * 0.7
        p[1] += dy / l * 0.7
      end
    end

    # Sutherland-Hodgman clip of a camera space polygon against z = near,
    # interpolating the u/v texture coordinates of new vertices.
    def clip_near(poly)
      out = []
      n = poly.size
      n.times do |i|
        a = poly[i]
        b = poly[(i + 1) % n]
        ain = a[2] >= @near
        bin = b[2] >= @near
        out << a if ain
        next if ain == bin
        t = (@near - a[2]) / (b[2] - a[2])
        out << [a[0] + (b[0] - a[0]) * t,
                a[1] + (b[1] - a[1]) * t,
                @near,
                a[3] + (b[3] - a[3]) * t,
                a[4] + (b[4] - a[4]) * t]
      end
      out
    end

    def offscreen?(pts)
      pts.all? { |p| p[0] < 0 } || pts.all? { |p| p[0] > @width } ||
        pts.all? { |p| p[1] < 0 } || pts.all? { |p| p[1] > @height }
    end

    # ---------------------------------------------------------------- meshes

    # Draws a FlatMesh at pos with the given orientation basis. light is the
    # [r,g,b] ambient (0..~1.2) around the object. flash (0..1) blends to white.
    # ambient is the minimum brightness of non-emissive triangles (0.6 keeps
    # objects readable in dim rooms; near 0 lets them vanish in the dark).
    def draw_mesh(mesh, pos, right, up, fwd, scale = 1.0, light = [1.0, 1.0, 1.0], flash = 0.0, ambient: 0.6)
      o = to_cam(pos[0], pos[1], pos[2])
      return if o[2] < -mesh.radius * scale
      rc = dir_to_cam(right[0] * scale, right[1] * scale, right[2] * scale)
      uc = dir_to_cam(up[0] * scale, up[1] * scale, up[2] * scale)
      fc = dir_to_cam(fwd[0] * scale, fwd[1] * scale, fwd[2] * scale)
      cam_verts = mesh.verts.map do |p|
        [o[0] + rc[0] * p[0] + uc[0] * p[1] + fc[0] * p[2],
         o[1] + rc[1] * p[0] + uc[1] * p[1] + fc[1] * p[2],
         o[2] + rc[2] * p[0] + uc[2] * p[1] + fc[2] * p[2]]
      end
      dist = Math.sqrt(o[0] * o[0] + o[1] * o[1] + o[2] * o[2])
      if @fog_mode == :exponential
        return if dist > @view_distance
        fog = Math.exp(-1.25 * dist / @fog)
      else
        fog = 1.0 - dist / @fog
        return if fog <= 0
      end
      fog = fog * 0.7 + 0.3
      inv_s = 1.0 / scale
      ws = @white_size
      mesh.tris.each do |t|
        a = cam_verts[t.a]
        b = cam_verts[t.b]
        c = cam_verts[t.c]
        next if a[2] < @near || b[2] < @near || c[2] < @near
        n = t.normal
        ncx = (rc[0] * n[0] + uc[0] * n[1] + fc[0] * n[2]) * inv_s
        ncy = (rc[1] * n[0] + uc[1] * n[1] + fc[1] * n[2]) * inv_s
        ncz = (rc[2] * n[0] + uc[2] * n[1] + fc[2] * n[2]) * inv_s
        facing = -(a[0] * ncx + a[1] * ncy + a[2] * ncz)
        next if facing <= 0 && !t.double_sided
        mx = (a[0] + b[0] + c[0]) / 3.0
        my = (a[1] + b[1] + c[1]) / 3.0
        mz = (a[2] + b[2] + c[2]) / 3.0
        ml = Math.sqrt(mx * mx + my * my + mz * mz) + 1e-6
        lambert = facing.abs / ml
        s = (0.35 + 0.75 * lambert) * fog
        col = t.color
        emissive = t.emissive
        r = col[0] * (emissive ? 1.0 : s * (light[0] * 0.5 + ambient))
        g = col[1] * (emissive ? 1.0 : s * (light[1] * 0.5 + ambient))
        bb = col[2] * (emissive ? 1.0 : s * (light[2] * 0.5 + ambient))
        if flash > 0
          r += (255 - r) * flash
          g += (255 - g) * flash
          bb += (255 - bb) * flash
        end
        ia = @focal / a[2]
        ib = @focal / b[2]
        ic = @focal / c[2]
        @triangle_count += 1
        @list << [mx * mx + my * my + mz * mz, {
          x: @half_w + a[0] * ia, y: @half_h + a[1] * ia,
          x2: @half_w + b[0] * ib, y2: @half_h + b[1] * ib,
          x3: @half_w + c[0] * ic, y3: @half_h + c[1] * ic,
          source_x: 0, source_y: 0, source_x2: ws, source_y2: 0, source_x3: 0, source_y3: ws,
          path: @white_path,
          r: D3D.clamp(r, 0, 255), g: D3D.clamp(g, 0, 255), b: D3D.clamp(bb, 0, 255)
        }]
      end
      self
    end

    # ---------------------------------------------------------------- sprites

    # Camera facing additive sprite of world size `size` centred on pos.
    def draw_glow(pos, size, r, g, b, a = 255, path: @glow_path)
      c = to_cam(pos[0], pos[1], pos[2])
      return if c[2] < @near
      s = size * @focal / c[2]
      return if s < 0.5
      sx = @half_w + c[0] * @focal / c[2]
      sy = @half_h + c[1] * @focal / c[2]
      return if sx < -s || sx > @width + s || sy < -s || sy > @height + s
      d2 = c[0] * c[0] + c[1] * c[1] + c[2] * c[2]
      @list << [d2 - size * size, {
        x: sx - s * 0.5, y: sy - s * 0.5, w: s, h: s, path: path,
        r: r, g: g, b: b, a: a, blendmode_enum: 2
      }]
      self
    end

    # ---------------------------------------------------------------- output

    # Everything queued this frame, sorted back to front.
    def sorted_primitives
      DepthSort.pairs(@list)
    end

    def flush(outputs)
      outputs.sprites << sorted_primitives
    end
  end
end
