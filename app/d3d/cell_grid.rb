module D3D
  # One wall quad of a CellGrid: corner c0 plus edge vectors eu (c0 -> c1) and
  # ev (c0 -> c3). normal points into the open cell. shade is the cell tint
  # multiplied by the per-direction shade.
  class CellFace
    attr_reader :normal, :c0, :eu, :ev, :center, :material, :shade, :cell

    def initialize(normal, c0, eu, ev, material, shade, cell)
      @normal = normal
      @c0 = c0
      @eu = eu
      @ev = ev
      @center = [c0[0] + (eu[0] + ev[0]) * 0.5,
                 c0[1] + (eu[1] + ev[1]) * 0.5,
                 c0[2] + (eu[2] + ev[2]) * 0.5]
      @material = material
      @shade = shade
      @cell = cell
    end
  end

  # A world made of cube cells that are either open (flyable) or solid rock.
  # Wall faces are generated wherever an open cell touches a solid one.
  #
  # Cells are addressed by integer (i, j, k) = (x, y, z) or by a flat index.
  # The outermost layer of cells is always solid.
  #
  # "Blockers" are solid cells that can later be opened (doors, hatches). The
  # faces of their neighbours use the blocker's material.
  class CellGrid
    # [di, dj, dk] of the six neighbours: -x, +x, -y, +y, -z, +z
    DIRS = [[-1, 0, 0], [1, 0, 0], [0, -1, 0], [0, 1, 0], [0, 0, -1], [0, 0, 1]]
    # Floors lit brighter than walls, ceilings darker: cheap depth cues.
    DEFAULT_DIR_SHADE = [0.82, 0.82, 1.0, 0.62, 0.74, 0.74]
    # Corners (as grid offsets) of the face between a cell and its neighbour in DIRS[n].
    PORTALS = [
      [[0, 0, 0], [0, 1, 0], [0, 0, 1], [0, 1, 1]],
      [[1, 0, 0], [1, 1, 0], [1, 0, 1], [1, 1, 1]],
      [[0, 0, 0], [1, 0, 0], [0, 0, 1], [1, 0, 1]],
      [[0, 1, 0], [1, 1, 0], [0, 1, 1], [1, 1, 1]],
      [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0]],
      [[0, 0, 1], [1, 0, 1], [0, 1, 1], [1, 1, 1]]
    ]
    # PORTALS flattened to [ox, oy, oz] triples at (dir * 4 + corner) * 3.
    PORTAL_OFFSETS = PORTALS.flatten

    # version is bumped on every runtime change of open/solid cells (unseal,
    # solidify), so caches such as GridMap know when to rebuild.
    attr_reader :nx, :ny, :nz, :cell_size, :cells, :faces, :blockers, :version

    def initialize(nx, ny, nz, cell_size: 10.0, material: :default, tint: [0.7, 0.7, 0.7],
                   dir_shade: DEFAULT_DIR_SHADE)
      @nx = nx
      @ny = ny
      @nz = nz
      @cell_size = cell_size.to_f
      @dir_shade = dir_shade
      size = nx * ny * nz
      @cells = Array.new(size, false)
      @material = Array.new(size, material)
      @tint = Array.new(size, tint)
      @blockers = {}
      @blocker_materials = {}
      @faces = Array.new(size)
      @visited = Array.new(size, 0)
      @stamp = 0
      @version = 0
      gp = (nx + 1) * (ny + 1) * (nz + 1)
      @gp_stamp = Array.new(gp, 0)
      @gp_x = Array.new(gp)
      @gp_y = Array.new(gp)
      @gp_z = Array.new(gp)
      # Grid point index offset of each PORTALS corner, flattened (dir * 4 + corner).
      @portal_goff = []
      PORTALS.each { |corners| corners.each { |o| @portal_goff << o[0] + (nx + 1) * (o[1] + (ny + 1) * o[2]) } }
    end

    # ----------------------------------------------------------- addressing

    def idx(i, j, k)
      i + @nx * (j + @ny * k)
    end

    # Integer division written so it behaves the same on CRuby and DragonRuby
    # (where Integer#/ returns a Float).
    def coords(n)
      i = n % @nx
      j = (n / @nx).to_i % @ny
      k = (n / (@nx * @ny)).to_i
      [i, j, k]
    end

    def in_bounds?(i, j, k)
      i > 0 && j > 0 && k > 0 && i < @nx - 1 && j < @ny - 1 && k < @nz - 1
    end

    def cell_of(p)
      cs = @cell_size
      [(p[0] / cs).floor, (p[1] / cs).floor, (p[2] / cs).floor]
    end

    def cell_center(i, j, k)
      cs = @cell_size
      [(i + 0.5) * cs, (j + 0.5) * cs, (k + 0.5) * cs]
    end

    # ----------------------------------------------------------- construction

    # Opens a box of cells (inclusive ranges) and assigns material and tint.
    # Call rebuild_faces when done editing.
    def carve(i0, i1, j0, j1, k0, k1, material, tint)
      each_in(i0, i1, j0, j1, k0, k1) do |n|
        @cells[n] = true
        @material[n] = material
        @tint[n] = tint
      end
    end

    def fill(i0, i1, j0, j1, k0, k1)
      each_in(i0, i1, j0, j1, k0, k1) { |n| @cells[n] = false }
    end

    # Randomly raises floor cells / lowers ceiling cells inside a room so caverns
    # look less boxy. Never touches cells next to blockers or floor/ceiling openings.
    def roughen(i0, i1, j0, j1, k0, k1, count, rng)
      count.times do
        i = rng.int(i0 + 1, i1 - 1)
        k = rng.int(k0 + 1, k1 - 1)
        h = rng.int(1, 2)
        if rng.next_f < 0.5
          next if open?(i, j0 - 1, k) || @blockers[idx(i, j0 - 1, k)]
          fill(i, i, j0, j0 + h - 1, k, k)
        else
          next if open?(i, j1 + 1, k) || @blockers[idx(i, j1 + 1, k)]
          fill(i, i, j1 - h + 1, j1, k, k)
        end
      end
    end

    # Turns a cell into a blocker (solid until unsealed). Its neighbours' faces
    # use `material`. The cell keeps its carved material/tint for when it opens.
    def seal(i, j, k, tag, material: tag)
      n = idx(i, j, k)
      @cells[n] = false
      @blockers[n] = tag
      @blocker_materials[n] = material
      n
    end

    # Opens a blocker cell and rebuilds the faces around it.
    def unseal(n)
      return false unless @blockers.delete(n)
      @blocker_materials.delete(n)
      @cells[n] = true
      rebuild_faces_near(n)
      @version += 1
      true
    end

    # Turns an open cell solid at runtime (cave-ins, closing shutters) and
    # rebuilds the faces around it. Returns false if the cell wasn't open.
    def solidify(i, j, k)
      return false unless in_bounds?(i, j, k)
      n = idx(i, j, k)
      return false unless @cells[n]
      @cells[n] = false
      rebuild_faces_near(n)
      @version += 1
      true
    end

    def blocker_index(tag)
      @blockers.each { |n, t| return n if t == tag }
      nil
    end

    # Returns the index of a blocker cell overlapping the sphere, if any.
    def blocker_near(pos, r)
      i0, i1, j0, j1, k0, k1 = sphere_cell_range(pos, r)
      (k0..k1).each do |k|
        (j0..j1).each do |j|
          (i0..i1).each do |i|
            n = idx(i, j, k)
            return n if @blockers[n]
          end
        end
      end
      nil
    end

    # ----------------------------------------------------------- queries

    def open?(i, j, k)
      return false if i < 0 || j < 0 || k < 0 || i >= @nx || j >= @ny || k >= @nz
      @cells[i + @nx * (j + @ny * k)]
    end

    def solid_at?(p)
      cs = @cell_size
      !open?((p[0] / cs).floor, (p[1] / cs).floor, (p[2] / cs).floor)
    end

    def material_of(n)
      @material[n]
    end

    def tint_of(n)
      @tint[n]
    end

    def tint_at(p, fallback = [0.5, 0.5, 0.5])
      i, j, k = cell_of(p)
      return fallback unless open?(i, j, k)
      @tint[idx(i, j, k)]
    end

    # Line of sight by sampling along the segment every `step` units.
    def los?(a, b, step = 2.0)
      d = V.dist(a, b)
      n = (d / step).ceil
      return true if n <= 1
      dx = (b[0] - a[0]) / n
      dy = (b[1] - a[1]) / n
      dz = (b[2] - a[2]) / n
      x = a[0]
      y = a[1]
      z = a[2]
      cs = @cell_size
      (n - 1).times do
        x += dx
        y += dy
        z += dz
        return false unless open?((x / cs).floor, (y / cs).floor, (z / cs).floor)
      end
      true
    end

    # Pushes a sphere out of solid cells. Mutates pos and returns the last
    # collision normal (or nil).
    def collide_sphere(pos, r)
      hit = nil
      cs = @cell_size
      rr = r * r
      i0, i1, j0, j1, k0, k1 = sphere_cell_range(pos, r)
      (k0..k1).each do |k|
        (j0..j1).each do |j|
          (i0..i1).each do |i|
            next if open?(i, j, k)
            cx = D3D.clamp(pos[0], i * cs, (i + 1) * cs)
            cy = D3D.clamp(pos[1], j * cs, (j + 1) * cs)
            cz = D3D.clamp(pos[2], k * cs, (k + 1) * cs)
            dx = pos[0] - cx
            dy = pos[1] - cy
            dz = pos[2] - cz
            d2 = dx * dx + dy * dy + dz * dz
            next if d2 >= rr || d2 < 1e-9
            d = Math.sqrt(d2)
            push = r - d
            nx = dx / d
            ny = dy / d
            nz = dz / d
            pos[0] += nx * push
            pos[1] += ny * push
            pos[2] += nz * push
            hit = [nx, ny, nz]
          end
        end
      end
      hit
    end

    # ----------------------------------------------------------- faces

    def rebuild_faces
      @faces = Array.new(@cells.size)
      (1...@nz - 1).each do |k|
        (1...@ny - 1).each do |j|
          (1...@nx - 1).each do |i|
            n = idx(i, j, k)
            @faces[n] = cell_faces(i, j, k, n) if @cells[n]
          end
        end
      end
      self
    end

    # Recomputes the faces of cell n and its six neighbours only. Use after
    # changing a single cell; much cheaper than rebuild_faces on large grids.
    def rebuild_faces_near(n)
      i, j, k = coords(n)
      @faces[n] = @cells[n] ? cell_faces(i, j, k, n) : nil
      DIRS.each do |d|
        ni = i + d[0]
        nj = j + d[1]
        nk = k + d[2]
        next unless in_bounds?(ni, nj, nk)
        m = idx(ni, nj, nk)
        @faces[m] = @cells[m] ? cell_faces(ni, nj, nk, m) : nil
      end
      self
    end

    # ----------------------------------------------------------- visibility

    # Breadth first walk through open cells starting at the renderer's camera,
    # crossing only cell boundaries (portals) that are inside the view frustum
    # and within the renderer's view distance. Returns the flat indices of
    # the cells reached.
    #
    # Hot path: works on flat cell indices with parallel i/j/k queues, and the
    # neighbour, distance and portal tests are inlined and unrolled per
    # direction (-x, +x, -y, +y, -z, +z). Grid corners are transformed to
    # camera space inline, at most once per pass (gp_x/gp_y/gp_z cache).
    def visible_cells(renderer)
      return visible_cells_native(renderer) if Native.enabled?

      @stamp += 1
      stamp = @stamp
      cs = @cell_size
      cam = renderer.camera_position
      px = cam[0]
      py = cam[1]
      pz = cam[2]
      max_d2 = (renderer.view_distance + cs)**2
      nx = @nx
      ny = @ny
      nz = @nz
      nxy = nx * ny
      ci = (px / cs).floor
      cj = (py / cs).floor
      ck = (pz / cs).floor
      return [] unless ci >= 0 && cj >= 0 && ck >= 0 && ci < nx && cj < ny && ck < nz
      # Camera basis for the inlined to_cam of grid points (same arithmetic).
      rx, ry, rz, ux, uy, uz, fx, fy, fz = renderer.camera_basis
      tx = renderer.tan_x
      ty = renderer.tan_y
      ntx = -tx
      nty = -ty
      gnx = nx + 1
      gnxy = gnx * (ny + 1)
      pgoff = @portal_goff
      po = PORTAL_OFFSETS
      cells = @cells
      visited = @visited
      gp_stamp = @gp_stamp
      gp_x = @gp_x
      gp_y = @gp_y
      gp_z = @gp_z
      n0 = ci + nx * cj + nxy * ck
      qn = [n0]
      qi = [ci]
      qj = [cj]
      qk = [ck]
      visited[n0] = stamp
      result = []
      head = 0
      while head < qn.size
        n = qn[head]
        i = qi[head]
        j = qj[head]
        k = qk[head]
        head += 1
        result << n if cells[n]
        ex = (i + 0.5) * cs - px
        ey = (j + 0.5) * cs - py
        ez = (k + 0.5) * cs - pz
        ex2 = ex * ex
        ey2 = ey * ey
        ez2 = ez * ez
        g0 = i + gnx * j + gnxy * k
        # -x neighbour
        if i > 0
          m = n - 1
          if cells[m] && visited[m] != stamp
            dd = (i - 1 + 0.5) * cs - px
            unless dd * dd + ey2 + ez2 > max_d2
              # Portal test: reject only if all four corners are behind the
              # eye or all outside the same frustum side plane.
              all_behind = all_left = all_right = all_top = all_bottom = true
              q = 0
              while q < 4
                g = g0 + pgoff[q]
                if gp_stamp[g] == stamp
                  cx = gp_x[g]
                  cy = gp_y[g]
                  cz = gp_z[g]
                else
                  gp_stamp[g] = stamp
                  o = q * 3
                  dx = (i + po[o]) * cs - px
                  dy = (j + po[o + 1]) * cs - py
                  dz = (k + po[o + 2]) * cs - pz
                  cx = gp_x[g] = dx * rx + dy * ry + dz * rz
                  cy = gp_y[g] = dx * ux + dy * uy + dz * uz
                  cz = gp_z[g] = dx * fx + dy * fy + dz * fz
                end
                all_behind = false unless cz <= 0
                all_right = false unless cx > cz * tx
                all_left = false unless cx < cz * ntx
                all_top = false unless cy > cz * ty
                all_bottom = false unless cy < cz * nty
                q += 1
              end
              unless all_behind || all_left || all_right || all_top || all_bottom
                visited[m] = stamp
                qn << m
                qi << i - 1
                qj << j
                qk << k
              end
            end
          end
        end
        # +x neighbour
        if i + 1 < nx
          m = n + 1
          if cells[m] && visited[m] != stamp
            dd = (i + 1 + 0.5) * cs - px
            unless dd * dd + ey2 + ez2 > max_d2
              all_behind = all_left = all_right = all_top = all_bottom = true
              q = 4
              while q < 8
                g = g0 + pgoff[q]
                if gp_stamp[g] == stamp
                  cx = gp_x[g]
                  cy = gp_y[g]
                  cz = gp_z[g]
                else
                  gp_stamp[g] = stamp
                  o = q * 3
                  dx = (i + po[o]) * cs - px
                  dy = (j + po[o + 1]) * cs - py
                  dz = (k + po[o + 2]) * cs - pz
                  cx = gp_x[g] = dx * rx + dy * ry + dz * rz
                  cy = gp_y[g] = dx * ux + dy * uy + dz * uz
                  cz = gp_z[g] = dx * fx + dy * fy + dz * fz
                end
                all_behind = false unless cz <= 0
                all_right = false unless cx > cz * tx
                all_left = false unless cx < cz * ntx
                all_top = false unless cy > cz * ty
                all_bottom = false unless cy < cz * nty
                q += 1
              end
              unless all_behind || all_left || all_right || all_top || all_bottom
                visited[m] = stamp
                qn << m
                qi << i + 1
                qj << j
                qk << k
              end
            end
          end
        end
        # -y neighbour
        if j > 0
          m = n - nx
          if cells[m] && visited[m] != stamp
            dd = (j - 1 + 0.5) * cs - py
            unless ex2 + dd * dd + ez2 > max_d2
              all_behind = all_left = all_right = all_top = all_bottom = true
              q = 8
              while q < 12
                g = g0 + pgoff[q]
                if gp_stamp[g] == stamp
                  cx = gp_x[g]
                  cy = gp_y[g]
                  cz = gp_z[g]
                else
                  gp_stamp[g] = stamp
                  o = q * 3
                  dx = (i + po[o]) * cs - px
                  dy = (j + po[o + 1]) * cs - py
                  dz = (k + po[o + 2]) * cs - pz
                  cx = gp_x[g] = dx * rx + dy * ry + dz * rz
                  cy = gp_y[g] = dx * ux + dy * uy + dz * uz
                  cz = gp_z[g] = dx * fx + dy * fy + dz * fz
                end
                all_behind = false unless cz <= 0
                all_right = false unless cx > cz * tx
                all_left = false unless cx < cz * ntx
                all_top = false unless cy > cz * ty
                all_bottom = false unless cy < cz * nty
                q += 1
              end
              unless all_behind || all_left || all_right || all_top || all_bottom
                visited[m] = stamp
                qn << m
                qi << i
                qj << j - 1
                qk << k
              end
            end
          end
        end
        # +y neighbour
        if j + 1 < ny
          m = n + nx
          if cells[m] && visited[m] != stamp
            dd = (j + 1 + 0.5) * cs - py
            unless ex2 + dd * dd + ez2 > max_d2
              all_behind = all_left = all_right = all_top = all_bottom = true
              q = 12
              while q < 16
                g = g0 + pgoff[q]
                if gp_stamp[g] == stamp
                  cx = gp_x[g]
                  cy = gp_y[g]
                  cz = gp_z[g]
                else
                  gp_stamp[g] = stamp
                  o = q * 3
                  dx = (i + po[o]) * cs - px
                  dy = (j + po[o + 1]) * cs - py
                  dz = (k + po[o + 2]) * cs - pz
                  cx = gp_x[g] = dx * rx + dy * ry + dz * rz
                  cy = gp_y[g] = dx * ux + dy * uy + dz * uz
                  cz = gp_z[g] = dx * fx + dy * fy + dz * fz
                end
                all_behind = false unless cz <= 0
                all_right = false unless cx > cz * tx
                all_left = false unless cx < cz * ntx
                all_top = false unless cy > cz * ty
                all_bottom = false unless cy < cz * nty
                q += 1
              end
              unless all_behind || all_left || all_right || all_top || all_bottom
                visited[m] = stamp
                qn << m
                qi << i
                qj << j + 1
                qk << k
              end
            end
          end
        end
        # -z neighbour
        if k > 0
          m = n - nxy
          if cells[m] && visited[m] != stamp
            dd = (k - 1 + 0.5) * cs - pz
            unless ex2 + ey2 + dd * dd > max_d2
              all_behind = all_left = all_right = all_top = all_bottom = true
              q = 16
              while q < 20
                g = g0 + pgoff[q]
                if gp_stamp[g] == stamp
                  cx = gp_x[g]
                  cy = gp_y[g]
                  cz = gp_z[g]
                else
                  gp_stamp[g] = stamp
                  o = q * 3
                  dx = (i + po[o]) * cs - px
                  dy = (j + po[o + 1]) * cs - py
                  dz = (k + po[o + 2]) * cs - pz
                  cx = gp_x[g] = dx * rx + dy * ry + dz * rz
                  cy = gp_y[g] = dx * ux + dy * uy + dz * uz
                  cz = gp_z[g] = dx * fx + dy * fy + dz * fz
                end
                all_behind = false unless cz <= 0
                all_right = false unless cx > cz * tx
                all_left = false unless cx < cz * ntx
                all_top = false unless cy > cz * ty
                all_bottom = false unless cy < cz * nty
                q += 1
              end
              unless all_behind || all_left || all_right || all_top || all_bottom
                visited[m] = stamp
                qn << m
                qi << i
                qj << j
                qk << k - 1
              end
            end
          end
        end
        # +z neighbour
        if k + 1 < nz
          m = n + nxy
          if cells[m] && visited[m] != stamp
            dd = (k + 1 + 0.5) * cs - pz
            unless ex2 + ey2 + dd * dd > max_d2
              all_behind = all_left = all_right = all_top = all_bottom = true
              q = 20
              while q < 24
                g = g0 + pgoff[q]
                if gp_stamp[g] == stamp
                  cx = gp_x[g]
                  cy = gp_y[g]
                  cz = gp_z[g]
                else
                  gp_stamp[g] = stamp
                  o = q * 3
                  dx = (i + po[o]) * cs - px
                  dy = (j + po[o + 1]) * cs - py
                  dz = (k + po[o + 2]) * cs - pz
                  cx = gp_x[g] = dx * rx + dy * ry + dz * rz
                  cy = gp_y[g] = dx * ux + dy * uy + dz * uz
                  cz = gp_z[g] = dx * fx + dy * fy + dz * fz
                end
                all_behind = false unless cz <= 0
                all_right = false unless cx > cz * tx
                all_left = false unless cx < cz * ntx
                all_top = false unless cy > cz * ty
                all_bottom = false unless cy < cz * nty
                q += 1
              end
              unless all_behind || all_left || all_right || all_top || all_bottom
                visited[m] = stamp
                qn << m
                qi << i
                qj << j
                qk << k + 1
              end
            end
          end
        end
      end
      result
    end

    # visible_cells in C (the optional extension; D3D::Ext.visible_cells
    # mirrors it, with its own scratch arrays in @native_visibility).
    def visible_cells_native(renderer)
      @native_visibility ||= Ext.visibility_state(@cells.size, @gp_stamp.size)
      cam = renderer.camera_position
      Ext.visible_cells(@native_visibility, @cells, [
        cam[0], cam[1], cam[2], @cell_size, renderer.view_distance, *renderer.camera_basis,
        renderer.tan_x, renderer.tan_y, @nx, @ny, @nz
      ])
    end

    private

    # Wall faces of open cell (i, j, k) with index n, or nil if it has none.
    def cell_faces(i, j, k, n)
      list = []
      DIRS.each_with_index do |d, di|
        m = idx(i + d[0], j + d[1], k + d[2])
        next if @cells[m]
        material = @blocker_materials[m] || @material[n]
        list << make_face(i, j, k, di, material, n)
      end
      list.empty? ? nil : list
    end

    def each_in(i0, i1, j0, j1, k0, k1)
      (k0..k1).each do |k|
        (j0..j1).each do |j|
          (i0..i1).each do |i|
            yield idx(i, j, k) if in_bounds?(i, j, k)
          end
        end
      end
    end

    def sphere_cell_range(pos, r)
      cs = @cell_size
      [((pos[0] - r) / cs).floor, ((pos[0] + r) / cs).floor,
       ((pos[1] - r) / cs).floor, ((pos[1] + r) / cs).floor,
       ((pos[2] - r) / cs).floor, ((pos[2] + r) / cs).floor]
    end

    def make_face(i, j, k, dir, material, n)
      cs = @cell_size
      x0 = i * cs
      y0 = j * cs
      z0 = k * cs
      x1 = x0 + cs
      y1 = y0 + cs
      z1 = z0 + cs
      c = case dir
          when 0 then [[x0, y0, z0], [x0, y0, z1], [x0, y1, z0], [1, 0, 0]]
          when 1 then [[x1, y0, z1], [x1, y0, z0], [x1, y1, z1], [-1, 0, 0]]
          when 2 then [[x0, y0, z0], [x1, y0, z0], [x0, y0, z1], [0, 1, 0]]
          when 3 then [[x0, y1, z1], [x1, y1, z1], [x0, y1, z0], [0, -1, 0]]
          when 4 then [[x1, y0, z0], [x0, y0, z0], [x1, y1, z0], [0, 0, 1]]
          else        [[x0, y0, z1], [x1, y0, z1], [x0, y1, z1], [0, 0, -1]]
          end
      c0 = c[0]
      tint = @tint[n]
      shade = @dir_shade[dir]
      CellFace.new(c[3], c0, V.sub(c[1], c0), V.sub(c[2], c0), material,
                   [tint[0] * shade, tint[1] * shade, tint[2] * shade], n)
    end
  end
end
