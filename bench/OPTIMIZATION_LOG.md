# Optimization Log

Every optimization attempt, kept or rejected, so nobody tries the same idea
twice. Newest first. Numbers come from `ruby bench/evaluate.rb` (CRuby A/B,
interleaved pairs) unless marked mruby.

Entry format:

```
### YYYY-MM-DD <short title> — KEEP|REJECT
- Hypothesis: what should get faster and why (profile evidence)
- Change: files / approach
- Result: case deltas (±noise), score, allocs/op, mruby if measured
- Notes: surprises, follow-ups
```

## Backlog (untested ideas, with profile evidence where known)

- SceneRenderer#draw_mesh and draw_glow are still Ruby (models, voxels and
  cell grids are native since 2026-09-30).
- Voxel mesh: 4 shared vertices per quad instead of 6 in build_mesh itself
  (the renderer now dedups 5364 corners to 896 unique vertices per mesh, so
  the render side no longer needs it; the gain would be in build_mesh time
  and allocs).
- Renderer: the output Hash per triangle now dominates allocs in every
  render case (894 of 1165/op in voxel_world_lit, 3708 of 6718 in spheres).
  Fewer keys, or reused hashes/arrays if the draw side allows it.
- Renderer: remaining `Float#-@` per emitted triangle is the negated sort
  key (895/op in voxel_world_lit); a negation-free sort key would drop it.
- Renderer#render_model_optimized: after the lazy projection cache,
  render/cubes_grid_solid/textured read ~+2% in CRuby (above measured noise
  but rated within_noise; mruby -1.1%/-1.4%). Small meshes pay the stamp
  bookkeeping; check whether a fast path for tiny meshes helps.
- Mat4: other methods (transform_point, inverse, perspective/orthographic
  builders) may still use `[]`/`times` loops or Vec3 temporaries; look_at is
  now scalar (math/camera_view_matrix -61% mruby).
- physics/sphere_model read +3.1% (±1.3%, rated within_noise) and
  physics/ray_model +2.4% (±3.1%) in the round-4 mruby check with untouched
  code paths; re-measure with more pairs.
- Renderer: whole-model culling against all frustum planes via the bounding
  sphere (today only "far behind the camera").
- VoxelWorld: chunks with per-chunk culling.
- cell_grid/collide_sphere read +2.6% (±0.7%) in mruby after the round-2
  visible_cells change and +3.6% (±2.7%, within noise) in the round-3 mruby
  check, although its code path was untouched both times; re-measure with
  more pairs to rule out a real regression (layout / GC side effect?).
- VoxelWorld#build_mesh: shared per-direction UV arrays cut allocs
  10731->8943 (-16.7%) but only -2.4% time (rejected alone); combine with
  the "4 shared vertices per quad" idea so the whole build shrinks enough
  to clear the threshold.
- SceneRenderer: after visible_cells (-28.8%) cell_grid/render is ~5.5 ms
  and not dominated by `Float#**`, `light_at` Arrays or the sort pairs
  (removing all three was within noise). Profile it again for the real
  cost (clipping/subdivision, glow drawing, flush).
- Collisions: add a model-level bounding-sphere early-out in `ray_model` /
  `sphere_model` before transforming vertices, and cache the world-space
  vertex arrays per model while its matrix is not dirty.

## Attempts

### 2026-09-30 Native textured models (render_model with uvs) — KEEP
- Hypothesis: textured models still ran the Ruby loop (render_model only
  took untextured ones); the same C loop only needs per-face uv indices.
- Change: pack_mesh takes optional per-face uv index arrays (nil -> -1);
  render_model gets texture and uvs, checks the indices against the current
  uvs.length like the Ruby code, reads the [u, v] values straight from the
  Ruby Arrays (Integer uvs stay Integer) and passes texture and uvs to
  emit_clipped for near-plane faces. The renderer uses it for all models.
  native_check: textured mirrored cube, textured sphere with light and fog,
  missing / out of range / nil uv indices, texture with empty uvs, textured
  ground clipped at the near plane (8 textured emit_clipped calls); all 17
  scenes identical.
- Result: first `evaluate.rb --base HEAD --mruby --native` run rejected on
  CRuby voxel/build_mesh "slower" (code untouched); `compare.rb --filter
  voxel/build_mesh --pairs 6` gave +0.1% ±3.5% within noise, same allocs,
  and the full rerun with `--pairs 5` decided keep: CRuby 0.996, nothing
  slower, mruby render/cubes_grid_textured -77.2% ±0.3%. Isolated (C sort on
  both sides, mruby): cubes_grid_textured 1.62 -> 0.52 ms, textured sphere
  field lit 10.99 -> 1.79 ms.

