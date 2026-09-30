module D3D
  class Vec3
    attr_accessor :x, :y, :z

    def initialize(x = 0, y = 0, z = 0)
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
    end

    def to_a
      [@x, @y, @z]
    end

    def dup
      Vec3.new(@x, @y, @z)
    end

    def +(other)
      Vec3.new(@x + other.x, @y + other.y, @z + other.z)
    end

    def -(other)
      Vec3.new(@x - other.x, @y - other.y, @z - other.z)
    end

    def *(scalar)
      Vec3.new(@x * scalar, @y * scalar, @z * scalar)
    end

    def /(scalar)
      Vec3.new(@x / scalar, @y / scalar, @z / scalar)
    end

    def -@
      Vec3.new(-@x, -@y, -@z)
    end

    def dot(other)
      @x * other.x + @y * other.y + @z * other.z
    end

    def cross(other)
      Vec3.new(
        @y * other.z - @z * other.y,
        @z * other.x - @x * other.z,
        @x * other.y - @y * other.x
      )
    end

    def length
      Math.sqrt(@x * @x + @y * @y + @z * @z)
    end

    def length_squared
      @x * @x + @y * @y + @z * @z
    end

    def normalize
      len = length
      return Vec3.new(0, 0, 0) if len == 0
      Vec3.new(@x / len, @y / len, @z / len)
    end

    def normalize!
      len = length
      return self if len == 0
      @x /= len
      @y /= len
      @z /= len
      self
    end

    def distance_to(other)
      (self - other).length
    end

    def lerp(other, t)
      Vec3.new(
        @x + (other.x - @x) * t,
        @y + (other.y - @y) * t,
        @z + (other.z - @z) * t
      )
    end

    def ==(other)
      return false unless other.is_a?(Vec3)
      @x == other.x && @y == other.y && @z == other.z
    end

    def to_s
      "Vec3(#{@x}, #{@y}, #{@z})"
    end

    def inspect
      to_s
    end

    # Class methods for common vectors
    def self.zero
      Vec3.new(0, 0, 0)
    end

    def self.one
      Vec3.new(1, 1, 1)
    end

    def self.up
      Vec3.new(0, 1, 0)
    end

    def self.down
      Vec3.new(0, -1, 0)
    end

    def self.forward
      Vec3.new(0, 0, -1)
    end

    def self.back
      Vec3.new(0, 0, 1)
    end

    def self.right
      Vec3.new(1, 0, 0)
    end

    def self.left
      Vec3.new(-1, 0, 0)
    end
  end
end
