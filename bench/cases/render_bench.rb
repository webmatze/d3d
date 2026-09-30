Bench::Registry.register(
  "render/cubes_grid_solid",
  setup: -> { [Scenes.camera_overview, Scenes.cube_grid(8, textured: false)] }
) { |fx| D3D::Renderer.render(fx[0], fx[1]) }

Bench::Registry.register(
  "render/cubes_grid_textured",
  setup: -> { [Scenes.camera_overview, Scenes.cube_grid(8, textured: true)] }
) { |fx| D3D::Renderer.render(fx[0], fx[1]) }

Bench::Registry.register(
  "render/spheres",
  setup: -> { [Scenes.camera_overview, Scenes.sphere_field(16)] }
) { |fx| D3D::Renderer.render(fx[0], fx[1]) }

Bench::Registry.register(
  "render/voxel_world",
  setup: -> { [Scenes.camera_voxel, Scenes.voxel_world] }
) { |fx| D3D::Renderer.render_voxel_world(fx[0], fx[1]) }

Bench::Registry.register(
  "render/voxel_world_lit",
  setup: -> { [Scenes.camera_voxel, Scenes.voxel_world] }
) do |fx|
  D3D::Renderer.render_voxel_world(fx[0], fx[1],
                                   light: { direction: [0.4, 1.0, 0.25], ambient: 0.55 },
                                   fog: { near: 20.0, far: 60.0, color: [0, 0, 0] })
end

Bench::Registry.register(
  "render/spheres_lit_fog",
  setup: -> { [Scenes.camera_overview, Scenes.sphere_field(16)] }
) do |fx|
  D3D::Renderer.render(fx[0], fx[1],
                       light: { direction: [0.4, 1.0, 0.25], ambient: 0.4 },
                       fog: { near: 8.0, far: 30.0, color: [20, 30, 40] })
end
