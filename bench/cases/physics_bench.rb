Bench::Registry.register(
  "physics/ray_model",
  setup: lambda do
    model = D3D::Model.new(mesh: D3D::Mesh.sphere(radius: 1.0, segments: 16, rings: 16))
    [D3D::Vec3.new(0.0, 0.0, 5.0), D3D::Vec3.new(0.0, 0.0, -1.0), model]
  end
) { |fx| D3D::Collisions.ray_model(fx[0], fx[1], fx[2]) }

Bench::Registry.register(
  "physics/sphere_model",
  setup: lambda do
    model = D3D::Model.new(mesh: D3D::Mesh.sphere(radius: 1.0, segments: 16, rings: 16))
    [D3D::Vec3.new(0.0, 0.0, 2.5), model]
  end
) { |fx| D3D::Collisions.sphere_model(fx[0], 1.2, fx[1]) }

Bench::Registry.register(
  "physics/voxel_body_move",
  setup: lambda do
    [Scenes.voxel_world, D3D::VoxelBody.new(0.5, 20.0, 0.5)]
  end
) do |fx|
  world, body = fx
  # Reset state each iteration so every measured op does the same work.
  body.position.x = 0.5
  body.position.y = 4.0
  body.position.z = 0.5
  body.velocity.x = 2.0
  body.velocity.y = 0.0
  body.velocity.z = 1.0
  body.move(world, 1.0 / 60.0)
end
