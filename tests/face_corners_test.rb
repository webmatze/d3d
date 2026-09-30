require "minitest/autorun"
require_relative "../app/d3d/vec3"
require_relative "../app/d3d/voxel_world"

class FaceCornersTest < Minitest::Test
  LIFT = 0.004

  def test_top_face_corners
    hit = { x: 1, y: 2, z: 3, normal: [0, 1, 0] }
    corners = D3D::VoxelWorld.face_corners(hit)

    assert_equal 4, corners.size
    corners.each { |c| assert_in_delta 3 + LIFT, c[1], 1e-9 }
    xs = corners.map { |c| c[0] }.sort
    zs = corners.map { |c| c[2] }.sort
    assert_equal [1, 1, 2, 2], xs
    assert_equal [3, 3, 4, 4], zs
  end

  def test_bottom_face_is_lifted_downward
    hit = { x: 0, y: 5, z: 0, normal: [0, -1, 0] }
    corners = D3D::VoxelWorld.face_corners(hit)
    corners.each { |c| assert_in_delta 5 - LIFT, c[1], 1e-9 }
  end

  def test_negative_x_face
    hit = { x: 2, y: 0, z: 0, normal: [-1, 0, 0] }
    corners = D3D::VoxelWorld.face_corners(hit)
    corners.each { |c| assert_in_delta 2 - LIFT, c[0], 1e-9 }
    ys = corners.map { |c| c[1] }.sort
    zs = corners.map { |c| c[2] }.sort
    assert_equal [0, 0, 1, 1], ys
    assert_equal [0, 0, 1, 1], zs
  end

  def test_positive_z_face_with_custom_lift
    hit = { x: 0, y: 0, z: 4, normal: [0, 0, 1] }
    corners = D3D::VoxelWorld.face_corners(hit, lift: 0.01)
    corners.each { |c| assert_in_delta 5 + 0.01, c[2], 1e-9 }
  end

  def test_corners_form_a_loop
    hit = { x: 1, y: 2, z: 3, normal: [0, 1, 0] }
    corners = D3D::VoxelWorld.face_corners(hit)
    # consecutive corners share exactly one varying axis (proper edge loop)
    4.times do |i|
      a = corners[i]
      b = corners[(i + 1) % 4]
      diffs = 3.times.count { |ax| a[ax] != b[ax] }
      assert_equal 1, diffs
    end
  end

  def test_zero_normal_returns_nil
    hit = { x: 0, y: 0, z: 0, normal: [0, 0, 0] }
    assert_nil D3D::VoxelWorld.face_corners(hit)
  end
end
