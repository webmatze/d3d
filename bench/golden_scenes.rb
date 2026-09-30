# Fixed scenes whose engine output golden.rb fingerprints. Each entry returns
# plain data (primitive hashes, arrays, numbers); golden.rb canonicalizes it.
# ordered: false means the output is compared as a multiset (e.g. triangle
# lists, whose order among equal depths may legitimately change).
# Assumes the engine and bench/scenes.rb are loaded.
module GoldenScenes
  module_function

  def all
    {
      "render/cubes" => [false, -> { D3D::Renderer.render(Scenes.camera_overview, Scenes.cube_grid(8)) }],
      "render/cubes_textured" => [false, -> { D3D::Renderer.render(Scenes.camera_overview, Scenes.cube_grid(8, textured: true)) }],
      "render/spheres" => [false, -> { D3D::Renderer.render(Scenes.camera_overview, Scenes.sphere_field(16)) }],
      "render/spheres_lit_fog" => [false, -> { D3D::Renderer.render(Scenes.camera_overview, Scenes.sphere_field(16), light: light, fog: fog) }],
      "render/voxel" => [false, -> { D3D::Renderer.render_voxel_world(Scenes.camera_voxel, Scenes.voxel_world) }],
      "render/voxel_lit_fog" => [false, -> { D3D::Renderer.render_voxel_world(Scenes.camera_voxel, Scenes.voxel_world, light: light, fog: fog) }],
      "render/near_clip_ground" => [false, -> { near_clip_ground }],
      "render/near_clip_voxel" => [false, -> { near_clip_voxel }],
      "render/mirrored_textured" => [false, -> { mirrored_textured }],
      "render/project_point" => [true, -> { project_points }],
      "voxel/mesh" => [true, -> { voxel_mesh }],
      "voxel/raycast" => [true, -> { voxel_raycasts }],
      "voxel/aabb" => [true, -> { voxel_aabbs }],
      "physics/voxel_body" => [true, -> { voxel_body_steps }],
      "physics/collisions" => [true, -> { collisions }],
      "cell_grid/render" => [false, -> { cell_grid_render }],
      "cell_grid/visible_cells" => [false, -> { cell_grid_visible }],
      "cell_grid/collide_sphere" => [true, -> { cell_grid_collide }],
      "grid_map/lines" => [false, -> { grid_map_lines }]
    }
  end

  def light
    { direction: [0.4, 1.0, 0.25], ambient: 0.4 }
  end

  def fog
    { near: 8.0, far: 30.0, color: [20, 30, 40] }
  end

  # Basic demo start view: ground corners behind the camera plus a cube.
  def near_clip_ground
    ground = D3D::Model.new(mesh: D3D::Mesh.plane(width: 20, depth: 20), color: { r: 80, g: 120, b: 80, a: 255 })
    ground.position.y = -1.5
    cube = D3D::Model.new(mesh: D3D::Mesh.cube, color: { r: 100, g: 150, b: 255, a: 255 })
    cube.set_scale(2)
    cam = D3D::Camera.new(position: D3D::Vec3.new(0, 2, 8), fov: 70)
    D3D::Renderer.render(cam, [ground, cube], light: light)
  end

  def near_clip_voxel
    world = D3D::VoxelWorld.new
    world.add_block(2, 0, 2, { r: 200, g: 200, b: 200, a: 255 }, texture: "sprites/blocks/stone.png")
    world.add_block(3, 0, 2, { r: 100, g: 200, b: 100, a: 255 })
    world.build_mesh
    cam = D3D::Camera.new(position: D3D::Vec3.new(2.5, 1.6, 2.5))
    cam.look_at(D3D::Vec3.new(2.5, 0.0, -0.5))
    D3D::Renderer.render_voxel_world(cam, world)
  end

  def mirrored_textured
    model = D3D::Model.new(mesh: D3D::Mesh.cube, texture: "sprites/block.png", position: D3D::Vec3.new(1, 0, -3))
    model.set_rotation(0.3, 0.7, 0.1)
    model.set_scale(-1, 2, 1)
    D3D::Renderer.render(D3D::Camera.new(position: D3D::Vec3.new(0, 1, 3)), [model])
  end

  def project_points
    cam = Scenes.camera_overview
    [[0, 0, 0], [3, 1, -2], [-4, 2, 5], [12, 10, 30]].map { |p| D3D::Renderer.project_point(cam, *p) }
  end

  def voxel_mesh
    data = Scenes.voxel_world.build_mesh
    [data[:vertices], data[:faces]]
  end

  def voxel_raycasts
    world = Scenes.voxel_world
    origin = D3D::Vec3.new(0.5, 20.0, 0.5)
    (0...12).map do |i|
      a = i * 0.5
      dir = D3D::Vec3.new(Math.cos(a) * 0.6, -1.0, Math.sin(a) * 0.6 + 0.3).normalize
      world.raycast(origin, dir, 64.0)
    end
  end

  def voxel_aabbs
    world = Scenes.voxel_world
    (0...16).map do |i|
      min = D3D::Vec3.new(i - 0.5, 2.0 + (i % 4), i * 0.7 - 0.5)
      max = D3D::Vec3.new(i + 0.5, 4.0 + (i % 4), i * 0.7 + 0.5)
      world.aabb_intersects?(min, max)
    end
  end

  def voxel_body_steps
    world = Scenes.voxel_world
    body = D3D::VoxelBody.new(3.5, 12.0, 3.5)
    (0...90).map do |i|
      body.velocity.x = Math.cos(i * 0.1) * 3.0
      body.velocity.z = Math.sin(i * 0.1) * 3.0
      body.velocity.y = 8.0 if i % 30 == 0 && body.on_ground
      body.move(world, 1.0 / 60.0, prevent_falling: i > 60)
      [body.position.x, body.position.y, body.position.z, body.on_ground]
    end
  end

  def collisions
    sphere = D3D::Model.new(mesh: D3D::Mesh.sphere(radius: 1.0, segments: 16, rings: 16))
    cube = D3D::Model.new(mesh: D3D::Mesh.cube, position: D3D::Vec3.new(3, 0, 0))
    cube.set_rotation(0.2, 0.4, 0.0)
    models = [sphere, cube]
    rays = (0...8).map do |i|
      hit = D3D::Collisions.ray_models(D3D::Vec3.new(i * 0.5 - 0.5, 0.1, 5.0), D3D::Vec3.new(0.0, 0.0, -1.0), models)
      hit && [hit.reject { |k, _| k == :model }, models.index(hit[:model])]
    end
    spheres = (0...6).map do |i|
      hit = D3D::Collisions.sphere_model(D3D::Vec3.new(0.0, 0.0, 1.5 + i * 0.1), 0.8, sphere)
      hit && hit.reject { |k, _| k == :model }
    end
    [rays, spheres]
  end

  def cell_grid_render
    grid = Scenes.cell_grid
    renderer = Scenes.scene_renderer
    pose = Scenes.cell_grid_pose
    lights = [{ pos: [60.0, 45.0, 160.0], radius: 50.0, color: [1.0, 0.4, 0.2], intensity: 0.8 }]
    renderer.begin_frame(pose, lights: lights)
    renderer.draw_grid(grid)
    mesh = D3D::FlatMesh.new.box(0, 0, 0, 3, 2, 4, [200, 180, 60])
    renderer.draw_mesh(mesh, [58.0, 43.0, 150.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0], 1.5, [1.0, 0.9, 0.8])
    renderer.draw_glow([54.0, 46.0, 140.0], 4.0, 255, 200, 120)
    renderer.sorted_primitives
  end

  def cell_grid_visible
    grid = Scenes.cell_grid
    renderer = Scenes.scene_renderer
    renderer.begin_frame(Scenes.cell_grid_pose)
    grid.visible_cells(renderer)
  end

  def cell_grid_collide
    grid = Scenes.cell_grid
    [[21.0, 45.0, 170.0], [55.0, 45.0, 120.0], [31.0, 26.0, 40.0], [70.0, 60.0, 200.0]].map do |p|
      pos = p.dup
      normal = grid.collide_sphere(pos, 2.4)
      [pos, normal]
    end
  end

  def grid_map_lines
    grid = Scenes.cell_grid
    renderer = Scenes.scene_renderer
    pose = Scenes.cell_grid_pose
    renderer.begin_frame(pose)
    map = D3D::GridMap.new(grid)
    map.explore(grid.visible_cells(renderer), pose.position)
    map.open(pose)
    map.lines(pose)
  end
end