### 2026-09-30 Native CellGrid#visible_cells — KEEP
- Hypothesis: with native faces, the Ruby portal flood fill was ~75% of
  cell_grid/render (2.85 of 3.72 ms in mruby); it is pure integer/float
  work on flat arrays, ideal for C.
- Change: `app/d3d/ext/d3d_ext.c` visibility_state (scratch arrays per grid:
  visited, grid point cache, queue; cached as @native_visibility) and
  visible_cells, same queue order, distance and portal tests as the Ruby
  code; the cells Array is passed on every call (cells change at runtime).
  CellGrid#visible_cells uses it when D3D::Native is enabled. native_check:
  visible cell lists compared directly (mine, shaft, camera outside the
  grid, camera in rock); all 15 scenes identical.
- Result: `evaluate.rb --base HEAD --mruby --native`: keep, CRuby 1.000,
  nothing slower; mruby cell_grid/visible_cells -99.1%. Isolated (C sort on
  both sides, mruby): visible_cells 2.82 -> 0.02 ms; with the native faces
  the whole frame: cell_grid/render 7.38 -> 0.88 ms, shaft_render 7.12 ->
  0.56 ms, 20x20 cavern with 2 lights 8.22 -> 0.90 ms.

### 2026-09-30 Native cell grid faces (D3D::Ext.draw_cell_faces) — KEEP
- Hypothesis: the cell-grid cavern was the slowest path in the Performance
  Benchmark (engine 11.2 ms for ~1900 triangles, all Ruby). Profile of
  cell_grid/render: 558 draw_face calls with 526 light_at (3085 Float#**,
  3063 sqrt, 1239 D3D.clamp) plus pair Arrays and Hashes, and the portal
  flood fill (visible_cells).
- Change: `app/d3d/ext/d3d_ext.c` draw_cell_faces mirrors draw_face and
  light_at for all faces of the visible cells, in order (pow(x, 2) for
  Ruby's **2, clamp bounds as Integer 0/255, [0, 0, 0] Integers beyond the
  fog); near-plane sub faces go to emit_textured via funcall. Face lists are
  packed in Ruby (SceneRenderer#native_cell_faces), cached by list identity
  because rebuild_faces_near replaces lists without a version bump.
  visible_cells stays Ruby. native_check: cell grid with point lights,
  ambient boost, near clipping (11 emit_textured calls) and a missing
  material; all 14 scenes identical. Fixed on the way: `@triangle_count +=
  Ext...` read the counter before the call and lost emit_textured's count.
- Result: `evaluate.rb --base HEAD --mruby --native`: keep, CRuby 1.001,
  nothing slower. Isolated (C sort on both sides, mruby): cell_grid/render
  7.31 -> 3.72 ms, shaft_render 7.01 -> 4.59 ms, 20x20 cavern with 2
  lights 8.02 -> 3.29 ms.
- Notes: visible_cells (Ruby) is now ~75% of what remains (2.85 ms of
  3.72 in cell_grid/render); next native candidate.

### 2026-09-30 Native voxel loop (D3D::Ext.render_voxels) — KEEP
- Hypothesis: after the native model loop, the voxel terrain was the
  slowest path per triangle in the Performance Benchmark (engine 11.1 ms
  for 3606 triangles); the same approach should cut its face loop.
- Change: `app/d3d/ext/d3d_ext.c` render_voxels mirrors the face loop of
  render_voxel_world (world-space cull, clip transform once per frame,
  light, fog, perspective divide, frustum cull, textured and solid output,
  near-plane faces via emit_clipped in loop order). Geometry reuses
  pack_mesh on the voxel render cache (handle in cache[30]); colours,
  paths and source coordinates are passed as the cache's Ruby arrays so
  they keep their exact values. native_check: textured voxel terrain with
  light and fog, voxel near clip (textured + solid); all 13 identical.
- Result: `evaluate.rb --base HEAD --mruby --native`: keep, CRuby 0.999,
  nothing slower (base without the extension). Isolated (C sort on both
  sides, mruby, median of 60): voxel_world 2.07 -> 0.42 ms, voxel_world
  lit+fog 2.44 -> 0.45 ms, textured 32x32 terrain lit (3258 tris) 8.72 ->
  1.65 ms.

### 2026-09-30 Native model loop (D3D::Ext.render_model) — KEEP
- Hypothesis: the Ruby model loop is at its limit (flat vertex arrays:
  no gain); its cost is interpreting the per-face arithmetic. In C the
  whole untextured loop (cull, transform with vertex cache, light, fog,
  frustum cull, output Hashes) should drop to a fraction.
- Change: `app/d3d/ext/d3d_ext.c`: pack_mesh (copy of vertices and
  face_cull_data, handle cached as Mesh#native_data, reset with
  invalidate_normals!) and render_model, which mirrors the Ruby loop
  operation by operation in double (bin/build-ext adds -ffp-contract=off);
  faces crossing the near plane go to Renderer.emit_clipped via funcall in
  loop order; unlit/unfogged colours keep their Ruby value (Integer stays
  Integer). Textured models stay on the Ruby path. native_check: new scenes
  (near clip, non-uniform/mirrored scale with light and fog, fog on Integer
  colours) and eql? comparison; all 11 identical.
- Result: `evaluate.rb --base HEAD --mruby --native` (full suite; base
  without the extension, so voxel/cell gains are the C sort): keep, CRuby
  1.001, mruby 0.703, render/spheres -89.9%, spheres_lit_fog -90.0%,
  cubes_grid_solid -75.2%. Isolated (C sort on both sides, mruby, median of
  60): spheres 8.90 -> 1.88 ms, spheres_lit_fog 10.94 -> 1.84 ms,
  cubes_grid_solid 1.49 -> 0.51 ms, Blub lit (8240 tris) 22.35 -> 5.06 ms.
- Notes: C now spends ~0.2-0.6 us per triangle, mostly building the output
  Hashes; DragonRuby's own drawing (~2 us per triangle) is the largest cost.
  Candidates: textured models in C, reusing output Hashes.

### 2026-09-30 Renderer: flat vertex coordinate arrays for models — REJECT
- Hypothesis: render_model_optimized reads every transformed vertex through
  three Vec3 method calls (v.x / v.y / v.z); mruby method dispatch is
  costly, render_voxel_world already reads flat arrays.
- Change: Mesh#vertex_coords ([xs, ys, zs], cached, reset with
  invalidate_normals!), renderer reads them; `faces[fi]` only in the
  texture branch.
