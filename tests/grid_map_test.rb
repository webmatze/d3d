require "minitest/autorun"
require_relative "../app/d3d/v"
require_relative "../app/d3d/native"
require_relative "../app/d3d/depth_sort"
require_relative "../app/d3d/pose"
require_relative "../app/d3d/cell_grid"
require_relative "../app/d3d/grid_map"

class GridMapTest < Minitest::Test
  def corridor_map
    grid = D3D::CellGrid.new(6, 6, 8, cell_size: 10.0)
    grid.carve(2, 2, 2, 2, 2, 4, :rock, [1.0, 1.0, 1.0])
    grid.rebuild_faces
    map = D3D::GridMap.new(grid, edge_color: ->(_n, tag) { tag ? [0, 0, 255] : [200, 200, 200] })
    cells = [grid.idx(2, 2, 2), grid.idx(2, 2, 3), grid.idx(2, 2, 4)]
    [grid, map, cells]
  end

  def test_straight_corridor_has_only_outline_edges
    _grid, map, cells = corridor_map
    map.explore(cells, [25.0, 25.0, 35.0])
    # 4 long edges (each made of 3 unit segments) + 4 edges around each end cap
    assert_equal 4 * 3 + 4 * 2, map.edges.size
  end

  def test_unexplored_cells_are_not_drawn
    _grid, map, cells = corridor_map
    map.explore(cells, [9999.0, 9999.0, 9999.0])
    assert_equal 0, map.edges.size
  end

  def test_blocker_edges_get_blocker_colour
    grid, map, cells = corridor_map
    grid.seal(2, 2, 4, :door)
    grid.rebuild_faces
    map.explore(cells.first(2), [25.0, 25.0, 25.0])
    assert map.edges.values.any? { |_a, _b, color| color == [0, 0, 255] }
  end

  def test_lines_include_ship_marker
    _grid, map, cells = corridor_map
    map.explore(cells, [25.0, 25.0, 35.0])
    pose = D3D::Pose.new([25.0, 25.0, 35.0])
    map.open(pose)
    lines = map.lines(pose)
    assert lines.size >= map.edges.size
  end

  def test_edge_keys_stay_unique_in_large_grids
    grid = D3D::CellGrid.new(100, 100, 100) # 101^3 > 1_000_000 grid points
    map = D3D::GridMap.new(grid)
    # grid keys 0/1_000_002 and 1/2 used to collide at 1_000_002
    far = [1_000_002 % 101, (1_000_002 / 101) % 101, 1_000_002 / (101 * 101)]
    map.send(:add_edge, [0, 0, 0], far, [1, 1, 1], false)
    map.send(:add_edge, [1, 0, 0], [2, 0, 0], [2, 2, 2], false)
    assert_equal 2, map.edges.size
  end

  def test_open_rebuilds_after_solidify
    grid, map, cells = corridor_map
    map.explore(cells, [25.0, 25.0, 35.0])
    before = map.edges.size
    grid.solidify(2, 2, 4)
    map.open(D3D::Pose.new([25.0, 25.0, 25.0]))
    refute_equal before, map.edges.size
  end
end
