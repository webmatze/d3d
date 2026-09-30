require "minitest/autorun"
require_relative "../app/d3d/vec3"
require_relative "../app/d3d/voxel_world"

class VoxelWorldAabbTest < Minitest::Test
  def setup
    @world = D3D::VoxelWorld.new
    @world.add_block(0, 0, 0, { r: 255, g: 255, b: 255 })
  end

  def test_aabb_overlapping_a_block_intersects
    min = D3D::Vec3.new(0.5, 0.5, 0.5)
    max = D3D::Vec3.new(1.5, 1.5, 1.5)
    assert @world.aabb_intersects?(min, max)
  end

  def test_aabb_in_empty_space_does_not_intersect
    min = D3D::Vec3.new(2.5, 2.5, 2.5)
    max = D3D::Vec3.new(3.5, 3.5, 3.5)
    refute @world.aabb_intersects?(min, max)
  end

  def test_aabb_touching_block_face_exactly_does_not_intersect
    # Box sits exactly on top of the block (min.y == block top)
    min = D3D::Vec3.new(0.2, 1.0, 0.2)
    max = D3D::Vec3.new(0.8, 2.0, 0.8)
    refute @world.aabb_intersects?(min, max)
  end

  def test_aabb_slightly_inside_block_intersects
    min = D3D::Vec3.new(0.2, 0.999, 0.2)
    max = D3D::Vec3.new(0.8, 1.999, 0.8)
    assert @world.aabb_intersects?(min, max)
  end

  def test_aabb_spanning_multiple_cells_finds_block
    @world.add_block(3, 0, 0, { r: 255, g: 255, b: 255 })
    min = D3D::Vec3.new(1.1, 0.2, 0.2)
    max = D3D::Vec3.new(3.5, 0.8, 0.8)
    assert @world.aabb_intersects?(min, max)
  end

  def test_aabb_at_negative_coordinates
    @world.add_block(-2, -1, -2, { r: 255, g: 255, b: 255 })
    min = D3D::Vec3.new(-1.5, -0.5, -1.5)
    max = D3D::Vec3.new(-1.2, 0.5, -1.2)
    assert @world.aabb_intersects?(min, max)
  end
end
