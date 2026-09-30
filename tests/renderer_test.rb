require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("..", __dir__)
require "app/d3d/d3d.rb"

class RendererTest < Minitest::Test
  GREEN = { r: 80, g: 120, b: 80, a: 255 }.freeze

  # The basic demo's 20x20 ground: its corners lie behind the camera.
  def ground
    model = D3D::Model.new(mesh: D3D::Mesh.plane(width: 20, depth: 20), color: GREEN.dup)
    model.position.y = -1.5
    model
  end

  def camera
    D3D::Camera.new(position: D3D::Vec3.new(0, 2, 8), fov: 70)
  end

  def cube(x, y, z, color: GREEN.dup)
    D3D::Model.new(mesh: D3D::Mesh.cube, position: D3D::Vec3.new(x, y, z), color: color)
  end

  def voxel_floor
    world = D3D::VoxelWorld.new
    4.times { |x| 4.times { |z| world.add_block(x, 0, z, { r: 200, g: 200, b: 200, a: 255 }) } }
    world.build_mesh
    world
  end

  def test_triangles_crossing_the_near_plane_are_clipped_not_dropped
    tris = D3D::Renderer.render(camera, [ground])
    refute_empty tris
    # the clipped ground reaches the bottom edge of the screen
    assert tris.flat_map { |t| [t[:y], t[:y2], t[:y3]] }.min <= 0
  end

  def test_clipping_interpolates_uvs
    out = []
    poly = [[0.0, 0.0, 0.0, -1.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0, 10.0, 0.0], [1.0, 0.0, 0.0, 1.0, 10.0, 10.0]]
    D3D::Renderer.emit_clipped(out, poly, 0.5, 1, 2, 3, 255, "t.png", false)
    assert_equal 2, out.size # clipped triangle becomes a quad -> 2 triangles
    us = out.flat_map { |t| [t[:source_x], t[:source_x2], t[:source_x3]] }
    assert_includes us.map { |u| u.round(6) }, 7.5 # 3/4 of the way from -1 to 1
    assert out.all? { |t| t[:path] == "t.png" }
  end

  def test_triangles_fully_behind_the_camera_are_skipped
    assert_empty D3D::Renderer.render(camera, [cube(0, 2, 11)])
  end

  def test_back_faces_are_culled
    # looking straight at one side of the cube: only its 2 front triangles
    tris = D3D::Renderer.render(D3D::Camera.new(position: D3D::Vec3.new(0, 0, 5)), [cube(0, 0, 0)])
    assert_equal 2, tris.size
  end

  def test_mirrored_models_show_their_outside
    cam = D3D::Camera.new(position: D3D::Vec3.new(0, 0, 5))
    mirrored = cube(0, 0, 0)
    mirrored.set_scale(-1, 1, 1)
    tris = D3D::Renderer.render(cam, [mirrored])
    assert_equal 2, tris.size
    tris.each { |t| assert_in_delta 4.5, depth_of(t, cam), 0.01 } # the near face at z = 0.5
  end

  def test_textured_models_keep_their_texture_and_solids_use_path_solid
    cam = D3D::Camera.new(position: D3D::Vec3.new(0, 0, 5))
    textured = cube(0, 0, 0)
    textured.texture = "sprites/block.png"
    tris = D3D::Renderer.render(cam, [textured]) + D3D::Renderer.render(D3D::Camera.new(position: D3D::Vec3.new(0, 0, 0.55)), [textured])
    refute_empty tris
    tris.each do |t|
      assert_equal "sprites/block.png", t[:path]
    end
    solids = D3D::Renderer.render(cam, [cube(0, 0, 0)]) +
             D3D::Renderer.render(D3D::Camera.new(position: D3D::Vec3.new(0, 0, 0.55)), [cube(0, 0, 0)])
    solids.each do |t|
      assert_equal :solid, t[:path]
      # DragonRuby draws :solid triangles only with source coordinates
      assert_equal [0, 0, 1, 0, 0, 1], t.values_at(:source_x, :source_y, :source_x2, :source_y2, :source_x3, :source_y3)
    end
  end

  # Mesh uvs are 0..1, DragonRuby's source coordinates are pixels.
  def test_texture_size_scales_uvs_to_pixels
    cam = D3D::Camera.new(position: D3D::Vec3.new(0, 0, 5))
    square = cube(0, 0, 0)
    square.texture = "sprites/blocks/stone.png"
    square.texture_size = 64
    tris = D3D::Renderer.render(cam, [square])
    us = tris.flat_map { |t| t.values_at(:source_x, :source_x2, :source_x3) }.uniq.sort
    assert_equal [0, 64], us

    wide = cube(0, 0, 0)
    wide.texture = "sprites/blocks/stone.png"
    wide.texture_size = [32, 16]
    tris = D3D::Renderer.render(cam, [wide])
    assert_equal [0, 32], tris.flat_map { |t| t.values_at(:source_x, :source_x2, :source_x3) }.uniq.sort
    assert_equal [0, 16], tris.flat_map { |t| t.values_at(:source_y, :source_y2, :source_y3) }.uniq.sort
  end

  # Without texture_size and without DragonRuby to ask, uvs stay as they are.
  def test_unknown_texture_size_keeps_uvs
    cam = D3D::Camera.new(position: D3D::Vec3.new(0, 0, 5))
    textured = cube(0, 0, 0)
    textured.texture = "sprites/blocks/stone.png"
    tris = D3D::Renderer.render(cam, [textured])
    assert_equal [0, 1], tris.flat_map { |t| t.values_at(:source_x, :source_x2, :source_x3) }.uniq.sort
  end

  def test_light_shades_faces_by_their_normal
    cam = D3D::Camera.new(position: D3D::Vec3.new(3, 3, 3))
    cam.look_at(D3D::Vec3.new(0, 0, 0))
    color = { r: 200, g: 200, b: 200, a: 255 }
    tris = D3D::Renderer.render(cam, [cube(0, 0, 0, color: color)], light: { direction: [0, 1, 0], ambient: 0.4 })
    reds = tris.map { |t| t[:r].round(3) }.uniq.sort
    assert_equal [80.0, 200.0], reds # sides get only ambient, the top full light
  end

  # Top face tilted by the model's x rotation; a uniform scale must not
  # change the shading (the fast path without a per-face sqrt).
  def test_light_on_a_rotated_uniformly_scaled_model
    cam = D3D::Camera.new(position: D3D::Vec3.new(0, 6, 6))
    cam.look_at(D3D::Vec3.new(0, 0, 0))
    color = { r: 200, g: 200, b: 200, a: 255 }
    model = cube(0, 0, 0, color: color)
    model.set_scale(2)
    model.set_rotation(0.3, 0, 0)
    tris = D3D::Renderer.render(cam, [model], light: { direction: [0, 1, 0], ambient: 0.4 })
    reds = tris.map { |t| t[:r].round(6) }
    assert_includes reds, (200 * (0.4 + 0.6 * Math.cos(0.3))).round(6)
  end

  # Non-uniform scale: world normals need the inverse transpose and a
  # per-face length. Rotating about y keeps the top face up and the sides
  # horizontal.
  def test_light_on_a_non_uniformly_scaled_model
    cam = D3D::Camera.new(position: D3D::Vec3.new(4, 5, 6))
    cam.look_at(D3D::Vec3.new(0, 0, 0))
    color = { r: 200, g: 200, b: 200, a: 255 }
    model = cube(0, 0, 0, color: color)
    model.set_scale(1, 3, 0.5)
    model.set_rotation(0, 0.7, 0)
    tris = D3D::Renderer.render(cam, [model], light: { direction: [0, 1, 0], ambient: 0.4 })
    assert_equal [80.0, 200.0], tris.map { |t| t[:r].round(6) }.uniq.sort
  end

  def test_fog_blends_towards_its_colour_and_skips_far_triangles
    fog = { near: 2.0, far: 6.0, color: [0, 0, 255] }
    cam = D3D::Camera.new(position: D3D::Vec3.new(0, 0, 0))
    near_tris = D3D::Renderer.render(cam, [cube(0, 0, -3)], fog: fog)
    refute_empty near_tris
    near_tris.each do |t|
      assert t[:r] < 80
      assert t[:b] > 80
    end
    assert_empty D3D::Renderer.render(cam, [cube(0, 0, -20)], fog: fog)
  end

  def test_voxel_faces_carry_their_normal
    world = voxel_floor
    world.mesh_data[:faces].each { |f| assert_equal 1, f[:n].map(&:abs).sum }
  end

  def test_voxel_face_under_the_camera_is_clipped_not_dropped
    world = D3D::VoxelWorld.new
    world.add_block(2, 0, 2, { r: 200, g: 200, b: 200, a: 255 })
    world.build_mesh
    # standing on the block looking ahead: its top face reaches behind the
    # camera, yet it is all there is to cover the bottom of the screen
    cam = D3D::Camera.new(position: D3D::Vec3.new(2.5, 1.6, 2.5))
    cam.look_at(D3D::Vec3.new(2.5, 0.0, -0.5))
    tris = D3D::Renderer.render_voxel_world(cam, world)
    assert covered?(tris, 640, 5)
  end

  def test_voxel_light_and_fog
    world = voxel_floor
    cam = D3D::Camera.new(position: D3D::Vec3.new(2.0, 3.0, 8.0))
    cam.look_at(D3D::Vec3.new(2.0, 0.0, 2.0))
    plain = D3D::Renderer.render_voxel_world(cam, world)
    lit = D3D::Renderer.render_voxel_world(cam, world, light: { direction: [0, 0, 1], ambient: 0.5 })
    assert_equal plain.size, lit.size
    assert lit.any? { |t| t[:r] < 200 } # top faces are only lit by the ambient part
    assert_empty D3D::Renderer.render_voxel_world(cam, world, fog: { near: 0.5, far: 1.0, color: [0, 0, 0] })
  end

  private

  def covered?(tris, px, py)
    tris.any? do |t|
      d1 = (px - t[:x2]) * (t[:y] - t[:y2]) - (t[:x] - t[:x2]) * (py - t[:y2])
      d2 = (px - t[:x3]) * (t[:y2] - t[:y3]) - (t[:x2] - t[:x3]) * (py - t[:y3])
      d3 = (px - t[:x]) * (t[:y3] - t[:y]) - (t[:x3] - t[:x]) * (py - t[:y])
      !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0))
    end
  end

  # View distance of a triangle's centroid, recovered from its sort depth.
  def depth_of(tri, cam)
    near = cam.near
    far = cam.far
    z_ndc_w = tri[:z_depth] # clip z = (far + near) / (far - near) * d - 2 * far * near / (far - near)
    (z_ndc_w + 2.0 * far * near / (far - near)) * (far - near) / (far + near)
  end
end