- Result: `evaluate.rb --base HEAD --filter render --mruby`: CRuby 0.996,
  mruby 0.994, no case measurably faster. Reverted.
- Notes: the Ruby model loop seems to be at its limit; the remaining cost is
  interpretation of the per-face arithmetic itself (7680 cull tests and
  ~3700 emitted triangles per render/spheres op). Next: the native loop.

### 2026-09-30 mruby GC: incremental instead of generational — KEEP (game setting)
- Hypothesis: the Performance Benchmark suggested that big loaded meshes
  slow everything down. Headless probes (render/spheres lit, 400 calls):
  with ogre + blub held, the median stayed the same but ~12% of calls got a
  ~17 ms spike (a full GC over ~0.5M mesh objects, about every 8th call);
  a full GC.start took 16 ms with the meshes vs 1 ms without.
- Change: not an engine change. `app/main.rb` sets
  `GC.generational_mode = false`; README recommends it for games;
  `bench/mruby_runner.rb` fixes the GC mode for both A/B sides.
- Result (headless, mruby): meshes held: generational p50 10.5 / p95 28.5 /
  max 34.3 ms, 46 spikes in 400; incremental p50 10.4 / p95 14.7 / max
  18.3, no spikes. interval_ratio 400/1000 only made spikes rarer and
  longer (max 64.5 ms). Without big meshes incremental was also faster,
  twice in a row: spheres p50 11.3 -> 9.9 ms, voxel_world 2.7 -> 2.3-2.4.
  Real window (Performance Benchmark, C ext on, light on): spikes gone;
  auto benchmark voxel terrain 24 -> 32 per side, cavern 16 -> 20, spheres
  16 -> 16, Blub engine 25.1 -> 21.9 ms (runs from different sessions).
- Notes: `--mruby` numbers from before this change ran with the default
  generational GC; compare only runs made with the same runner.

### 2026-09-30 Renderer: model light in model space, inline shading — KEEP
- Hypothesis: lit models allocate per front face a [r, g, b] Array from
  `shade` and ~2 Floats per world normal component, plus a sqrt
  (render/spheres_lit_fog: 16527 allocs/op, 3500 Arrays at renderer.rb:503,
  ~6500 Floats at 715-717, 3501 Math.sqrt). The Performance Benchmark showed
  lit models at 3-4 us per triangle in DragonRuby.
