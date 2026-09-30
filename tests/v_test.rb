require "minitest/autorun"
require_relative "../app/d3d/v"

class VTest < Minitest::Test
  V = D3D::V

  def assert_vec(expected, actual, delta = 1e-9)
    3.times { |i| assert_in_delta expected[i], actual[i], delta }
  end

  def test_rotate_pair_keeps_vectors_orthonormal
    a, b = V.rotate_pair([0.0, 0.0, 1.0], [1.0, 0.0, 0.0], 0.7)
    assert_in_delta 1.0, V.len(a), 1e-9
    assert_in_delta 1.0, V.len(b), 1e-9
    assert_in_delta 0.0, V.dot(a, b), 1e-9
  end

  def test_rotate_pair_turns_a_towards_b
    a, b = V.rotate_pair([0.0, 0.0, 1.0], [1.0, 0.0, 0.0], Math::PI / 2)
    assert_vec [1.0, 0.0, 0.0], a
    assert_vec [0.0, 0.0, -1.0], b
  end

  def test_basis_from_forward_matches_convention
    right, up = V.basis_from_forward([0.0, 0.0, 1.0])
    assert_vec [1.0, 0.0, 0.0], right
    assert_vec [0.0, 1.0, 0.0], up
  end

  def test_basis_from_forward_straight_up_does_not_degenerate
    right, up = V.basis_from_forward([0.0, 1.0, 0.0])
    assert_in_delta 1.0, V.len(right), 1e-9
    assert_in_delta 0.0, V.dot(right, [0.0, 1.0, 0.0]), 1e-9
    assert_in_delta 0.0, V.dot(up, [0.0, 1.0, 0.0]), 1e-9
  end

  def test_clamp
    assert_equal 0, D3D.clamp(-5, 0, 10)
    assert_equal 10, D3D.clamp(15, 0, 10)
    assert_equal 4, D3D.clamp(4, 0, 10)
  end

  def test_lcg_is_deterministic
    a = D3D::Lcg.new(42)
    b = D3D::Lcg.new(42)
    5.times { assert_equal a.int(0, 100), b.int(0, 100) }
  end
end
