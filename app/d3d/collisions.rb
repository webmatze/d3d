module D3D
  module Collisions
    EPSILON = 1e-6

    class << self
      def ray_triangle(ray_origin, ray_direction, v0, v1, v2)
        edge1 = v1 - v0
        edge2 = v2 - v0
        h = ray_direction.cross(edge2)
        a = edge1.dot(h)

        return nil if a.abs < EPSILON

        f = 1.0 / a
        s = ray_origin - v0
        u = f * s.dot(h)

        return nil if u < 0.0 || u > 1.0

        q = s.cross(edge1)
        v = f * ray_direction.dot(q)

        return nil if v < 0.0 || u + v > 1.0

        t = f * edge2.dot(q)

        return nil if t < EPSILON

        hit_point = ray_origin + ray_direction * t
        { t: t, point: hit_point, u: u, v: v }
      end

      # Scalar Moller-Trumbore over vertices transformed once per call (see
      # transform_vertices). Same operation order as ray_triangle, so results
      # match it bit for bit; Vec3s and the hash are built only for the hit.
      def ray_model(ray_origin, ray_direction, model)
        return nil unless model.visible

        mesh = model.mesh
        transform_vertices(mesh.vertices, model.get_model_matrix)
        wx = @wx
        wy = @wy
        wz = @wz

        ox = ray_origin.x
        oy = ray_origin.y
        oz = ray_origin.z
        dx = ray_direction.x
        dy = ray_direction.y
        dz = ray_direction.z

        best_t = nil
        best_u = nil
        best_v = nil
        best_idx = nil
        best_i0 = nil
        best_i1 = nil
        best_i2 = nil

        faces = mesh.faces
        face_count = faces.length
        face_idx = 0
        while face_idx < face_count
          fv = faces[face_idx][:v]
          i0 = fv[0]
          i1 = fv[1]
          i2 = fv[2]
          v0x = wx[i0]
          v0y = wy[i0]
          v0z = wz[i0]

          e1x = wx[i1] - v0x
          e1y = wy[i1] - v0y
          e1z = wz[i1] - v0z
          e2x = wx[i2] - v0x
          e2y = wy[i2] - v0y
          e2z = wz[i2] - v0z

          hx = dy * e2z - dz * e2y
          hy = dz * e2x - dx * e2z
          hz = dx * e2y - dy * e2x
          a = e1x * hx + e1y * hy + e1z * hz

          if a.abs >= EPSILON
            f = 1.0 / a
            sx = ox - v0x
            sy = oy - v0y
            sz = oz - v0z
            u = f * (sx * hx + sy * hy + sz * hz)

            unless u < 0.0 || u > 1.0
              qx = sy * e1z - sz * e1y
              qy = sz * e1x - sx * e1z
              qz = sx * e1y - sy * e1x
              v = f * (dx * qx + dy * qy + dz * qz)

              unless v < 0.0 || u + v > 1.0
                t = f * (e2x * qx + e2y * qy + e2z * qz)

                if t >= EPSILON && (best_t.nil? || t < best_t)
                  best_t = t
                  best_u = u
                  best_v = v
                  best_idx = face_idx
                  best_i0 = i0
                  best_i1 = i1
                  best_i2 = i2
                end
              end
            end
          end

          face_idx += 1
        end

        return nil if best_t.nil?

        {
          t: best_t,
          point: ray_origin + ray_direction * best_t,
          u: best_u,
          v: best_v,
          model: model,
          face_index: best_idx,
          v0: Vec3.new(wx[best_i0], wy[best_i0], wz[best_i0]),
          v1: Vec3.new(wx[best_i1], wy[best_i1], wz[best_i1]),
          v2: Vec3.new(wx[best_i2], wy[best_i2], wz[best_i2])
        }
      end

      def ray_models(ray_origin, ray_direction, models)
        closest_hit = nil

        models.each do |model|
          hit = ray_model(ray_origin, ray_direction, model)
          next unless hit

          if closest_hit.nil? || hit[:t] < closest_hit[:t]
            closest_hit = hit
          end
        end

        closest_hit
      end

      # Scalar closest_point_on_triangle / closest_point_on_segment over
      # vertices transformed once per call; same operation order as the Vec3
      # versions. Returns the first face within the radius, as before.
      def sphere_model(sphere_center, sphere_radius, model)
        return nil unless model.visible

        mesh = model.mesh
        transform_vertices(mesh.vertices, model.get_model_matrix)
        wx = @wx
        wy = @wy
        wz = @wz

        px = sphere_center.x
        py = sphere_center.y
        pz = sphere_center.z

        faces = mesh.faces
        face_count = faces.length
        face_idx = 0
        while face_idx < face_count
          fv = faces[face_idx][:v]
          i0 = fv[0]
          i1 = fv[1]
          i2 = fv[2]
          v0x = wx[i0]
          v0y = wy[i0]
          v0z = wz[i0]

          e0x = wx[i1] - v0x
          e0y = wy[i1] - v0y
          e0z = wz[i1] - v0z
          e1x = wx[i2] - v0x
          e1y = wy[i2] - v0y
          e1z = wz[i2] - v0z
          tpx = px - v0x
          tpy = py - v0y
          tpz = pz - v0z

          d00 = e0x * e0x + e0y * e0y + e0z * e0z
          d01 = e0x * e1x + e0y * e1y + e0z * e1z
          d11 = e1x * e1x + e1y * e1y + e1z * e1z
          d20 = tpx * e0x + tpy * e0y + tpz * e0z
          d21 = tpx * e1x + tpy * e1y + tpz * e1z

          denom = d00 * d11 - d01 * d01
          v = (d11 * d20 - d01 * d21) / denom
          w = (d00 * d21 - d01 * d20) / denom
          u = 1.0 - v - w

          if u >= 0 && v >= 0 && w >= 0
            cx = v0x + e0x * v + e1x * w
            cy = v0y + e0y * v + e1y * w
            cz = v0z + e0z * v + e1z * w
          else
            if u < 0
              ai = i1
              bi = i2
            elsif v < 0
              ai = i0
              bi = i2
            else
              ai = i0
              bi = i1
            end
            ax = wx[ai]
            ay = wy[ai]
            az = wz[ai]
            abx = wx[bi] - ax
            aby = wy[bi] - ay
            abz = wz[bi] - az
            st = ((px - ax) * abx + (py - ay) * aby + (pz - az) * abz) /
                 (abx * abx + aby * aby + abz * abz)
            if st < 0
              st = 0
            elsif st > 1
              st = 1
            elsif st != st
              st = [[st, 0].max, 1].min # NaN: raise exactly like before
            end
            cx = ax + abx * st
            cy = ay + aby * st
            cz = az + abz * st
          end

          ddx = px - cx
          ddy = py - cy
          ddz = pz - cz
          distance = Math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)

          if distance <= sphere_radius
            closest_point = Vec3.new(cx, cy, cz)
            normal = (sphere_center - closest_point).normalize
            penetration = sphere_radius - distance
            return {
              point: closest_point,
              normal: normal,
              penetration: penetration,
              model: model
            }
          end

          face_idx += 1
        end

        nil
      end

      def sphere_models(sphere_center, sphere_radius, models)
        collisions = []

        models.each do |model|
          collision = sphere_model(sphere_center, sphere_radius, model)
          collisions << collision if collision
        end

        collisions
      end

      def point_in_triangle(point, v0, v1, v2)
        edge0 = v1 - v0
        edge1 = v2 - v0
        edge2 = point - v0

        dot00 = edge0.dot(edge0)
        dot01 = edge0.dot(edge1)
        dot02 = edge0.dot(edge2)
        dot11 = edge1.dot(edge1)
        dot12 = edge1.dot(edge2)

        inv_denom = 1.0 / (dot00 * dot11 - dot01 * dot01)
        u = (dot11 * dot02 - dot01 * dot12) * inv_denom
        v = (dot00 * dot12 - dot01 * dot02) * inv_denom

        u >= 0 && v >= 0 && u + v <= 1
      end

      def aabb_intersects?(min1, max1, min2, max2)
        min1.x <= max2.x && max1.x >= min2.x &&
        min1.y <= max2.y && max1.y >= min2.y &&
        min1.z <= max2.z && max1.z >= min2.z
      end

      def sphere_intersects_sphere?(center1, radius1, center2, radius2)
        distance = center1.distance_to(center2)
        distance <= radius1 + radius2
      end

      private

      # Transforms every mesh vertex once into the reused scratch arrays
      # @wx/@wy/@wz, with Mat4#transform_point's exact arithmetic.
      def transform_vertices(vertices, matrix)
        d = matrix.data
        m0 = d[0]
        m1 = d[1]
        m2 = d[2]
        m3 = d[3]
        m4 = d[4]
        m5 = d[5]
        m6 = d[6]
        m7 = d[7]
        m8 = d[8]
        m9 = d[9]
        m10 = d[10]
        m11 = d[11]
        m12 = d[12]
        m13 = d[13]
        m14 = d[14]
        m15 = d[15]
        wx = (@wx ||= [])
        wy = (@wy ||= [])
        wz = (@wz ||= [])

        n = vertices.length
        i = 0
        while i < n
          vert = vertices[i]
          vx = vert.x
          vy = vert.y
          vz = vert.z
          x = (m0 * vx + m1 * vy + m2 * vz + m3 * 1.0).to_f
          y = (m4 * vx + m5 * vy + m6 * vz + m7 * 1.0).to_f
          z = (m8 * vx + m9 * vy + m10 * vz + m11 * 1.0).to_f
          w = m12 * vx + m13 * vy + m14 * vz + m15 * 1.0
          if w != 0 && w != 1
            x /= w
            y /= w
            z /= w
          end
          wx[i] = x
          wy[i] = y
          wz[i] = z
          i += 1
        end
      end

      def closest_point_on_triangle(point, v0, v1, v2)
        edge0 = v1 - v0
        edge1 = v2 - v0
        v0_to_point = point - v0

        d00 = edge0.dot(edge0)
        d01 = edge0.dot(edge1)
        d11 = edge1.dot(edge1)
        d20 = v0_to_point.dot(edge0)
        d21 = v0_to_point.dot(edge1)

        denom = d00 * d11 - d01 * d01
        v = (d11 * d20 - d01 * d21) / denom
        w = (d00 * d21 - d01 * d20) / denom
        u = 1.0 - v - w

        if u >= 0 && v >= 0 && w >= 0
          return v0 + edge0 * v + edge1 * w
        end

        if u < 0
          return closest_point_on_segment(point, v1, v2)
        elsif v < 0
          return closest_point_on_segment(point, v0, v2)
        else
          return closest_point_on_segment(point, v0, v1)
        end
      end

      def closest_point_on_segment(point, a, b)
        ab = b - a
        t = (point - a).dot(ab) / ab.dot(ab)
        t = [[t, 0].max, 1].min
        a + ab * t
      end
    end
  end
end
