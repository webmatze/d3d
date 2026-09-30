Bench::Registry.register(
  "voxel/build_mesh",
  setup: -> { Scenes.voxel_world }
) { |world| world.rebuild! }

Bench::Registry.register(
  "voxel/raycast",
  setup: lambda do
    world = Scenes.voxel_world
    origin = D3D::Vec3.new(0.5, 20.0, 0.5)
    dir = D3D::Vec3.new(0.3, -1.0, 0.2).normalize
    [world, origin, dir]
  end
) { |fx| fx[0].raycast(fx[1], fx[2], 64.0) }

Bench::Registry.register(
  "voxel/aabb_query",
  setup: lambda do
    world = Scenes.voxel_world
    min = D3D::Vec3.new(-0.5, 5.0, -0.5)
    max = D3D::Vec3.new(0.5, 7.0, 0.5)
    [world, min, max]
  end
) { |fx| fx[0].aabb_intersects?(fx[1], fx[2]) }
