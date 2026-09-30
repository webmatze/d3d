require "minitest/autorun"
require_relative "../app/d3d/v"
require_relative "../app/d3d/native"
require_relative "../app/d3d/depth_sort"
require_relative "../app/d3d/pose"
require_relative "../app/d3d/cell_grid"
require_relative "../app/d3d/scene_renderer"

class CellGridTest < Minitest::Test
  CS = 10.0

  # 1x1x3 corridor along z: cells (2,2,2)..(2,2,4)
  def corridor
    grid = D3D::CellGrid.new(6, 6, 8, cell_size: CS)
    grid.carve(2, 2, 2, 2, 2, 4, :rock, [1.0, 1.0, 1.0])
    grid.rebuild_faces
  end

  def test_coords_round_trip
    grid = D3D::CellGrid.new(6, 5, 7)
    n = grid.idx(3, 4, 5)
    assert_equal [3, 4, 5], grid.coords(n)
  end

  def test_carve_never_opens_the_border
    grid = D3D::CellGrid.new(4, 4, 4)
    grid.carve(0, 3, 0, 3, 0, 3, :rock, [1, 1, 1])
    refute grid.open?(0, 1, 1)
    assert grid.open?(1, 1, 1)
  end

  def test_faces_only_against_solid_cells_with_inward_normals
    grid = corridor
    middle = grid.faces[grid.idx(2, 2, 3)]
    assert_equal 4, middle.size # no faces towards the open neighbours
    end_cell = grid.faces[grid.idx(2, 2, 2)]
    assert_equal 5, end_cell.size
    center = grid.cell_center(2, 2, 2)
    end_cell.each do |f|
      to_center = D3D::V.sub(center, f.c0)
      assert D3D::V.dot(to_center, f.normal) > 0
    end
  end

  def test_floor_is_brighter_than_ceiling
    grid = corridor
    faces = grid.faces[grid.idx(2, 2, 3)]
    floor = faces.find { |f| f.normal == [0, 1, 0] }
    ceiling = faces.find { |f| f.normal == [0, -1, 0] }
    assert floor.shade[0] > ceiling.shade[0]
  end

  def test_collide_sphere_pushes_out_of_walls
    grid = corridor
    pos = [21.0, 25.0, 35.0] # 1 unit from the -x wall at x = 20
    normal = grid.collide_sphere(pos, 2.5)
    assert_in_delta 22.5, pos[0], 1e-9
    assert_equal [1.0, 0.0, 0.0], normal
  end

  def test_line_of_sight
    grid = corridor
    assert grid.los?([25.0, 25.0, 21.0], [25.0, 25.0, 49.0])
    refute grid.los?([25.0, 25.0, 25.0], [45.0, 25.0, 25.0])
  end

  def test_seal_and_unseal
    grid = corridor
    n = grid.seal(2, 2, 3, :door, material: :door_blue)
    grid.rebuild_faces
    refute grid.open?(2, 2, 3)
    assert_equal n, grid.blocker_near([25.0, 25.0, 29.0], 2.0)
    door_face = grid.faces[grid.idx(2, 2, 2)].find { |f| f.normal == [0, 0, -1] }
    assert_equal :door_blue, door_face.material

    assert grid.unseal(n)
    assert grid.open?(2, 2, 3)
    assert_nil grid.blocker_index(:door)
    assert_equal 5, grid.faces[grid.idx(2, 2, 2)].size
  end

  def test_visible_cells_skips_cells_behind_the_camera
    grid = D3D::CellGrid.new(12, 6, 12, cell_size: CS)
    grid.carve(1, 10, 2, 2, 5, 5, :rock, [1, 1, 1]) # corridor along x
    grid.rebuild_faces
    renderer = D3D::SceneRenderer.new(materials: { rock: { path: "r.png", size: 128 } })
    pose = D3D::Pose.new([55.0, 25.0, 55.0], [1.0, 0.0, 0.0]) # in cell 5, looking +x
    renderer.begin_frame(pose)
    visible = grid.visible_cells(renderer).map { |n| grid.coords(n)[0] }
    assert_includes visible, 5
    assert_includes visible, 9
    refute_includes visible, 2
  end

  def test_visible_cells_see_through_a_portal_closer_than_the_near_plane
    grid = D3D::CellGrid.new(3, 3, 10, cell_size: CS)
    grid.carve(1, 1, 1, 1, 1, 8, :rock, [1, 1, 1]) # corridor along z
    grid.rebuild_faces
    renderer = D3D::SceneRenderer.new(materials: { rock: { path: "r.png", size: 128 } })
    # 0.2 units before the z = 30 boundary, inside the 0.4 near distance
    pose = D3D::Pose.new([15.0, 15.0, 29.8], [0.0, 0.0, 1.0])
    renderer.begin_frame(pose)
    visible = grid.visible_cells(renderer).map { |n| grid.coords(n)[2] }
    assert_includes visible, 3
    assert_includes visible, 8
  end

  # Face signature per cell: [normal, material, corner] for every face.
  def face_signature(grid)
    grid.faces.map { |list| list && list.map { |f| [f.normal, f.material, f.c0] }.sort }
  end

  def room
    grid = D3D::CellGrid.new(10, 8, 10, cell_size: CS)
    grid.carve(2, 6, 2, 5, 2, 6, :rock, [1.0, 1.0, 1.0])
    grid.seal(4, 3, 4, :door, material: :door_blue)
    grid.rebuild_faces
  end

  def test_solidify_matches_full_rebuild
    local = room
    assert local.solidify(3, 2, 3)
    full = room
    full.fill(3, 3, 2, 2, 3, 3)
    full.rebuild_faces
    assert_equal face_signature(full), face_signature(local)
  end

  def test_unseal_matches_full_rebuild
    local = room
    local.unseal(local.blocker_index(:door))
    full = D3D::CellGrid.new(10, 8, 10, cell_size: CS)
    full.carve(2, 6, 2, 5, 2, 6, :rock, [1.0, 1.0, 1.0])
    full.rebuild_faces
    assert_equal face_signature(full), face_signature(local)
  end

  def test_solidify_removes_faces_and_walls_off_neighbours
    grid = room
    n = grid.idx(3, 3, 3)
    before = grid.faces[grid.idx(2, 3, 3)]&.size || 0
    assert grid.solidify(3, 3, 3)
    refute grid.open?(3, 3, 3)
    assert_nil grid.faces[n]
    assert_equal before + 1, grid.faces[grid.idx(2, 3, 3)].size
  end

  def test_solidify_rejects_solid_and_border_cells
    grid = room
    refute grid.solidify(0, 3, 3)
    refute grid.solidify(8, 3, 3)
  end

  def test_version_bumps_on_runtime_changes
    grid = room
    v = grid.version
    grid.solidify(3, 3, 3)
    assert_equal v + 1, grid.version
    grid.unseal(grid.blocker_index(:door))
    assert_equal v + 2, grid.version
    refute grid.solidify(3, 3, 3)
    assert_equal v + 2, grid.version
  end
end
