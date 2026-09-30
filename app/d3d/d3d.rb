module D3D
  VERSION = '1.0.0'
  SCREEN_WIDTH = 1280
  SCREEN_HEIGHT = 720
end

# Folder the engine files live in, relative to the game directory. Define
# D3D_ROOT before requiring this file to vendor the engine elsewhere, e.g.
#   D3D_ROOT = 'lib/d3d'
#   require 'lib/d3d/d3d.rb'
Object.const_set(:D3D_ROOT, 'app/d3d') unless Object.const_defined?(:D3D_ROOT)

%w[
  vec3
  mat4
  mesh
  model
  camera
  native
  depth_sort
  renderer
  obj_loader
  collisions
  voxel_world
  voxel_body
  v
  pose
  flat_mesh
  cell_grid
  scene_renderer
  grid_map
].each { |f| require "#{Object.const_get(:D3D_ROOT)}/#{f}.rb" }

module D3D

  class << self
    def render(camera, models, lights: nil, light: nil, fog: nil)
      Renderer.render(camera, models, lights: lights, light: light, fog: fog)
    end

    def render_voxel_world(camera, voxel_world, light: nil, fog: nil)
      Renderer.render_voxel_world(camera, voxel_world, light: light, fog: fog)
    end

    def load_obj(path)
      ObjLoader.load(path)
    end

    def cube_mesh
      Mesh.cube
    end

    def plane_mesh(width: 1, depth: 1, segments_x: 1, segments_z: 1)
      Mesh.plane(width: width, depth: depth, segments_x: segments_x, segments_z: segments_z)
    end

    def sphere_mesh(radius: 1, segments: 16, rings: 16)
      Mesh.sphere(radius: radius, segments: segments, rings: rings)
    end
  end
end
