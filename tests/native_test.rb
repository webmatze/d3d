require "minitest/autorun"
require_relative "../app/d3d/native"
require_relative "../app/d3d/depth_sort"

class NativeTest < Minitest::Test
  # Stands in for the C extension, which only exists inside DragonRuby.
  module FakeExt
    extend self
    API = D3D::Native::API
    attr_reader :calls

    def sort_by_depth(list)
      (@calls ||= []) << :sort_by_depth
      list.sort_by { |t| -t[:z_depth] }
    end

    def sort_pairs(list)
      (@calls ||= []) << :sort_pairs
      list.sort_by { |e| -e[0] }.map { |e| e[1] }
    end
  end

  def teardown
    D3D.send(:remove_const, :Ext) if D3D.constants.include?(:Ext)
    D3D::Native.enabled = false
  end

  def test_load_fails_quietly_outside_dragonruby
    refute D3D::Native.load
    refute D3D::Native.enabled?
    refute D3D::Native.loaded?
  end

  def test_cannot_enable_without_the_extension
    D3D::Native.enabled = true
    refute D3D::Native.enabled?
  end

  def test_depth_sort_uses_the_extension_once_loaded
    D3D.const_set(:Ext, FakeExt)
    assert D3D::Native.load
    tris = [{ z_depth: 1.0 }, { z_depth: 3.0 }]
    assert_equal [3.0, 1.0], D3D::DepthSort.triangles(tris).map { |t| t[:z_depth] }
    assert_equal [3.0, 1.0], D3D::DepthSort.pairs(tris.map { |t| [t[:z_depth], t] }).map { |t| t[:z_depth] }
    assert_equal %i[sort_by_depth sort_pairs], FakeExt.calls.last(2)
  end

  # A library built for another engine version must not be called.
  module OutdatedExt
    API = D3D::Native::API - 1
  end

  def test_extension_with_another_api_is_refused
    D3D.const_set(:Ext, OutdatedExt)
    out, = capture_io { refute D3D::Native.load }
    refute D3D::Native.loaded?
    D3D::Native.enabled = true
    refute D3D::Native.enabled?
    assert_includes out, "expects #{D3D::Native::API}"
  end

  def test_extension_can_be_switched_off_again
    D3D.const_set(:Ext, FakeExt)
    D3D::Native.load
    D3D::Native.enabled = false
    refute D3D::Native.enabled?
    FakeExt.calls&.clear
    D3D::DepthSort.triangles([{ z_depth: 1.0 }])
    assert_empty FakeExt.calls.to_a
  end
end