- Change: `app/d3d/renderer.rb` render_model_optimized: the light direction
  goes into model space once per model ((inv^T n) . L = n . (inv L)); with a
  uniform scale (inv inv^T = c I) the world normal length is sqrt(c) for
  every face, so no per-face sqrt; non-uniform scales keep the per-face
  length. Light and fog inline like render_voxel_world; `shade` removed.
  New bench case render/spheres_lit_fog; renderer tests for a rotated
  uniformly scaled and a non-uniformly scaled lit model.
- Result: `evaluate.rb --base HEAD --filter render --mruby`: CRuby 0.977,
  render/spheres_lit_fog -17.1% ±1.7%; mruby -13.2% ±2.6%, nothing slower,
  smoke pass. Full suite (CRuby): score 0.987, spheres_lit_fog -17.5%
  ±0.3%, nothing slower. Allocs/op 16527 -> 6513. Golden match.
- Notes: the remaining allocations are the output Hashes (3500/op) and
  clip/NDC Floats of the vertex cache.

### 2026-09-29 Optional C extension for DepthSort — KEEP
- Hypothesis: after the mruby sort block, the depth sort is still the
  largest single cost in DragonRuby render calls (9.7 ms of render/spheres);
  a qsort in C over the extracted z_depth keys measured 0.19 ms.
