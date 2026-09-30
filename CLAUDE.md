# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

D3D is a lightweight, pure Ruby 3D rendering engine built for DragonRuby GTK. It's a software-rendered 3D graphics library (no GPU shaders) that runs entirely in Ruby within the DragonRuby game framework.

## Build and Run Commands

```bash
# Run the application (requires DragonRuby GTK installed)
dragonruby .
bin/run      # same, with the Smaug.toml DragonRuby and shaders=true kept in game metadata

# The project uses Smaug (DragonRuby's build system)
# Configuration is in Smaug.toml

# Unit tests for pure-Ruby engine parts (run with system Ruby, no DragonRuby needed)
for f in tests/*.rb; do ruby "$f"; done

# Judge a performance change against a revision: tests + golden output + A/B timing
ruby bench/evaluate.rb --base HEAD            # add --mruby for DragonRuby timing + demo smoke test
ruby bench/profile.rb render/spheres          # exact allocs / calls / executed lines per op
ruby bench/smoke.rb                           # all demos headless in DragonRuby + screenshots
```

See `bench/README.md` and `bench/OPTIMIZATION_LOG.md` for performance work.
Never judge speed against `bench/baseline.json` (it drifts with machine state); use `bench/compare.rb` / `bench/evaluate.rb`.
Engine output is guarded by `bench/golden.json`: a change that alters output
needs `ruby bench/golden.rb --update` and a reason in the commit.

On startup an in-game menu lists all registered demos (arrow keys/number keys + Enter to start, ESC with a free mouse returns to the menu). Demos live in `app/examples/`.

## Architecture

The engine follows a modular component-based architecture:

```
D3D Module (app/d3d/d3d.rb - entry point)
├── Math Foundation
│   ├── Vec3 (vec3.rb) - 3D vector operations
│   └── Mat4 (mat4.rb) - 4x4 matrix transforms, perspective/orthographic projections
├── Scene Objects
│   ├── Mesh (mesh.rb) - geometry storage + primitive generators (cube, plane, sphere)
│   ├── Model (model.rb) - transformable 3D objects with dirty flag optimization
│   └── Camera (camera.rb) - view/projection matrices, first-person controls
├── Rendering Pipeline (renderer.rb)
│   └── backface culling → MVP transforms → near-plane clipping → frustum culling →
│       optional light/fog → depth sorting → rasterization
├── Physics
│   ├── Collisions (collisions.rb) - ray-triangle, ray-model, sphere-model intersection
│   ├── VoxelWorld (voxel_world.rb) - spatial hash storage, greedy mesh generation,
│   │   DDA raycast, AABB query (aabb_intersects?), face_corners helper
│   └── VoxelBody (voxel_body.rb) - AABB character physics: gravity, axis-by-axis
│       collision snapping, optional ledge guard (move(world, dt, prevent_falling:))
├── Content Loading
│   └── ObjLoader (obj_loader.rb) - Wavefront OBJ parser
└── Cell-Grid Scenes (6DOF, independent of Camera/Renderer/Vec3; arrays only)
    ├── V (v.rb) - array vector helpers, D3D.clamp, Lcg
    ├── Pose (pose.rb) - position + right/up/fwd basis, yaw!/pitch!/roll!
    ├── CellGrid (cell_grid.rb) - cube cells, wall faces, collide_sphere, los?,
    │   seal/unseal blockers, solidify (runtime cave-ins, local face rebuild,
    │   version counter), portal flood-fill visible_cells(renderer)
    ├── SceneRenderer (scene_renderer.rb) - clipping, subdivision, fog/headlight/
    │   point lights, FlatMesh + glow drawing, painter's sort, flush(outputs)
    ├── FlatMesh (flat_mesh.rb) - flat shaded mesh builder (box, bipyramid)
    └── GridMap (grid_map.rb) - wireframe automap of explored cells
```

## Key Implementation Details

