# Deterministic benchmark fixtures. Assumes the D3D engine is already loaded.
# Also loaded by DragonRuby (mruby_runner.rb), hence extend self.
module Scenes
  extend self

  def camera_overview
    cam = D3D::Camera.new(position: D3D::Vec3.new(12.0, 10.0, 18.0))
    cam.look_at(D3D::Vec3.new(0.0, 0.0, 0.0))
    cam
  end

  # Camera framing the voxel_world scene (which is centered near (8, 2, 8)).
  def camera_voxel
    cam = D3D::Camera.new(position: D3D::Vec3.new(24.0, 18.0, 24.0))
    cam.look_at(D3D::Vec3.new(8.0, 2.0, 8.0))
    cam
  end

  # n x n grid of cubes centered on the origin. Shares one mesh across models.
  def cube_grid(n, textured: false)
    mesh = D3D::Mesh.cube
    models = []
    n.times do |i|
      n.times do |j|
        x = (i - (n - 1) / 2.0) * 2.0
        z = (j - (n - 1) / 2.0) * 2.0
        models << D3D::Model.new(
          mesh: mesh,
          texture: textured ? "sprites/block.png" : nil,
          position: D3D::Vec3.new(x, 0.0, z),
          color: { r: 200, g: 100, b: 50, a: 255 }
        )
      end
    end
    models
  end

  # `count` spheres arranged in a deterministic spiral.
  def sphere_field(count)
    mesh = D3D::Mesh.sphere(radius: 0.8, segments: 16, rings: 16)
    models = []
    count.times do |i|
      angle = i * 0.618 * Math::PI * 2
      r = 2.0 + i * 0.4
      models << D3D::Model.new(
        mesh: mesh,
        position: D3D::Vec3.new(Math.cos(angle) * r, 0.0, Math.sin(angle) * r),
        color: { r: 80, g: 160, b: 220, a: 255 }
      )
    end
    models
  end

  # 16x16 columns of blocks with a deterministic height field. Mesh prebuilt.
  def voxel_world
    world = D3D::VoxelWorld.new
    size = 16
    size.times do |x|
      size.times do |z|
        height = 1 + ((Math.sin(x * 0.4) + Math.cos(z * 0.4)) * 2.0).to_i.abs
        (0..height).each do |y|
          world.add_block(x, y, z, { r: 120, g: 180, b: 90, a: 255 })
        end
      end
    end
    world.rebuild!
    world
  end

  # Cell-grid mine: a room, a tunnel and a roughened cavern with a pillar.
  def cell_grid
    g = D3D::CellGrid.new(24, 12, 30, cell_size: 10.0)
    g.carve(3, 8, 3, 6, 2, 7, :metal, [1.0, 1.0, 1.05])
    g.carve(5, 6, 4, 5, 8, 14, :rock, [0.8, 0.7, 0.6])
    g.carve(2, 16, 2, 9, 15, 25, :rock, [0.8, 0.7, 0.6])
    g.fill(8, 9, 2, 9, 19, 20)
    g.roughen(2, 16, 2, 9, 15, 25, 20, D3D::Lcg.new(7))
    g.rebuild_faces
  end

  # Pose at the tunnel mouth looking into the cavern.
  def cell_grid_pose
    D3D::Pose.new([55.0, 45.0, 120.0], [0.2, -0.1, 1.0])
  end

  # Tall grid like Core Breach level 2: a 12x34x12 shaft with ledges, a
  # cross-bridge and side galleries.
  def cell_grid_shaft
    g = D3D::CellGrid.new(48, 40, 48, cell_size: 10.0)
    g.carve(18, 29, 3, 36, 18, 29, :rock, [0.75, 0.7, 0.65])
    g.fill(18, 20, 20, 20, 20, 23)            # ledge
    g.fill(27, 29, 12, 12, 24, 27)            # ledge
    g.fill(18, 29, 24, 24, 23, 24)            # cross-bridge
    g.carve(6, 17, 27, 30, 21, 24, :rock, [0.75, 0.7, 0.65])   # west gallery
    g.carve(30, 42, 14, 18, 20, 26, :metal, [0.05, 0.05, 0.07]) # dark wing
    g.carve(20, 27, 1, 6, 4, 17, :rock, [1.1, 0.6, 0.4])       # magma tunnel
    g.rebuild_faces
  end

  # Near the top of the shaft, looking down and across it.
  def cell_grid_shaft_pose
    D3D::Pose.new([235.0, 330.0, 200.0], [0.2, -0.8, 0.5])
  end

  def scene_renderer
    D3D::SceneRenderer.new(
      focal: 620,
      materials: { rock: { path: "sprites/cell_grid/rock.png", size: 128 },
                   metal: { path: "sprites/cell_grid/metal.png", size: 128 } }
    )
  end
end
