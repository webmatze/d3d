module D3D
  module ObjLoader
    class << self
      def load(path)
        vertices = []
        uvs = []
        normals = []
        faces = []

        content = $gtk.read_file(path)
        unless content
          puts "D3D::ObjLoader: Could not read file: #{path}"
          return Mesh.new
        end

        content.each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?('#')

          parts = line.split
          type = parts[0]

          case type
          when 'v'
            x = parts[1].to_f
            y = parts[2].to_f
            z = parts[3].to_f
            vertices << Vec3.new(x, y, z)

          when 'vt'
            u = parts[1].to_f
            v = parts[2].to_f
            uvs << [u, v]

          when 'vn'
            x = parts[1].to_f
            y = parts[2].to_f
            z = parts[3].to_f
            normals << Vec3.new(x, y, z)

          when 'f'
            face_vertices = parts[1..-1]
            parse_face(face_vertices, faces, vertices.length, uvs.length, normals.length)
          end
        end

        Mesh.new(
          vertices: vertices,
          uvs: uvs,
          normals: normals,
          faces: faces
        )
      end

      private

      def parse_face(face_parts, faces, vertex_count, uv_count, normal_count)
        v_indices = []
        uv_indices = []
        n_indices = []

        face_parts.each do |part|
          indices = part.split('/')

          v_idx = indices[0].to_i
          v_idx = v_idx < 0 ? vertex_count + v_idx : v_idx - 1
          v_indices << v_idx

          if indices[1] && !indices[1].empty?
            uv_idx = indices[1].to_i
            uv_idx = uv_idx < 0 ? uv_count + uv_idx : uv_idx - 1
            uv_indices << uv_idx
          else
            uv_indices << nil
          end

          if indices[2] && !indices[2].empty?
            n_idx = indices[2].to_i
            n_idx = n_idx < 0 ? normal_count + n_idx : n_idx - 1
            n_indices << n_idx
          else
            n_indices << nil
          end
        end

        if v_indices.length >= 3
          triangulate_face(v_indices, uv_indices, n_indices, faces)
        end
      end

      def triangulate_face(v_indices, uv_indices, n_indices, faces)
        (1...v_indices.length - 1).each do |i|
          faces << {
            v: [v_indices[0], v_indices[i], v_indices[i + 1]],
            uv: [uv_indices[0], uv_indices[i], uv_indices[i + 1]],
            n: [n_indices[0], n_indices[i], n_indices[i + 1]]
          }
        end
      end
    end
  end
end