**Rendering Pipeline** (renderer.rb - most complex file):
1. Backface culling before any transform: models test the camera (moved into model space via the inverse model matrix) against cached `Mesh#face_normals`; voxel faces carry their normal in `:n`
2. MVP transform (inlined for performance, avoids Vec3 allocation)
3. Triangles crossing the near plane (w < camera.near) are clipped in clip space (`emit_clipped`, rare slow path) instead of dropped
4. Frustum culling with margin-based off-screen rejection
5. Optional `light:` (flat Lambert by face normal) and `fog:` (blend towards a colour, skip beyond far)
6. Perspective divide and screen conversion
7. Depth sorting (painter's algorithm, back-to-front) through `DepthSort` (depth_sort.rb), which picks the fastest sort per VM
8. Supports both textured and solid color triangles

**Voxel World** (voxel_world.rb):
- Spatial hash storage with packed Integer keys (`block_key`: 20 bits per axis, coordinates -524288..524287)
- Greedy mesh generation: only exposes faces adjacent to empty space
- Dirty flag triggers `rebuild!()` to regenerate mesh

**Performance Optimizations**:
- Inline matrix computations to avoid object allocation
- Dirty flag on Model for lazy matrix recalculation
- Pre-computed constants (HALF_WIDTH, HALF_HEIGHT)
- Model-level culling before triangle processing

## Demo System

- `app/main.rb` only requires the engine, the registry and the demo files, then delegates `tick` to `Demos.tick(args)`
- `app/demo_registry.rb` holds the `Demos` module: registry, in-game menu, and demo lifecycle (fresh instance + `setup(args)` on every start)
- Each demo in `app/examples/` is a class with `self.title`, optional `self.description`, `setup(args)` and `tick(args)`, and calls `Demos.register(MyDemo)` at the bottom of its file
- To add a demo: create the class file in `app/examples/` and add a `require` in `app/main.rb`

## Code Conventions

- All 3D engine code is in `app/d3d/` directory
- Demo/application code is in `app/examples/` (one class per file); `app/main.rb` stays minimal
- Ruby style: methods use snake_case, classes use PascalCase
- Collision functions return hit info hashes with `:point`, `:normal`, `:distance`, `:model` keys
- `app/d3d/d3d.rb` requires files relative to `D3D_ROOT` (default `app/d3d`) so games can vendor the engine elsewhere (e.g. `lib/d3d`). New engine files must be added to its require list.
- Engine code must run on both CRuby (tests/bench) and DragonRuby's mruby:
  - Integer `/` returns a Float in DragonRuby; use `(a / b).to_i` for index math.
  - Use `extend self` instead of a bare `module_function`, which mruby doesn't support.
  - Check constants with `Object.const_defined?`, not `defined?`.
  - The project pins DragonRuby Pro 7.21 (Smaug.toml). Draw solid colours as sprites with `path: :solid`;
    `primitive_marker: :solid` and `outputs.solids` are deprecated there (`bench/smoke.rb` reports the warning).
- `D3D::Native` loads the optional C extension of D3D Pro (sold separately, not in this repo). The engine must
  stay complete without it. Code with a native counterpart must keep its output unless the Pro side changes too:
  the face loops of `Renderer#render_model_optimized` and `render_voxel_world`, `SceneRenderer#draw_face` +
  `light_at`, `CellGrid#visible_cells`, `DepthSort`, and `Mesh#native_data`.
- Shaders (Pro, early access): `.hlsl` fragment shaders in `shaders/`, full-screen post-processing only via
  `outputs.shader` / `outputs[:rt].shader`, and they must be `require`d first. `shaders=true` in
  `metadata/game_metadata.txt` (Smaug's run/build rewrites the file without it; `bin/run` restores it)
  switches the renderer to SDL_GPU, which can't run headless, so
  `bench/dragonruby.rb` rewrites it to `shaders=false`; guard shader code with `PostFxDemo.shaders_enabled?`-style checks.
  Switching shaders or turning one off at runtime is unreliable in 7.21 (stale shaders, a crash in `render_shader`):
  keep one shader path and select variants with a uniform (see `shaders/postfx/postfx.frag.hlsl`).
