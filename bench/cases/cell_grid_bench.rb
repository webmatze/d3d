Bench::Registry.register(
  "cell_grid/visible_cells",
  setup: lambda do
    renderer = Scenes.scene_renderer
    renderer.begin_frame(Scenes.cell_grid_pose)
    [Scenes.cell_grid, renderer]
  end
) { |fx| fx[0].visible_cells(fx[1]) }

Bench::Registry.register(
  "cell_grid/render",
  setup: -> { [Scenes.cell_grid, Scenes.scene_renderer, Scenes.cell_grid_pose] }
) do |fx|
  fx[1].begin_frame(fx[2])
  fx[1].draw_grid(fx[0])
  fx[1].sorted_primitives
end

Bench::Registry.register(
  "cell_grid/collide_sphere",
  setup: -> { Scenes.cell_grid }
) { |grid| grid.collide_sphere([21.0, 45.0, 170.0], 2.4) }

Bench::Registry.register(
  "cell_grid/shaft_visible_cells",
  setup: lambda do
    renderer = Scenes.scene_renderer
    renderer.begin_frame(Scenes.cell_grid_shaft_pose)
    [Scenes.cell_grid_shaft, renderer]
  end
) { |fx| fx[0].visible_cells(fx[1]) }

Bench::Registry.register(
  "cell_grid/shaft_render",
  setup: -> { [Scenes.cell_grid_shaft, Scenes.scene_renderer, Scenes.cell_grid_shaft_pose] }
) do |fx|
  fx[1].begin_frame(fx[2])
  fx[1].draw_grid(fx[0])
  fx[1].sorted_primitives
end

# One cave-in step on the tall grid: solidify a cell, then carve it open again.
Bench::Registry.register(
  "cell_grid/solidify_and_reopen",
  setup: -> { Scenes.cell_grid_shaft }
) do |grid|
  grid.solidify(23, 20, 23)
  grid.carve(23, 23, 20, 20, 23, 23, :rock, [0.75, 0.7, 0.65])
  grid.rebuild_faces_near(grid.idx(23, 20, 23))
end

Bench::Registry.register(
  "cell_grid/full_face_rebuild_tall",
  setup: -> { Scenes.cell_grid_shaft }
) { |grid| grid.rebuild_faces }
