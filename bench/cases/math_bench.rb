Bench::Registry.register(
  "math/mat4_multiply",
  setup: lambda do
    a = D3D::Mat4.translation(1.0, 2.0, 3.0) * D3D::Mat4.rotation(0.3, 0.5, 0.7)
    b = D3D::Mat4.scale(1.5, 2.0, 0.5) * D3D::Mat4.rotation(0.1, 0.2, 0.3)
    [a, b]
  end
) { |fx| fx[0] * fx[1] }

Bench::Registry.register(
  "math/vec3_ops",
  setup: -> { [D3D::Vec3.new(1.0, 2.0, 3.0), D3D::Vec3.new(-0.5, 4.0, 2.5)] }
) do |fx|
  a, b = fx
  c = a + b
  d = a - b
  c.dot(d)
  a.cross(b).normalize
  a.length
end

Bench::Registry.register(
  "math/camera_view_matrix",
  setup: lambda do
    cam = D3D::Camera.new(position: D3D::Vec3.new(5.0, 4.0, 8.0))
    cam.look_at(D3D::Vec3.new(0.0, 0.0, 0.0))
    cam
  end
) do |cam|
  cam.invalidate_view!
  cam.get_view_matrix
end