- Change: `app/d3d/ext/d3d_ext.c` (D3D::Ext.sort_by_depth / sort_pairs,
  type checks before allocating, equal depths keep input order),
  `app/d3d/native.rb` (D3D::Native.load / enabled?, returns false wherever
  the extension can't load), DepthSort uses Ext when enabled. `bin/build-ext`
  builds it; compare/evaluate `--native` load it on the head side;
  `bench/native_check.rb` compares C and Ruby output in DragonRuby.
- Result: native_check identical in all 8 scenes. `evaluate.rb --base HEAD
  --mruby --native` (full suite, base = Ruby sort block): CRuby score 0.999;
  mruby score 0.870: render/spheres -50.6% ±0.4%, voxel_world -43.7% ±0.5%,
  voxel_world_lit -39.8% ±0.6%, cubes_grid_solid -32.2% ±0.9%,
  cubes_grid_textured -30.4% ±1.1%, cell_grid/render -21.7% ±0.5%,
  cell_grid/shaft_render -13.8% ±1.3%. Tests, golden, smoke pass.
- Notes: only macOS/Linux builds so far (no Windows, iOS, Android, web).
  Next native candidate: the transform/cull/clip loop (~12 ms of
  render/spheres in mruby).

### 2026-09-29 DepthSort: sort block instead of sort_by on mruby — KEEP
- Hypothesis: in DragonRuby the final back-to-front sort is 31-44% of a
  render call (mruby split: render/spheres 25.7 ms, of which sort_by 11.4 ms,
  output hashes 2.2 ms). mruby's sort_by builds pairs and sorts them with a
  Ruby-level block; a plain sort block measured 9.7 vs 16.1 ms for 3708
  triangles in render order. On CRuby it is the opposite (sort_by is C code,
  0.32 ms; sort block 0.57 ms), so the choice has to depend on the VM.
- Change: new `app/d3d/depth_sort.rb` (DepthSort.triangles / .pairs, picks
  sort block when RUBY_ENGINE is mruby, sort_by otherwise); Renderer and
  SceneRenderer sort through it. CRuby path unchanged. evaluate.rb now also
  counts mruby-only gains with --mruby (keep still needs nothing slower in
  either runtime).
- Result: `evaluate.rb --base HEAD --mruby` (full suite): CRuby score 0.999,
  nothing slower; mruby score 0.924: render/cubes_grid_solid -17.7% ±0.1%,
  cubes_grid_textured -16.8% ±0.6%, spheres -23.8% ±0.6%, voxel_world
  -25.1% ±1.1%, voxel_world_lit -23.0% ±2.1%, cell_grid/render -15.6% ±0.3%,
  cell_grid/shaft_render -9.6% ±1.4%. Tests, golden, smoke pass.
- Notes: an optional C extension qsort measured 0.19 ms for the same sort
  (~50x); that is the next step (DepthSort is its single entry point).

Round 4 mruby check (`bench/compare.rb 3b2b04f --mruby --pairs 2`, all four
kept changes together): math/camera_view_matrix -61.1%, render/spheres
-9.3%, render/voxel_world -24.0%, render/voxel_world_lit -22.9%,
voxel/raycast -53.6%, voxel/aabb_query -74.0%, physics/voxel_body_move
-63.9%; no case slower (largest: physics/sphere_model +3.1% ±1.3%, rated
within_noise, code untouched). Score 0.758.

### 2026-09-25 Camera#calculate_view_matrix / Mat4.look_at: scalar math, one data array literal — KEEP
- Hypothesis: math/camera_view_matrix 3.02 us/op, 10 allocs/op: 8 Vec3
  temporaries (normalize x2, cross x2, +, -, Vec3.up, forward), identity data
  Array then 12 Mat4#[]= calls; every render/* case calls it once per op.
- Change: `app/d3d/mat4.rb`, `app/d3d/camera.rb` (26e2fdf): new
  Mat4.look_at_scalar with the same operation order as Vec3 cross/dot/
  normalize (same zero-length fallback), one 16-element literal; look_at
  delegates to it; calculate_view_matrix computes target as scalars and
  calls it with up = (0.0, 1.0, 0.0). 40002-case comparison vs the old
  implementation (incl. pitch +-90 deg, zero-length forward): 0 differences.
- Result: vs bb93868: math/camera_view_matrix 3026 -> 1146 ns (-62.3%,
  ±1.0%), allocs/op 10 -> 2; all other cases within noise. Score not
  captured (output truncated). mruby (round check): -61.1%.

### 2026-09-25 VoxelWorld#aabb_intersects?/#raycast, VoxelBody: inline packed block keys — KEEP
- Hypothesis: voxel/aabb_query 1.96 us/op (7 Range allocs, 8 has_block? +
  block_key), voxel/raycast 6.84 us/op (26 has_block?, 17 throwaway normal
  Arrays), physics/voxel_body_move 4.31 us/op (11 Ranges, 6 Vec3 from
  aabb_min/aabb_max); mruby gained only -5% from earlier voxel work.
- Change: `app/d3d/voxel_world.rb`, `app/d3d/voxel_body.rb` (bb93868): new
  scalar aabb_intersects_xyz? with while loops and inline packed keys
  (aabb_intersects? delegates); raycast updates the packed key incrementally
  and builds the normal Array only on a hit; VoxelBody#colliding? uses the
  scalar AABB method, ground_below? uses while loops. aabb_min/aabb_max kept.
  20k-case random comparison vs the old VoxelWorld: 0 differences.
- Result: vs 28c92ff, 3 pairs: voxel/raycast -50.5% (±0.6%), allocs 27->2;
  voxel/aabb_query -38.3% (±1.0%), allocs 7->0; physics/voxel_body_move
  -38.3% (±0.3%), allocs 18->0; all others within noise. Score 0.903.
  mruby (round check): -53.6% / -74.0% / -63.9%.

### 2026-09-25 Renderer#render_model_optimized: lazy per-vertex projection cache — KEEP
- Hypothesis: render/spheres 7.71 ms/op; all 4624 vertices transformed per
  op though about half belong only to back faces, and 3708 front faces redo
  the divide/NDC/screen math per corner (11124 projections for 4624
  vertices).
- Change: `app/d3d/renderer.rb` (28c92ff): no up-front vertex loop; a vertex
  is transformed on first use by a front face in the current pass (Integer
  stamp vs per-call @vert_pass). Clip x/y/z/w always cached (the near-clip
  path reads them raw); for !(w < near) also inv_w, NDC x/y/z and screen
  x/y with the old expressions. Golden output bit-identical.
- Result: vs 21a29c6: render/spheres -8.07% (±0.60%), allocs 8540->6718;
  render/cubes_grid_solid +2.07% (±0.91%) and cubes_grid_textured +2.01%
  (±0.40%) rated within_noise, allocs 2588->2524; others within noise.
  Score 0.993. mruby (round check): spheres -9.3%, cubes_grid -1.1%/-1.4%.
- Notes: the small cubes_grid regression in CRuby is above measured noise;
  see backlog.

### 2026-09-25 Renderer#render_voxel_world: cached unique vertices and flat face arrays — KEEP
- Hypothesis: render/voxel_world 2.65 ms/op, voxel_world_lit 3.12 ms/op;
  37552 Float#*/op from transforming 3 corners of each of 894 front faces,
  but the mesh has only 896 unique positions among 5364 corners; per-face
  Hash lookups in the cull, 2682 Float#-@, 894 [r,g,b] Arrays from shade.
- Change: `app/d3d/renderer.rb` (21a29c6): cache keyed on mesh_data identity
  (equal?) with deduplicated vertices (-0.0 kept separate from 0.0), per-face
  unique indices, first corner, normal, r/g/b/a, texture and pre-multiplied
  UV source coords; per frame each unique vertex of a front face is
  transformed at most once (frame stamp); shade's scalar math inlined in the
  same order; neg margin hoisted. Golden output bit-identical.
- Result: vs 3b2b04f, 3 pairs: render/voxel_world -37.3% (±0.11%), allocs
  1577->1162; render/voxel_world_lit -35.6% (±0.25%), allocs 2477->1168;
  voxel/build_mesh -6.0% (±5.16%, untouched); others within noise. Score
  not captured (output truncated). mruby (round check): -24.0% / -22.9%.
- Notes: Float#* in voxel_world_lit 37552->12328/op, Float#-@ 2682->895.

Round 3 mruby check (`bench/compare.rb 7e5e7e5 --mruby --pairs 2`, all three
kept changes together): math/mat4_multiply -84.5%, render/cubes_grid_solid
-30.2%, render/cubes_grid_textured -30.2%, render/spheres -9.9%,
cell_grid/visible_cells -17.4%, cell_grid/render -6.3%; no case slower
(largest: cell_grid/collide_sphere +3.6% ±2.7%, within noise). Score 0.844.

### 2026-09-25 CellGrid#visible_cells: inline scalar to_cam, unrolled neighbour directions — KEEP
- Hypothesis: `cell_grid/visible_cells` 2.92 ms/op (~46% of cell_grid/render
  6.33 ms); all 1713 allocs/op come from `renderer.to_cam` (1240 Arrays +
  468 Floats, 1240 calls). The 6-direction loop runs 5838x/op with di<2/di<4
  branch chains and dir_off lookups.
- Change: `app/d3d/cell_grid.rb`, `app/d3d/scene_renderer.rb` (0c64f65):
  reader for the camera basis on SceneRenderer; visible_cells reads position
  and basis into locals once and computes camera coords inline with
  to_cam's exact arithmetic; the `while di < 6` loop replaced by six
  unrolled neighbour blocks keeping visit and queue order.
- Result: vs 9ce2311, 3 pairs: cell_grid/visible_cells -28.8% (±0.29%),
  allocs 1713->474; cell_grid/render -13.1% (±0.09%), allocs 7782->6543;
  all others within noise (voxel/build_mesh +4.35% ±1.05, voxel/aabb_query
  +3.13% ±2.25, both within noise, code untouched). Score 0.977.
  mruby (round check): -17.4% / -6.3%.

### 2026-09-25 VoxelWorld#build_mesh: shared per-face UV arrays, unrolled vertex emit — REJECT
- Hypothesis: `voxel/build_mesh` 1.49 ms, 10731 allocs/op: 1788 fresh uv
  Arrays identical per direction, 1700 Array#each blocks (FACE_LIST.each
  with 4-way destructuring, verts.each).
