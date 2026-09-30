module D3D
  class Model
    attr_accessor :mesh, :texture, :position, :rotation, :scale
    # Pixel size of the texture as Integer (square) or [w, h]. Mesh uvs are
    # 0..1 and DragonRuby wants pixels, so the renderer scales by it; when
    # nil, the renderer asks DragonRuby for the image size.
    attr_accessor :texture_size
    attr_accessor :color, :visible
    attr_reader :model_matrix, :model_matrix_dirty

    def initialize(mesh:, texture: nil, position: nil, rotation: nil, scale: nil, color: nil,
                   texture_size: nil)
      @mesh = mesh
      @texture = texture
      @texture_size = texture_size
      @position = position || Vec3.new(0, 0, 0)
      @rotation = rotation || Vec3.new(0, 0, 0)
      @scale = scale || Vec3.new(1, 1, 1)
      @color = color || { r: 255, g: 255, b: 255, a: 255 }
      @visible = true
      @model_matrix = nil
      @model_matrix_dirty = true
    end

    def position=(value)
      @position = value
      @model_matrix_dirty = true
    end

    def rotation=(value)
      @rotation = value
      @model_matrix_dirty = true
    end

    def scale=(value)
      @scale = value
      @model_matrix_dirty = true
    end

    def set_translation(x, y, z)
      @position.x = x
      @position.y = y
      @position.z = z
      @model_matrix_dirty = true
      self
    end

    def set_rotation(rx, ry, rz)
      @rotation.x = rx
      @rotation.y = ry
      @rotation.z = rz
      @model_matrix_dirty = true
      self
    end

    def set_scale(sx, sy = nil, sz = nil)
      sy ||= sx
      sz ||= sx
      @scale.x = sx
      @scale.y = sy
      @scale.z = sz
      @model_matrix_dirty = true
      self
    end

    def translate(dx, dy, dz)
      @position.x += dx
      @position.y += dy
      @position.z += dz
      @model_matrix_dirty = true
      self
    end

    def rotate(drx, dry, drz)
      @rotation.x += drx
      @rotation.y += dry
      @rotation.z += drz
      @model_matrix_dirty = true
      self
    end

    def get_model_matrix
      if @model_matrix_dirty || @model_matrix.nil?
        @model_matrix = calculate_model_matrix
        @model_matrix_dirty = false
      end
      @model_matrix
    end

    def mark_dirty!
      @model_matrix_dirty = true
    end

    def bounding_sphere_radius
      return @bounding_sphere_radius if @bounding_sphere_radius

      max_dist = 0
      @mesh.vertices.each do |v|
        dist = v.length
        max_dist = dist if dist > max_dist
      end

      max_scale = [@scale.x, @scale.y, @scale.z].max
      @bounding_sphere_radius = max_dist * max_scale
    end

    def world_bounding_sphere_center
      @position.dup
    end

    private

    def calculate_model_matrix
      translation = Mat4.translation(@position.x, @position.y, @position.z)
      rotation = Mat4.rotation(@rotation.x, @rotation.y, @rotation.z)
      scale = Mat4.scale(@scale.x, @scale.y, @scale.z)

      translation * rotation * scale
    end
  end
end
