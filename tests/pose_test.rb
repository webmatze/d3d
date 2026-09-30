require "minitest/autorun"
require_relative "../app/d3d/v"
require_relative "../app/d3d/pose"

class PoseTest < Minitest::Test
  V = D3D::V

  def assert_orthonormal(pose)
    [pose.right, pose.up, pose.fwd].each { |v| assert_in_delta 1.0, V.len(v), 1e-9 }
    assert_in_delta 0.0, V.dot(pose.right, pose.up), 1e-9
    assert_in_delta 0.0, V.dot(pose.up, pose.fwd), 1e-9
    assert_in_delta 0.0, V.dot(pose.fwd, pose.right), 1e-9
  end

  def test_default_pose_looks_down_positive_z
    pose = D3D::Pose.new
    assert_equal [0.0, 0.0, 1.0], pose.fwd
    assert_equal [1.0, 0.0, 0.0], pose.right
    assert_equal [0.0, 1.0, 0.0], pose.up
  end

  def test_stays_orthonormal_after_many_rotations
    pose = D3D::Pose.new
    1000.times do |i|
      pose.yaw!(0.013 * (i % 7)).pitch!(-0.021).roll!(0.017)
      pose.orthonormalize!
    end
    assert_orthonormal pose
  end

  def test_roll_keeps_forward
    pose = D3D::Pose.new
    pose.roll!(0.8)
    assert_equal [0.0, 0.0, 1.0], pose.fwd
    refute_in_delta 1.0, pose.up[1], 1e-3
  end

  def test_yaw_right_turns_forward_towards_right
    pose = D3D::Pose.new
    pose.yaw!(Math::PI / 2)
    assert_in_delta 1.0, pose.fwd[0], 1e-9
  end

  def test_pitch_up_turns_forward_upwards
    pose = D3D::Pose.new
    pose.pitch!(0.3)
    assert pose.fwd[1] > 0
  end

  def test_dup_is_independent
    pose = D3D::Pose.new([1, 2, 3])
    copy = pose.dup
    copy.position[0] = 99
    copy.yaw!(1.0)
    assert_equal 1.0, pose.position[0]
    assert_equal [0.0, 0.0, 1.0], pose.fwd
  end
end