- Change: `app/d3d/voxel_world.rb`: frozen per-direction uv triples and 18
  flat vertex offsets in FACE_LIST, index while loop over directions,
  unrolled vertex pushes, shared uv arrays referenced from face hashes.
- Result: vs 9ce2311: voxel/build_mesh -2.40% (±0.40%) but rated
  within_noise, allocs 10731->8943 (-16.7%); everything else within noise.
  Score 1.0002. Reset to 9ce2311.
- Notes: alloc win is real but time gain too small alone; retry bundled with
  "4 shared vertices per quad" (see backlog).

### 2026-09-25 Renderer: per-mesh flat face arrays for back face culling + while loops — KEEP
- Hypothesis: `render/spheres` 8.99 ms/op walks 7680 faces but only 3708 are
  front-facing; the cull does a Hash lookup, Vec3 attr calls and index reads
  per face (standalone replica: 1.49 ms, ~17% of the case). 11126
  `Float#-@`/op from `-margin`, 32 each_with_index blocks/op.
- Change: `app/d3d/mesh.rb`, `app/d3d/renderer.rb` (9ce2311): lazily cached
  Mesh#face_cull_data (vertex indices, first-corner coords, normals as flat
  arrays; cleared with face normals); render_model_optimized culls with a
  while loop over those arrays using identical arithmetic and only touches
  the face hash after the cull; vertex loop as while; hoisted neg margin.
  render_voxel_world untouched.
- Result: vs 937bd3b, 3 pairs: render/spheres -12.86% (±1.02%), allocs
  8604->8540; render/cubes_grid_solid -8.01% (±0.21%), allocs 2844->2588;
  render/cubes_grid_textured -7.95% (±0.57%), allocs 2844->2588; 14 other
  cases within noise. Score 0.982. mruby (round check, with mat4): spheres
  -9.9%.

### 2026-09-25 Mat4#multiply_matrix: unrolled scalar 4x4 product — KEEP
- Hypothesis: one multiply costs 8.8 us; render/cubes_grid_textured does 65
  per op (8320 `Mat4#[]`, 1040 `[]=`, 1365 times blocks, 1684 Float allocs
  at mat4.rb:37), ~32% of the case.
