require "minitest/autorun"
require_relative "../app/d3d/v"
require_relative "../app/d3d/flat_mesh"

class FlatMeshTest < Minitest::Test
  V = D3D::V

  def test_box_has_twelve_triangles_with_outward_normals
    mesh = D3D::FlatMesh.new.box(0, 0, 0, 1, 2, 3, [255, 0, 0])
    assert_equal 12, mesh.tris.size
    mesh.tris.each do |t|
      centroid = V.scale(V.add(V.add(mesh.verts[t.a], mesh.verts[t.b]), mesh.verts[t.c]), 1.0 / 3)
      assert V.dot(t.normal, centroid) > 0, "normal should point away from the centre"
    end
  end

  def test_radius_tracks_farthest_vertex
    mesh = D3D::FlatMesh.new.box(0, 0, 0, 3, 4, 0, [255, 0, 0])
    assert_in_delta 5.0, mesh.radius, 1e-9
  end

  def test_bipyramid_triangle_count_and_darker_back
    mesh = D3D::FlatMesh.new.bipyramid(6, 1.0, 2.0, 1.0, [[100, 100, 100]])
    assert_equal 12, mesh.tris.size
    assert_equal [70.0, 70.0, 70.0], mesh.tris[1].color.map { |c| c.round(6) }
  end

  def test_tri_flags
    mesh = D3D::FlatMesh.new
    a = mesh.vert(0, 0, 0)
    b = mesh.vert(1, 0, 0)
    c = mesh.vert(0, 1, 0)
    mesh.tri(a, b, c, [1, 2, 3], double_sided: true, emissive: true)
    assert mesh.tris[0].double_sided
    assert mesh.tris[0].emissive
  end
end
