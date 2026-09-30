require "minitest/autorun"
require_relative "../app/d3d/vec3"
require_relative "../app/d3d/voxel_world"
require_relative "../app/d3d/voxel_body"

class VoxelBodyTest < Minitest::Test
  DT = 1.0 / 60.0
  WHITE = { r: 255, g: 255, b: 255 }.freeze

  def setup
    @world = D3D::VoxelWorld.new
  end

  def floor_world
    # 5x5 floor at y=0
    (-2..2).each do |x|
      (-2..2).each do |z|
        @world.add_block(x, 0, z, WHITE)
      end
    end
    @world
  end

  def test_falls_under_gravity_in_empty_world
    body = D3D::VoxelBody.new(0.5, 10, 0.5)
    body.move(@world, DT)
    assert body.velocity.y < 0
    assert body.position.y < 10
    refute body.on_ground
  end

  def test_lands_on_block_and_snaps_to_surface
    floor_world
    body = D3D::VoxelBody.new(0.5, 3, 0.5)
    120.times { body.move(@world, DT) }
    assert_in_delta 1.0, body.position.y, 1e-6
    assert_equal 0, body.velocity.y
    assert body.on_ground
  end

  def test_terminal_velocity_clamped
    body = D3D::VoxelBody.new(0.5, 10_000, 0.5)
    600.times { body.move(@world, DT) }
    assert body.velocity.y >= body.terminal_velocity
    assert_in_delta body.terminal_velocity, body.velocity.y, 1e-6
  end

  def test_horizontal_movement_blocked_by_wall
    floor_world
    @world.add_block(2, 1, 0, WHITE) # wall block in +x direction
    body = D3D::VoxelBody.new(0.5, 1, 0.5)
    body.velocity.x = 4.0
    60.times { body.move(@world, DT) }
    # stopped just before the wall: x + half_width <= 2
    assert body.position.x + body.width / 2.0 <= 2.0
    assert_equal 0, body.velocity.x
  end

  def test_upward_movement_blocked_by_ceiling
    floor_world
    @world.add_block(0, 3, 0, WHITE) # ceiling above spawn
    body = D3D::VoxelBody.new(0.5, 1, 0.5)
    body.velocity.y = 10.0
    max_head = 0.0
    hit_ceiling = false
    30.times do
      body.move(@world, DT)
      max_head = [max_head, body.position.y + body.height].max
      hit_ceiling ||= body.velocity.y == 0
    end
    # head never penetrates the ceiling at y=3, and the snap zeroed velocity
    assert max_head <= 3.0
    assert hit_ceiling
  end

  def test_ground_below_detects_standing_surface
    floor_world
    body = D3D::VoxelBody.new(0.5, 1, 0.5)
    assert body.ground_below?(@world)

    airborne = D3D::VoxelBody.new(0.5, 5, 0.5)
    refute airborne.ground_below?(@world)
  end

  def test_intersects_block
    body = D3D::VoxelBody.new(0.5, 1, 0.5)
    assert body.intersects_block?(0, 1, 0)   # block at feet level overlaps
    assert body.intersects_block?(0, 2, 0)   # head level overlaps (height 1.8)
    refute body.intersects_block?(0, 3, 0)   # above the head
    refute body.intersects_block?(3, 1, 0)   # far away
  end

  def test_prevent_falling_stops_at_ledge
    @world.add_block(0, 0, 0, WHITE) # single block, edges all around
    body = D3D::VoxelBody.new(0.5, 1, 0.5)
    body.move(@world, DT) # settle on_ground
    assert body.on_ground

    60.times do
      body.velocity.x = 4.0
      body.move(@world, DT, prevent_falling: true)
    end
    assert body.on_ground
    # may overhang, but part of the feet must stay above the block (x - half < 1)
    assert body.position.x - body.width / 2.0 < 1.0
    assert body.ground_below?(@world)
    assert_equal 0, body.velocity.x
  end

  def test_without_prevent_falling_walks_off_ledge
    @world.add_block(0, 0, 0, WHITE)
    body = D3D::VoxelBody.new(0.5, 1, 0.5)
    60.times do
      body.velocity.x = 4.0
      body.move(@world, DT)
    end
    refute body.on_ground
    assert body.position.y < 1.0
  end

  def test_gravity_can_be_disabled
    body = D3D::VoxelBody.new(0.5, 10, 0.5, gravity: 0)
    body.move(@world, DT)
    assert_equal 0, body.velocity.y
    assert_in_delta 10.0, body.position.y, 1e-9
  end
end