- Change: `app/d3d/mat4.rb` (937bd3b): both @data arrays read into 32
  locals, result built as one array literal with the same summation order
  (starting from 0.0, bit-identical); multiply_vec3 reads into locals too.
- Result: vs 7e5e7e5, 3 pairs: math/mat4_multiply -86.9% (±0.04%),
  render/cubes_grid_solid -33.2% (±0.17%), render/cubes_grid_textured
  -30.8% (±0.57%), render/spheres -2.9% (within noise); others within
  noise; allocs/op unchanged. Score 0.846. mruby (round check):
  -84.5% / -30.2% / -30.2%.

### 2026-09-25 Collisions: transform vertices once, scalar ray/sphere triangle tests — KEEP
- Hypothesis: `physics/ray_model` (2.22 ms, 13823 allocs/op) and
  `physics/sphere_model` (2.86 ms, 14661 allocs/op) call
  `Mat4#transform_point` 1440x/op for only 289 unique vertices; Vec3 math in
  `ray_triangle` / `closest_point_on_triangle` adds thousands of Vec3s.
- Change: `app/d3d/collisions.rb` (0b68a34): matrix read once into locals,
  all mesh vertices transformed into reused flat wx/wy/wz arrays with
  transform_point's exact arithmetic; Moller-Trumbore and closest-point tests
  inlined as scalar math; Vec3s/hash only for the returned hit. Public
  `ray_triangle` / `point_in_triangle` unchanged.
- Result: vs d161681, 3 pairs: physics/ray_model -82.3% (±0.5%), allocs
  13825->3346; physics/sphere_model -77.3% (±0.2%), allocs 14661->2284; all
  other cases within noise. Score 0.826. mruby (round check): -82.0% / -78.3%.

### 2026-09-25 VoxelWorld: packed Integer block keys instead of "x,y,z" strings — KEEP
- Hypothesis: `voxel/build_mesh` (3.69 ms, 30294 allocs/op) spends 19563
  String allocs/op building `"x,y,z"` keys in `has_block?`; same keys in
  raycast, aabb_intersects? and voxel_body_move.
- Change: `app/d3d/voxel_world.rb` (784daec): key = ((x+OFF)*SPAN + (y+OFF))
  *SPAN + (z+OFF), OFF = 2**19, SPAN = 2**20 (coords +-524288, fits 64-bit
  fixnums); build_mesh computes base key once per block and adds
  precomputed per-face deltas.
- Result: vs 0b68a34, 3 pairs: voxel/build_mesh -60.6% (±0.73%) allocs
  30294->10731; voxel/aabb_query -47.2% (±1.07%) allocs 43->7; voxel/raycast
  -44.2% (±0.20%) allocs 134->27; physics/voxel_body_move -22.0% (±0.79%)
  allocs 43->18; others within noise. Score 0.866. mruby (round check):
  build_mesh -46.9%, raycast -29.6%, aabb_query -13.6%, voxel_body_move -5.1%.

### 2026-09-25 Renderer: hoist -NDC_MARGIN, negation-free sort key, while loops, inlined shade — REJECT
- Hypothesis: `render/spheres` makes 11126 `Float#-@` calls/op (cull margin +
  sort key), 32 each_with_index blocks; `render/voxel_world_lit` 894 `shade`
  calls + 894 [r,g,b] Arrays/op.
- Change: `app/d3d/renderer.rb`: NEG_NDC_MARGIN constant, `0.0 - z_depth`
  sort key, while loops in render_model_optimized, scalar inlined shade.
- Result: evaluate.rb "no case measurably faster" (all within_noise, score
  0.9951, 3 pairs). Consistent direction: render/spheres -4.18% ±0.22,
  voxel_world_lit -3.24% ±0.32 (allocs 2477->1583), cubes_grid_solid -2.23%
  ±1.09, cubes_grid_textured -2.12% ±0.72 (allocs 2844->2588), voxel_world
  -1.52% ±0.30. Tests and golden passed; branch reset to 784daec.
- Notes: real but small gains; worth bundling with a larger render change.

### 2026-09-25 SceneRenderer: no Float#**, allocation-free light_at, parallel sort keys — REJECT
- Hypothesis: `cell_grid/render` 6.31 ms/op; 3085 `Float#**`, 413 light_at
  Arrays + 1239 clamp calls, 1040 sort pair Arrays per op.
- Change: `app/d3d/scene_renderer.rb`: `t*t` instead of `**2`, private
  scalar light_rgb, parallel @keys/@prims arrays sorted by index.
