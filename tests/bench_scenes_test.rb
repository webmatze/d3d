require "minitest/autorun"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(ROOT) unless $LOAD_PATH.include?(ROOT)
require "app/d3d/d3d.rb"
require_relative "../bench/scenes"

class BenchScenesTest < Minitest::Test
  def test_cube_grid_count
    models = Scenes.cube_grid(4, textured: false)
    assert_equal 16, models.length
    assert(models.all? { |m| m.is_a?(D3D::Model) })
  end

  def test_cube_grid_solid_has_no_texture
    models = Scenes.cube_grid(2, textured: false)
    assert(models.all? { |m| m.texture.nil? })
  end

  def test_cube_grid_textured_sets_texture
    models = Scenes.cube_grid(2, textured: true)
    assert(models.all? { |m| !m.texture.nil? })
  end

  def test_sphere_field_count
    assert_equal 10, Scenes.sphere_field(10).length
  end

  def test_voxel_world_has_blocks
    world = Scenes.voxel_world
    assert world.block_count >= 512
  end

  def test_camera_overview_returns_camera
    assert_instance_of D3D::Camera, Scenes.camera_overview
  end

  def test_camera_voxel_returns_camera
    assert_instance_of D3D::Camera, Scenes.camera_voxel
  end

  def test_sphere_field_positions_are_spread
    models = Scenes.sphere_field(8)
    coords = models.map { |m| [m.position.x.round(4), m.position.z.round(4)] }
    assert_equal 8, coords.uniq.length
  end
end
