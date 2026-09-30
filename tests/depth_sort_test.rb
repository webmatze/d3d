require "minitest/autorun"
require_relative "../app/d3d/native"
require_relative "../app/d3d/depth_sort"

class DepthSortTest < Minitest::Test
  DEPTHS = [0.5, 3.0, -1.0, 3.0, 2.25, 0.0, 10.0, 2.25].freeze

  def triangles
    DEPTHS.each_with_index.map { |z, i| { z_depth: z, id: i } }
  end

  # Runs the block once with the CRuby branch and once with the mruby branch.
  def each_vm
    original = D3D::DepthSort::MRUBY
    [false, true].each do |mruby|
      set_mruby(mruby)
      yield mruby
    end
  ensure
    set_mruby(original)
  end

  def set_mruby(value)
    D3D::DepthSort.send(:remove_const, :MRUBY)
    D3D::DepthSort.const_set(:MRUBY, value)
  end

  def test_triangles_are_sorted_back_to_front
    each_vm do |mruby|
      list = triangles
      sorted = D3D::DepthSort.triangles(list)
      assert_equal DEPTHS.sort.reverse, sorted.map { |t| t[:z_depth] }, "mruby=#{mruby}"
      assert_equal list.map { |t| t[:id] }.sort, sorted.map { |t| t[:id] }.sort
      refute_same list, sorted
    end
  end

  def test_pairs_return_primitives_back_to_front
    each_vm do |mruby|
      list = triangles.map { |t| [t[:z_depth], t] }
      sorted = D3D::DepthSort.pairs(list)
      assert_equal DEPTHS.sort.reverse, sorted.map { |t| t[:z_depth] }, "mruby=#{mruby}"
    end
  end

  def test_empty_lists
    each_vm do
      assert_equal [], D3D::DepthSort.triangles([])
      assert_equal [], D3D::DepthSort.pairs([])
    end
  end
end
