module D3D
  # Rotatable 3D wireframe map of the explored part of a CellGrid.
  # Only the outline edges of walls are drawn: an edge is skipped when the wall
  # simply continues flat into the neighbouring cell.
  #
  #   map = D3D::GridMap.new(grid, edge_color: ->(cell, blocker_tag) { [r, g, b] })
  #   map.explore(renderer.last_visible, pose.position)   # every game frame
  #   map.open(pose); map.update(args.inputs); map.render(args.outputs, pose, markers)
  #
  # edge_color is called with the open cell's index and the blocker tag of the
  # wall (nil for plain rock). markers: [[pos, [r, g, b], size], ...]
  class GridMap
    NEAR = 1.0

    attr_reader :edges
    attr_accessor :yaw, :pitch, :distance

    def initialize(grid, edge_color: nil, explore_radius: 100.0, focal: 620.0,
                   width: 1280, height: 720, ship_color: [255, 230, 60])
      @grid = grid
      @edge_color = edge_color || ->(n, _tag) { grid.tint_of(n).map { |t| D3D.clamp(t * 190, 40, 230) } }
      @explore_radius = explore_radius
      @focal = focal
      @half_w = width / 2.0
      @half_h = height / 2.0
      @ship_color = ship_color
      @explored = Array.new(grid.cells.size, false)
      @explored_list = []
      @edges = {}
      @grid_points = (grid.nx + 1) * (grid.ny + 1) * (grid.nz + 1)
      @version = grid.version
      @yaw = 0.0
      @pitch = 0.5
      @distance = 120.0
    end

    def explored?(pos)
      i, j, k = @grid.cell_of(pos)
      @grid.open?(i, j, k) && @explored[@grid.idx(i, j, k)]
    end

    # Marks visible cells within explore_radius of the camera as explored.
    def explore(cells, cam)
      r2 = @explore_radius * @explore_radius
      cs = @grid.cell_size
      cells.each do |n|
        next if @explored[n]
        i, j, k = @grid.coords(n)
        dx = (i + 0.5) * cs - cam[0]
        dy = (j + 0.5) * cs - cam[1]
        dz = (k + 0.5) * cs - cam[2]
        next if dx * dx + dy * dy + dz * dz > r2
        @explored[n] = true
        @explored_list << n
        add_cell_edges(i, j, k)
      end
    end

    def rebuild
      @edges = {}
      @explored_list.each do |n|
        next unless @grid.cells[n]
        i, j, k = @grid.coords(n)
        add_cell_edges(i, j, k)
      end
      @version = @grid.version
    end

    # ------------------------------------------------------------- view

    # Call when the map is opened: rebuilds after the grid changed (doors
    # opened, cells solidified) and faces the map along the pose's heading.
    def open(pose)
      rebuild if @grid.version != @version
      @yaw = Math.atan2(pose.fwd[0], pose.fwd[2])
      @pitch = 0.5
      @distance = 120.0
    end

    # Mouse / arrows / A D rotate, W S / wheel / bumpers zoom.
    def update(inputs)
      kb = inputs.keyboard
      ms = inputs.mouse
      pad = inputs.controller_one
      @yaw += (ms.relative_x || 0) * 0.006
      @pitch -= (ms.relative_y || 0) * 0.006
      @yaw -= 0.03 if kb.left_arrow || kb.a
      @yaw += 0.03 if kb.right_arrow || kb.d
      @pitch += 0.03 if kb.up_arrow
      @pitch -= 0.03 if kb.down_arrow
      rx = pad.right_analog_x_perc || 0
      ry = pad.right_analog_y_perc || 0
      @yaw += rx * 0.04 if rx.abs > 0.15
      @pitch -= ry * 0.04 if ry.abs > 0.15
      @distance -= 3 if kb.w || pad.r1
      @distance += 3 if kb.s || pad.l1
      wheel = ms.wheel
      @distance -= wheel.y * 12 if wheel
      @pitch = D3D.clamp(@pitch, -1.45, 1.45)
      @distance = D3D.clamp(@distance, 25.0, 450.0)
    end

    # Returns the line primitives of the map (orbiting pose.position).
    def lines(pose, markers = [])
      target = pose.position
      cp = Math.cos(@pitch)
      @fwd = [Math.sin(@yaw) * cp, -Math.sin(@pitch), Math.cos(@yaw) * cp]
      @right, @up = V.basis_from_forward(@fwd)
      @cam = V.madd(target, @fwd, -@distance)
      fade_range = @distance + 250.0

      out = []
      @edges.each_value do |p1, p2, color|
        seg = project_segment(p1, p2)
        next unless seg
        f = D3D.clamp(1.3 - seg[4] / fade_range, 0.25, 1.0)
        out << { x: seg[0], y: seg[1], x2: seg[2], y2: seg[3],
                 r: color[0] * f, g: color[1] * f, b: color[2] * f }
      end
      markers.each { |pos, color, size| diamond(out, pos, size, color) }
      ship_marker(out, pose)
      out
    end

    def render(outputs, pose, markers = [])
      outputs.lines << lines(pose, markers)
    end

    private

    def open_at?(c)
      @grid.open?(c[0], c[1], c[2])
    end

    def blocker_at(c)
      @grid.blockers[@grid.idx(c[0], c[1], c[2])]
    end

    def add_cell_edges(i, j, k)
      c = [i, j, k]
      n = @grid.idx(i, j, k)
      CellGrid::DIRS.each_with_index do |d, di|
        nb = [i + d[0], j + d[1], k + d[2]]
        next if open_at?(nb)
        axis = (di / 2).to_i
        sign = d[axis]
        plane = c[axis] + (sign > 0 ? 1 : 0)
        tag = blocker_at(nb)
        color = @edge_color.call(n, tag)
        others = [0, 1, 2] - [axis]
        others.each do |a|
          b = a == others[0] ? others[1] : others[0]
          [-1, 1].each do |s|
            side = c.dup
            side[a] += s
            if open_at?(side)
              beyond = side.dup
              beyond[axis] += sign
              next if !open_at?(beyond) && blocker_at(beyond) == tag
            end
            p1 = [0, 0, 0]
            p1[axis] = plane
            p1[a] = c[a] + (s > 0 ? 1 : 0)
            p1[b] = c[b]
            p2 = p1.dup
            p2[b] += 1
            add_edge(p1, p2, color, !tag.nil?)
          end
        end
      end
    end

    def add_edge(p1, p2, color, priority)
      g1 = grid_key(p1)
      g2 = grid_key(p2)
      key = g1 < g2 ? g1 * @grid_points + g2 : g2 * @grid_points + g1
      return if @edges[key] && !priority
      cs = @grid.cell_size
      @edges[key] = [p1.map { |v| v * cs }, p2.map { |v| v * cs }, color]
    end

    def grid_key(p)
      p[0] + (@grid.nx + 1) * (p[1] + (@grid.ny + 1) * p[2])
    end

    def project_segment(p1, p2)
      a = to_cam(p1)
      b = to_cam(p2)
      return nil if a[2] < NEAR && b[2] < NEAR
      if a[2] < NEAR
        a = clip(b, a)
      elsif b[2] < NEAR
        b = clip(a, b)
      end
      [@half_w + a[0] * @focal / a[2], @half_h + a[1] * @focal / a[2],
       @half_w + b[0] * @focal / b[2], @half_h + b[1] * @focal / b[2],
       (a[2] + b[2]) * 0.5]
    end

    def clip(inside, outside)
      t = (NEAR - inside[2]) / (outside[2] - inside[2])
      [inside[0] + (outside[0] - inside[0]) * t, inside[1] + (outside[1] - inside[1]) * t, NEAR]
    end

    def to_cam(p)
      d = V.sub(p, @cam)
      [V.dot(d, @right), V.dot(d, @up), V.dot(d, @fwd)]
    end

    def line3(out, p1, p2, color)
      seg = project_segment(p1, p2)
      return unless seg
      out << { x: seg[0], y: seg[1], x2: seg[2], y2: seg[3], r: color[0], g: color[1], b: color[2] }
    end

    def diamond(out, pos, s, color)
      pts = [[s, 0, 0], [0, s, 0], [-s, 0, 0], [0, -s, 0], [0, 0, s], [0, 0, -s]].map { |o| V.add(pos, o) }
      [[0, 1], [1, 2], [2, 3], [3, 0], [0, 4], [1, 4], [2, 4], [3, 4], [0, 5], [1, 5], [2, 5], [3, 5]].each do |a, b|
        line3(out, pts[a], pts[b], color)
      end
    end

    def ship_marker(out, pose)
      p = pose.position
      nose = V.madd(p, pose.fwd, 5)
      tail = V.madd(p, pose.fwd, -3)
      l = V.madd(tail, pose.right, -3)
      r = V.madd(tail, pose.right, 3)
      top = V.madd(tail, pose.up, 2)
      [[nose, l], [nose, r], [l, r], [nose, top], [l, top], [r, top]].each do |a, b|
        line3(out, a, b, @ship_color)
      end
    end
  end
end
