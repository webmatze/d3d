require "minitest/autorun"
require_relative "../app/d3d/v"
require_relative "../app/d3d/pose"
require_relative "../app/d3d/flat_mesh"
require_relative "../app/d3d/cell_grid"
require_relative "../app/d3d/native"
require_relative "../app/d3d/depth_sort"
require_relative "../app/d3d/scene_renderer"

class SceneRendererTest < Minitest::Test
  FakeOutputs = Struct.new(:sprites)

  def renderer
    D3D::SceneRenderer.new(focal: 620, materials: { rock: { path: "rock.png", size: 128 } })
  end

  def test_clip_near_interpolates_uv
    r = renderer
    poly = [[0.0, 0.0, -1.0, 0.0, 0.0], [0.0, 0.0, 1.8, 100.0, 0.0], [1.0, 0.0, 1.8, 100.0, 50.0]]
    out = r.clip_near(poly)
    clipped = out.select { |p| p[2] == r.near }
    assert_equal 2, clipped.size
    # a -> b crosses z = 0.4 at t = 0.5 so u = 50
    assert_in_delta 50.0, clipped.last[3], 1e-9
    out.each { |p| assert p[2] >= r.near }
  end

  def test_face_behind_camera_emits_nothing
    grid = D3D::CellGrid.new(6, 6, 8, cell_size: 10.0)
    grid.carve(2, 2, 2, 2, 2, 4, :rock, [1.0, 1.0, 1.0])
    grid.rebuild_faces
    r = renderer
    # camera in the middle cell looking +z: the far end wall is visible, the near end wall behind us is not
    r.begin_frame(D3D::Pose.new([25.0, 25.0, 35.0], [0.0, 0.0, 1.0]))
    back_wall = grid.faces[grid.idx(2, 2, 2)].find { |f| f.normal == [0, 0, 1] }
    r.draw_face(back_wall)
    assert_equal 0, r.triangle_count

    front_wall = grid.faces[grid.idx(2, 2, 4)].find { |f| f.normal == [0, 0, -1] }
    r.draw_face(front_wall)
    assert r.triangle_count > 0
  end

  def test_close_faces_are_subdivided_more
    grid = D3D::CellGrid.new(6, 6, 40, cell_size: 10.0)
    grid.carve(2, 2, 2, 2, 2, 30, :rock, [1.0, 1.0, 1.0])
    grid.rebuild_faces
    wall = grid.faces[grid.idx(2, 2, 30)].find { |f| f.normal == [0, 0, -1] }
    near = renderer
    near.begin_frame(D3D::Pose.new([25.0, 25.0, 295.0], [0.0, 0.0, 1.0]))
    near.draw_face(wall)
    far = renderer
    far.begin_frame(D3D::Pose.new([25.0, 25.0, 215.0], [0.0, 0.0, 1.0]))
    far.draw_face(wall)
    assert near.triangle_count > far.triangle_count
    assert_equal 2, far.triangle_count
  end

  # A 35-cell straight tunnel, camera at one end looking down it.
  def long_tunnel
    grid = D3D::CellGrid.new(6, 6, 40, cell_size: 10.0)
    grid.carve(2, 2, 2, 2, 2, 36, :rock, [1.0, 1.0, 1.0])
    grid.rebuild_faces
    [grid, D3D::Pose.new([25.0, 25.0, 25.0], [0.0, 0.0, 1.0])]
  end

  def test_view_distance_defaults_to_fog
    r = D3D::SceneRenderer.new(fog: 90)
    assert_equal 90.0, r.view_distance
    assert_equal :linear, r.fog_mode
  end

  def test_view_distance_limits_the_cells_drawn
    grid, pose = long_tunnel
    short = D3D::SceneRenderer.new(focal: 620, fog: 140, materials: { rock: { path: "rock.png", size: 128 } })
    long = D3D::SceneRenderer.new(focal: 620, fog: 140, view_distance: 400, fog_mode: :exponential,
                                  materials: { rock: { path: "rock.png", size: 128 } })
    short.begin_frame(pose)
    short.draw_grid(grid)
    long.begin_frame(pose)
    long.draw_grid(grid)
    assert long.last_visible.size > short.last_visible.size
    assert long.triangle_count > short.triangle_count
  end

  # Exponential fog: close to the linear fog near the camera, never black.
  def test_exponential_fog_fades_without_going_black
    linear = D3D::SceneRenderer.new(fog: 140)
    expo = D3D::SceneRenderer.new(fog: 140, view_distance: 400, fog_mode: :exponential)
    [linear, expo].each { |r| r.begin_frame(D3D::Pose.new([0.0, 0.0, 0.0], [0.0, 0.0, 1.0])) }
    tint = [1.0, 1.0, 1.0]
    assert_in_delta linear.light_at(0, 0, 50, 50.0, tint)[0], expo.light_at(0, 0, 50, 50.0, tint)[0], 5.0
    assert_equal [0, 0, 0], linear.light_at(0, 0, 200, 200.0, tint)
    far = expo.light_at(0, 0, 200, 200.0, tint)[0]
    assert far > 0
    assert far < expo.light_at(0, 0, 100, 100.0, tint)[0]
  end

  def test_fog_mode_is_checked
    assert_raises(ArgumentError) { D3D::SceneRenderer.new(fog_mode: :fast) }
  end

  def test_output_is_sorted_back_to_front
    r = renderer
    r.begin_frame(D3D::Pose.new)
    r.draw_glow([0.0, 0.0, 10.0], 1.0, 255, 255, 255)
    r.draw_glow([0.0, 0.0, 50.0], 1.0, 255, 0, 0)
    r.draw_glow([0.0, 0.0, 20.0], 1.0, 0, 255, 0)
    colors = r.sorted_primitives.map { |p| [p[:r], p[:g], p[:b]] }
    assert_equal [[255, 0, 0], [0, 255, 0], [255, 255, 255]], colors
  end

  def test_draw_mesh_culls_back_faces
    r = renderer
    r.begin_frame(D3D::Pose.new)
    cube = D3D::FlatMesh.new.box(0, 0, 0, 1, 1, 1, [200, 0, 0])
    r.draw_mesh(cube, [0.0, 0.0, 10.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0])
    assert_equal 2, r.triangle_count # only the face towards the camera
  end

  def test_flush_pushes_sorted_sprites
    r = renderer
    r.begin_frame(D3D::Pose.new)
    r.draw_glow([0.0, 0.0, 10.0], 1.0, 255, 255, 255)
    out = FakeOutputs.new([])
    r.flush(out)
    assert_equal 1, out.sprites.first.size
  end

  def test_project
    r = renderer
    r.begin_frame(D3D::Pose.new)
    sx, sy, z = r.project([1.0, 0.0, 10.0])
    assert_in_delta 640 + 62.0, sx, 1e-9
    assert_in_delta 360.0, sy, 1e-9
    assert_in_delta 10.0, z, 1e-9
    assert_nil r.project([0.0, 0.0, -1.0])
  end

  def wall_brightness(r)
    grid = D3D::CellGrid.new(6, 6, 8, cell_size: 10.0)
    grid.carve(2, 2, 2, 2, 2, 4, :rock, [0.05, 0.05, 0.05])
    grid.rebuild_faces
    r.begin_frame(D3D::Pose.new([25.0, 25.0, 25.0], [0.0, 0.0, 1.0]))
    wall = grid.faces[grid.idx(2, 2, 4)].find { |f| f.normal == [0, 0, -1] }
    r.draw_face(wall)
    r.sorted_primitives.map { |p| p[:r] }.max
  end

  def test_headlight_can_be_dimmed_between_frames
    r = renderer
    bright = wall_brightness(r)
    r.headlight = 0.05
    r.headlight_range = 20
    assert_equal 0.05, r.headlight
    assert wall_brightness(r) < bright / 3
  end

  def mesh_brightness(ambient)
    r = renderer
    r.begin_frame(D3D::Pose.new)
    cube = D3D::FlatMesh.new.box(0, 0, 0, 1, 1, 1, [200, 200, 200])
    if ambient
      r.draw_mesh(cube, [0.0, 0.0, 10.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0], 1.0, [0.0, 0.0, 0.0], 0.0, ambient: ambient)
    else
      r.draw_mesh(cube, [0.0, 0.0, 10.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0], 1.0, [0.0, 0.0, 0.0])
    end
    r.sorted_primitives.map { |p| p[:r] }.max
  end

  def test_mesh_ambient_defaults_to_previous_brightness
    assert_equal mesh_brightness(0.6), mesh_brightness(nil)
  end

  def test_low_mesh_ambient_darkens_non_emissive_triangles
    assert mesh_brightness(0.05) < mesh_brightness(0.6) / 5
  end

  def test_emissive_triangles_ignore_ambient
    r = renderer
    r.begin_frame(D3D::Pose.new)
    eye = D3D::FlatMesh.new.box(0, 0, 0, 1, 1, 1, [255, 40, 40], emissive: true)
    r.draw_mesh(eye, [0.0, 0.0, 10.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0], 1.0, [0.0, 0.0, 0.0], 0.0, ambient: 0.0)
    assert_equal 255, r.sorted_primitives.first[:r]
  end
end
