module D3D
  class Mat4
    attr_accessor :data

    def initialize(data = nil)
      @data = data || identity_data
    end

    def [](row, col)
      @data[row * 4 + col]
    end

    def []=(row, col, value)
      @data[row * 4 + col] = value
    end

    def dup
      Mat4.new(@data.dup)
    end

    def *(other)
      if other.is_a?(Mat4)
        multiply_matrix(other)
      elsif other.is_a?(Vec3)
        multiply_vec3(other)
      else
        raise ArgumentError, "Cannot multiply Mat4 with #{other.class}"
      end
    end

    # Unrolled 4x4 product. Each entry keeps the original summation order
    # (starting from 0.0, k = 0..3) so results stay bit-identical.
    def multiply_matrix(other)
      a = @data
      b = other.data
      a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15 = a
      b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15 = b
      Mat4.new([
        (((0.0 + a0 * b0) + a1 * b4) + a2 * b8) + a3 * b12,
        (((0.0 + a0 * b1) + a1 * b5) + a2 * b9) + a3 * b13,
        (((0.0 + a0 * b2) + a1 * b6) + a2 * b10) + a3 * b14,
        (((0.0 + a0 * b3) + a1 * b7) + a2 * b11) + a3 * b15,
        (((0.0 + a4 * b0) + a5 * b4) + a6 * b8) + a7 * b12,
        (((0.0 + a4 * b1) + a5 * b5) + a6 * b9) + a7 * b13,
        (((0.0 + a4 * b2) + a5 * b6) + a6 * b10) + a7 * b14,
        (((0.0 + a4 * b3) + a5 * b7) + a6 * b11) + a7 * b15,
        (((0.0 + a8 * b0) + a9 * b4) + a10 * b8) + a11 * b12,
        (((0.0 + a8 * b1) + a9 * b5) + a10 * b9) + a11 * b13,
        (((0.0 + a8 * b2) + a9 * b6) + a10 * b10) + a11 * b14,
        (((0.0 + a8 * b3) + a9 * b7) + a10 * b11) + a11 * b15,
        (((0.0 + a12 * b0) + a13 * b4) + a14 * b8) + a15 * b12,
        (((0.0 + a12 * b1) + a13 * b5) + a14 * b9) + a15 * b13,
        (((0.0 + a12 * b2) + a13 * b6) + a14 * b10) + a15 * b14,
        (((0.0 + a12 * b3) + a13 * b7) + a14 * b11) + a15 * b15
      ])
    end

    def multiply_vec3(vec, w = 1.0)
      d = @data
      vx = vec.x
      vy = vec.y
      vz = vec.z
      x = d[0] * vx + d[1] * vy + d[2] * vz + d[3] * w
      y = d[4] * vx + d[5] * vy + d[6] * vz + d[7] * w
      z = d[8] * vx + d[9] * vy + d[10] * vz + d[11] * w
      w_out = d[12] * vx + d[13] * vy + d[14] * vz + d[15] * w
      [Vec3.new(x, y, z), w_out]
    end

    def transform_point(vec)
      result, w = multiply_vec3(vec, 1.0)
      if w != 0 && w != 1
        result.x /= w
        result.y /= w
        result.z /= w
      end
      result
    end

    def transform_direction(vec)
      result, _ = multiply_vec3(vec, 0.0)
      result
    end

    def to_s
      rows = 4.times.map do |row|
        4.times.map { |col| format("%8.4f", self[row, col]) }.join(" ")
      end
      "Mat4[\n  #{rows.join("\n  ")}\n]"
    end

    def inspect
      to_s
    end

    # Class methods for creating common matrices
    def self.identity
      Mat4.new
    end

    def self.translation(x, y, z)
      mat = Mat4.new
      mat[0, 3] = x.to_f
      mat[1, 3] = y.to_f
      mat[2, 3] = z.to_f
      mat
    end

    def self.translation_vec(vec)
      translation(vec.x, vec.y, vec.z)
    end

    def self.scale(x, y = nil, z = nil)
      y ||= x
      z ||= x
      mat = Mat4.new
      mat[0, 0] = x.to_f
      mat[1, 1] = y.to_f
      mat[2, 2] = z.to_f
      mat
    end

    def self.scale_vec(vec)
      scale(vec.x, vec.y, vec.z)
    end

    def self.rotation_x(angle)
      c = Math.cos(angle)
      s = Math.sin(angle)
      mat = Mat4.new
      mat[1, 1] = c
      mat[1, 2] = -s
      mat[2, 1] = s
      mat[2, 2] = c
      mat
    end

    def self.rotation_y(angle)
      c = Math.cos(angle)
      s = Math.sin(angle)
      mat = Mat4.new
      mat[0, 0] = c
      mat[0, 2] = s
      mat[2, 0] = -s
      mat[2, 2] = c
      mat
    end

    def self.rotation_z(angle)
      c = Math.cos(angle)
      s = Math.sin(angle)
      mat = Mat4.new
      mat[0, 0] = c
      mat[0, 1] = -s
      mat[1, 0] = s
      mat[1, 1] = c
      mat
    end

    def self.rotation(rx, ry, rz)
      rotation_z(rz) * rotation_y(ry) * rotation_x(rx)
    end

    def self.rotation_vec(vec)
      rotation(vec.x, vec.y, vec.z)
    end

    def self.perspective(fov_degrees, aspect, near, far)
      fov_rad = fov_degrees * Math::PI / 180.0
      tan_half_fov = Math.tan(fov_rad / 2.0)

      mat = Mat4.new(Array.new(16, 0.0))
      mat[0, 0] = 1.0 / (aspect * tan_half_fov)
      mat[1, 1] = 1.0 / tan_half_fov
      mat[2, 2] = -(far + near) / (far - near)
      mat[2, 3] = -(2.0 * far * near) / (far - near)
      mat[3, 2] = -1.0
      mat
    end

    def self.look_at(eye, target, up)
      look_at_scalar(eye.x, eye.y, eye.z, target.x, target.y, target.z, up.x, up.y, up.z)
    end

    # Scalar look_at: same operation order as Vec3#-, #normalize, #cross and
    # #dot, but no Vec3 allocations and no Mat4#[]= calls.
    def self.look_at_scalar(ex, ey, ez, tx, ty, tz, ux, uy, uz)
      ex = ex.to_f
      ey = ey.to_f
      ez = ez.to_f
      ux = ux.to_f
      uy = uy.to_f
      uz = uz.to_f

      # forward = (eye - target).normalize
      fx = ex - tx.to_f
      fy = ey - ty.to_f
      fz = ez - tz.to_f
      len = Math.sqrt(fx * fx + fy * fy + fz * fz)
      if len == 0
        fx = 0.0
        fy = 0.0
        fz = 0.0
      else
        fx /= len
        fy /= len
        fz /= len
      end

      # right = up.cross(forward).normalize
      rx = uy * fz - uz * fy
      ry = uz * fx - ux * fz
      rz = ux * fy - uy * fx
      len = Math.sqrt(rx * rx + ry * ry + rz * rz)
      if len == 0
        rx = 0.0
        ry = 0.0
        rz = 0.0
      else
        rx /= len
        ry /= len
        rz /= len
      end

      # new_up = forward.cross(right)
      nx = fy * rz - fz * ry
      ny = fz * rx - fx * rz
      nz = fx * ry - fy * rx

      Mat4.new([
        rx, ry, rz, -(rx * ex + ry * ey + rz * ez),
        nx, ny, nz, -(nx * ex + ny * ey + nz * ez),
        fx, fy, fz, -(fx * ex + fy * ey + fz * ez),
        0.0, 0.0, 0.0, 1.0
      ])
    end

    def self.orthographic(left, right, bottom, top, near, far)
      mat = Mat4.new(Array.new(16, 0.0))
      mat[0, 0] = 2.0 / (right - left)
      mat[1, 1] = 2.0 / (top - bottom)
      mat[2, 2] = -2.0 / (far - near)
      mat[0, 3] = -(right + left) / (right - left)
      mat[1, 3] = -(top + bottom) / (top - bottom)
      mat[2, 3] = -(far + near) / (far - near)
      mat[3, 3] = 1.0
      mat
    end

    private

    def identity_data
      [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
      ]
    end
  end
end