- Result: evaluate.rb "no case measurably faster"; all visible cases within
  noise with allocs unchanged (render/spheres -0.40% ±0.30, voxel_world_lit
  -0.06% ±0.68, build_mesh +1.29% ±1.59). The cell_grid/render delta and
  score were lost (only the output tail was captured). Branch reset to
  784daec.
- Notes: these micro-costs are not where cell_grid/render spends its time.

### 2026-09-25 Renderer: `path: :solid` instead of `primitive_marker: :solid` — output change, not a perf attempt
- Why: DragonRuby 7.13 deprecates `primitive_marker: :solid`. Solid
  triangles are now `:solid` sprites and need `source_x..source_y3`
  (0,0 / 1,0 / 0,1); without them DragonRuby draws nothing (checked with
  screenshots).
- Result: CRuby render/* +7% to +13% slower (solid triangle hashes grow from
  12 to 18 keys; building one literal instead of key-by-key assignment
  helped only ~1-2%). mruby, where the game runs: all render/* within noise
  (score 0.991).
- Lesson: hash-shape costs differ a lot between CRuby and mruby. For changes
  to output hashes, trust `compare.rb --mruby` over CRuby numbers.

### 2026-09-25 SceneRenderer#draw_face: shared subdivision vertex grid — KEEP
- Hypothesis: draw_face/emit_textured is ~4.7 ms of `cell_grid/render`.
  Each of 571 sub-quads per op built 4 fresh vertex arrays although only
  (sub+1)^2 distinct points exist, plus `poly.map`, `all?`/`any?` blocks and
  `dir_to_cam` arrays.
- Change: `app/d3d/scene_renderer.rb`: scalar o/u/v, camera-space and
  projected grid computed once per face into reused scratch arrays; clipping
  path only for quads crossing the near plane; unrolled offscreen?/pad!.
- Result (CRuby, vs 94a6949): cell_grid/render -15.9% ±0.6% (7.498 ->
  6.306 ms), allocs/op 17342 -> 7782 (-55.1%); all other cases within noise;
  score 0.992.
- Notes: screen coords may differ by float ulps (golden tolerance), triangle
  order and keys unchanged. Commit 34acd73.

### 2026-09-25 CellGrid#visible_cells: flat-index BFS, inlined portal test — KEEP
- Hypothesis: visible_cells was 3.90 ms/op (~45% of `cell_grid/render`):
  5838 `open?`, 4540 `grid_point`, 1135 `portal_visible?` calls, 972 queue
  triples and 9080 `Float#-@` per op.
- Change: `app/d3d/cell_grid.rb`: queue flat cell indices, `while` loop over
  precomputed direction offsets with inline bounds check, inlined
  portal_visible?/grid_point with precomputed corner offsets and negated tan.
  Visit order and result order unchanged.
- Result (CRuby, vs b1beda3, 3 pairs): cell_grid/visible_cells -25.2% ±0.13%,
  allocs/op 4629 -> 1713; cell_grid/render -13.9% ±0.21%, allocs/op 20258 ->
  17342; others within noise; score 0.974.
- Notes: commit 94a6949.

### 2026-09-25 Round total in mruby (both changes, vs b1beda3, 2 pairs)
- cell_grid/visible_cells -40.9% ±0.5%, cell_grid/render -35.9% ±0.5%, no
  case slower; score 0.946. cell_grid/collide_sphere +2.6% ±0.7% (judged
  within noise by compare.rb; untouched code path, see backlog).

### 2026-09-25 Renderer: clip-space vertex cache per model — KEEP
- Hypothesis: `render/spheres` transformed 3708 front faces x 3 corners =
  11124 vertices per op, but the 16 spheres only have 4624 unique vertices
  (each shared by up to 6 triangles). Transform each vertex once per model.
- Change: `Renderer#render_model_optimized` fills reused flat arrays
  (x/y/z/w) for all vertices, the face loop only indexes them.
- Result (CRuby, 3 pairs, full suite): render/spheres -17.2% ±0.5%,
  cubes_grid_solid -7.0% ±0.7%, cubes_grid_textured -6.0% ±0.2%, nothing
  slower, score 0.981. Allocs/op render/spheres 10380 -> 8537.
  mruby (2 pairs): spheres -11.0% ±0.4%, cubes -5.8% / -5.9%, score 0.955.
- Notes: eager transform also covers vertices only used by back faces; a
  lazy per-vertex stamp could skip those (~half of them) at the cost of a
  check per corner. The voxel path has no shared vertices yet (see backlog).
