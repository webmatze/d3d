module D3D
  module Renderer
    # Pre-computed constants for screen conversion
    HALF_WIDTH = SCREEN_WIDTH * 0.5
    HALF_HEIGHT = SCREEN_HEIGHT * 0.5
    # Pixel size of the voxel block textures (UVs are normalized 0..1)
    VOXEL_TEX_SIZE = 16
    # Triangles entirely beyond this NDC range are skipped
    NDC_MARGIN = 4.0

    class << self
      # light: optional { direction: [x, y, z] (pointing towards the light),
      #   ambient: 0.35 }. Flat shades every triangle by its face normal.
      # fog: optional { near:, far:, color: [r, g, b] }. Blends triangles
      #   towards color with view distance and skips triangles beyond far.
      #   Textures are tinted multiplicatively, so on textured faces the blend
      #   is only exact towards dark fog colours.
      def render(camera, models, lights: nil, light: nil, fog: nil)
        triangles = []

        view_matrix = camera.get_view_matrix
        projection_matrix = camera.get_projection_matrix
        vp_matrix = projection_matrix * view_matrix

        # Camera position for frustum culling
        cam_pos = camera.position
        cam_forward = camera.forward
        near = camera.near
        lit = light_setup(light)
        fogs = fog_setup(fog)

        models.each do |model|
          next unless model.visible

          # Model-level frustum culling: skip models behind camera
          if model_behind_camera?(model, cam_pos, cam_forward)
            next
          end

          model_matrix = model.get_model_matrix
          mvp_matrix = vp_matrix * model_matrix

          render_model_optimized(triangles, model, model_matrix.data, mvp_matrix.data,
                                 cam_pos, near, lit, fogs)
        end

        DepthSort.triangles(triangles)
      end

      # Takes the same light:/fog: options as render.
      def render_voxel_world(camera, voxel_world, light: nil, fog: nil)
        mesh_data = voxel_world.build_mesh
        return [] if mesh_data.nil? || mesh_data[:faces].empty?

        # Flat per-mesh arrays (unique vertices, per-face data); rebuilt only
        # when build_mesh hands out a new mesh Hash
        cache = @voxel_cache
        cache = voxel_cache_build(mesh_data) unless cache && cache[0].equal?(mesh_data)
        ux = cache[1]
        uy = cache[2]
        uz = cache[3]
        cx = cache[4]
        cy = cache[5]
        cz = cache[6]
        cw = cache[7]
        stamp = cache[8]
        fi0 = cache[9]
        fi1 = cache[10]
        fi2 = cache[11]
        fvx = cache[12]
        fvy = cache[13]
        fvz = cache[14]
        fnx = cache[15]
        fny = cache[16]
        fnz = cache[17]
        fr = cache[18]
        fg = cache[19]
        fb = cache[20]
        fa = cache[21]
        fpath = cache[22]
        fsx0 = cache[23]
        fsy0 = cache[24]
        fsx1 = cache[25]
        fsy1 = cache[26]
        fsx2 = cache[27]
        fsy2 = cache[28]
        face_count = fi0.size
        frame = cache[29] + 1
        cache[29] = frame

        triangles = []

        view_matrix = camera.get_view_matrix
        projection_matrix = camera.get_projection_matrix
        mvp_matrix = projection_matrix * view_matrix
        mvp = mvp_matrix.data
        m0 = mvp[0]
        m1 = mvp[1]
        m2 = mvp[2]
        m3 = mvp[3]
        m4 = mvp[4]
        m5 = mvp[5]
        m6 = mvp[6]
        m7 = mvp[7]
        m8 = mvp[8]
        m9 = mvp[9]
        m10 = mvp[10]
        m11 = mvp[11]
        m12 = mvp[12]
        m13 = mvp[13]
        m14 = mvp[14]
        m15 = mvp[15]

        cam_pos = camera.position
        px = cam_pos.x
        py = cam_pos.y
        pz = cam_pos.z
        near = camera.near
        lit = light_setup(light)
        fogs = fog_setup(fog)
        fog_far = fogs ? fogs[1] : nil
        shaded = lit || fogs
        if lit
          l0 = lit[0]
          l1 = lit[1]
          l2 = lit[2]
          l3 = lit[3]
        end
        if fogs
          fog_near = fogs[0]
          fog_r = fogs[2]
          fog_g = fogs[3]
          fog_b = fogs[4]
          fog_inv = fogs[5]
        end
        margin = NDC_MARGIN
        neg_margin = -margin
        hw = HALF_WIDTH
        hh = HALF_HEIGHT

        # With the optional extension loaded the face loop below runs in C
        # (D3D::Ext.render_voxels mirrors it exactly). Its geometry handle
        # lives in the render cache; colours, paths and source coordinates
        # are passed as the cache's Ruby arrays so they keep their values.
        if Native.enabled?
          cache[30] ||= Ext.pack_mesh(ux, uy, uz, fi0, fi1, fi2, fvx, fvy, fvz, fnx, fny, fnz)
          Ext.render_voxels(triangles, cache[30], mvp,
                            [fr, fg, fb, fa, fpath, fsx0, fsy0, fsx1, fsy1, fsx2, fsy2], [
                              px, py, pz, near, fog_far, hw, hh, margin,
                              lit ? true : false, l0, l1, l2, l3,
                              fogs ? true : false, fog_near, fog_r, fog_g, fog_b, fog_inv
                            ])
          return DepthSort.triangles(triangles)
        end

        fi = 0
        while fi < face_count
          nx = fnx[fi]
          ny = fny[fi]
          nz = fnz[fi]
          # Back face culling in world space, before any projection work
          if (px - fvx[fi]) * nx + (py - fvy[fi]) * ny + (pz - fvz[fi]) * nz <= 0
            fi += 1
            next
          end

          # Each unique vertex is transformed at most once per frame
          i0 = fi0[fi]
          if stamp[i0] != frame
            x = ux[i0]
            y = uy[i0]
            z = uz[i0]
            cx[i0] = m0 * x + m1 * y + m2 * z + m3
            cy[i0] = m4 * x + m5 * y + m6 * z + m7
            cz[i0] = m8 * x + m9 * y + m10 * z + m11
            cw[i0] = m12 * x + m13 * y + m14 * z + m15
            stamp[i0] = frame
          end
          i1 = fi1[fi]
          if stamp[i1] != frame
            x = ux[i1]
            y = uy[i1]
            z = uz[i1]
            cx[i1] = m0 * x + m1 * y + m2 * z + m3
            cy[i1] = m4 * x + m5 * y + m6 * z + m7
            cz[i1] = m8 * x + m9 * y + m10 * z + m11
            cw[i1] = m12 * x + m13 * y + m14 * z + m15
            stamp[i1] = frame
          end
          i2 = fi2[fi]
          if stamp[i2] != frame
            x = ux[i2]
            y = uy[i2]
            z = uz[i2]
            cx[i2] = m0 * x + m1 * y + m2 * z + m3
            cy[i2] = m4 * x + m5 * y + m6 * z + m7
            cz[i2] = m8 * x + m9 * y + m10 * z + m11
            cw[i2] = m12 * x + m13 * y + m14 * z + m15
            stamp[i2] = frame
          end

          w0 = cw[i0]
          w1 = cw[i1]
          w2 = cw[i2]

          # Skip triangles entirely behind the near plane or beyond the fog
          if (w0 < near && w1 < near && w2 < near) ||
             (fog_far && w0 > fog_far && w1 > fog_far && w2 > fog_far)
            fi += 1
            next
          end

          r = fr[fi]
          g = fg[fi]
          b = fb[fi]
          if shaded
            # Flat Lambert light and distance fog, inline (no [r, g, b] Array)
            if lit
              d = nx * l0 + ny * l1 + nz * l2
              k = l3 + (1.0 - l3) * (d > 0 ? d : 0.0)
              r *= k
              g *= k
              b *= k
            end
            if fogs
              f = ((w0 + w1 + w2) * 0.333333 - fog_near) * fog_inv
              if f > 0
                f = 1.0 if f > 1.0
                r += (fog_r - r) * f
                g += (fog_g - g) * f
                b += (fog_b - b) * f
              end
            end
          end

          clip0x = cx[i0]
          clip0y = cy[i0]
          clip0z = cz[i0]
          clip1x = cx[i1]
          clip1y = cy[i1]
          clip1z = cz[i1]
          clip2x = cx[i2]
          clip2y = cy[i2]
          clip2z = cz[i2]
          path = fpath[fi]

          # Triangles crossing the near plane are clipped instead of dropped
          if w0 < near || w1 < near || w2 < near
            if path
              emit_clipped(triangles, [
                [clip0x, clip0y, clip0z, w0, fsx0[fi], fsy0[fi]],
                [clip1x, clip1y, clip1z, w1, fsx1[fi], fsy1[fi]],
                [clip2x, clip2y, clip2z, w2, fsx2[fi], fsy2[fi]]
              ], near, r, g, b, fa[fi], path, false)
            else
              emit_clipped(triangles, [
                [clip0x, clip0y, clip0z, w0, 0, 0],
                [clip1x, clip1y, clip1z, w1, 0, 0],
                [clip2x, clip2y, clip2z, w2, 0, 0]
              ], near, r, g, b, fa[fi], nil, true)
            end
            fi += 1
            next
          end

          # Inline perspective divide (no Vec3 allocation)
          inv_w0 = 1.0 / w0
          inv_w1 = 1.0 / w1
          inv_w2 = 1.0 / w2

          ndc0x = clip0x * inv_w0
          ndc0y = clip0y * inv_w0
          ndc0z = clip0z * inv_w0
          ndc1x = clip1x * inv_w1
          ndc1y = clip1y * inv_w1
          ndc1z = clip1z * inv_w1
          ndc2x = clip2x * inv_w2
          ndc2y = clip2y * inv_w2
          ndc2z = clip2z * inv_w2

          # Inline frustum culling
          if (ndc0z > 1.0 && ndc1z > 1.0 && ndc2z > 1.0) ||
             (ndc0x < neg_margin && ndc1x < neg_margin && ndc2x < neg_margin) ||
             (ndc0x > margin && ndc1x > margin && ndc2x > margin) ||
             (ndc0y < neg_margin && ndc1y < neg_margin && ndc2y < neg_margin) ||
             (ndc0y > margin && ndc1y > margin && ndc2y > margin)
            fi += 1
            next
          end

          # Textured faces map their UVs (normalized 0-1 -> texture pixels,
          # pre-multiplied in the cache). Solid colours are :solid sprites,
          # which DragonRuby only draws as triangles when source coordinates
          # are set. One hash literal with all keys: growing the hash key by
          # key costs ~10% of the render.
          if path
            sx0 = fsx0[fi]
            sy0 = fsy0[fi]
            sx1 = fsx1[fi]
            sy1 = fsy1[fi]
            sx2 = fsx2[fi]
            sy2 = fsy2[fi]
          else
            path = :solid
            sx0 = 0
            sy0 = 0
            sx1 = 1
            sy1 = 0
            sx2 = 0
            sy2 = 1
          end

          triangles << {
            x: (ndc0x + 1.0) * hw, y: (ndc0y + 1.0) * hh,
            x2: (ndc1x + 1.0) * hw, y2: (ndc1y + 1.0) * hh,
            x3: (ndc2x + 1.0) * hw, y3: (ndc2y + 1.0) * hh,
            z_depth: (clip0z + clip1z + clip2z) * 0.333333,
            r: r, g: g, b: b, a: fa[fi],
            path: path,
            source_x: sx0, source_y: sy0,
            source_x2: sx1, source_y2: sy1,
            source_x3: sx2, source_y3: sy2
          }
          fi += 1
        end

        DepthSort.triangles(triangles)
      end

      # Builds the flat render cache for a voxel mesh Hash: deduplicated
      # vertex coordinates, reusable clip-space arrays with a frame stamp,
      # per-face unique vertex indices, first corner, normal, colour, texture
      # (nil for solid faces) and pre-multiplied source coordinates.
      def voxel_cache_build(mesh_data)
        vertices = mesh_data[:vertices]
        faces = mesh_data[:faces]
        ux = []
        uy = []
        uz = []
        index_of = {}
        remap = Array.new(vertices.size)
        vertices.each_with_index do |v, i|
          key = voxel_vertex_key(v[0], v[1], v[2])
          u = index_of[key]
          unless u
            u = ux.size
            ux << v[0]
            uy << v[1]
            uz << v[2]
            index_of[key] = u
          end
          remap[i] = u
        end

        count = ux.size
        cache = [mesh_data, ux, uy, uz,
                 Array.new(count, 0.0), Array.new(count, 0.0),
                 Array.new(count, 0.0), Array.new(count, 0.0),
                 Array.new(count, -1)]
        20.times { cache << [] }
        cache << 0
        cache << nil # native handle (D3D::Ext.pack_mesh), built on first use

        ts = VOXEL_TEX_SIZE
        faces.each do |face|
          vi = face[:v]
          v0 = vertices[vi[0]]
          n = face[:n]
          uv = face[:texture] && face[:uv]
          cache[9] << remap[vi[0]]
          cache[10] << remap[vi[1]]
          cache[11] << remap[vi[2]]
          cache[12] << v0[0]
          cache[13] << v0[1]
          cache[14] << v0[2]
          cache[15] << n[0]
          cache[16] << n[1]
          cache[17] << n[2]
          cache[18] << face[:r]
          cache[19] << face[:g]
          cache[20] << face[:b]
          cache[21] << face[:a]
          cache[22] << (uv ? face[:texture] : nil)
          cache[23] << (uv ? uv[0][0] * ts : 0)
          cache[24] << (uv ? uv[0][1] * ts : 0)
          cache[25] << (uv ? uv[1][0] * ts : 0)
          cache[26] << (uv ? uv[1][1] * ts : 0)
          cache[27] << (uv ? uv[2][0] * ts : 0)
          cache[28] << (uv ? uv[2][1] * ts : 0)
        end

        @voxel_cache = cache
      end

      # Hash key for vertex deduplication. Keeps -0.0 apart from 0.0 so
      # merged vertices always transform to identical clip coordinates.
      def voxel_vertex_key(x, y, z)
        key = [x, y, z]
        key << :nx if x.is_a?(Float) && x == 0 && 1.0 / x < 0
        key << :ny if y.is_a?(Float) && y == 0 && 1.0 / y < 0
        key << :nz if z.is_a?(Float) && z == 0 && 1.0 / z < 0
        key
      end

      # Project a world-space point to screen coordinates.
      # Returns [screen_x, screen_y] or nil if the point is behind the camera.
      def project_point(camera, x, y, z)
        vp = (camera.get_projection_matrix * camera.get_view_matrix).data

        clip_x = vp[0] * x + vp[1] * y + vp[2] * z + vp[3]
        clip_y = vp[4] * x + vp[5] * y + vp[6] * z + vp[7]
        w = vp[12] * x + vp[13] * y + vp[14] * z + vp[15]

        return nil if w <= 0.01

        inv_w = 1.0 / w
        [(clip_x * inv_w + 1.0) * HALF_WIDTH, (clip_y * inv_w + 1.0) * HALF_HEIGHT]
      end

      # Clips a triangle crossing the near plane (w = near) against it and
      # emits the resulting polygon as a triangle fan. Each poly entry is
      # [clip_x, clip_y, clip_z, w, u, v]; u/v are interpolated with it.
      def emit_clipped(triangles, poly, near, r, g, b, a, path, solid)
        out = []
        n = poly.size
        n.times do |i|
          p = poly[i]
          q = poly[(i + 1) % n]
          p_in = p[3] >= near
          q_in = q[3] >= near
          out << p if p_in
          next if p_in == q_in

          t = (near - p[3]) / (q[3] - p[3])
          out << [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t,
                  p[2] + (q[2] - p[2]) * t, near,
                  p[4] + (q[4] - p[4]) * t, p[5] + (q[5] - p[5]) * t]
        end
        return if out.size < 3

        pts = out.map do |p|
          inv_w = 1.0 / p[3]
          [(p[0] * inv_w + 1.0) * HALF_WIDTH, (p[1] * inv_w + 1.0) * HALF_HEIGHT, p[2], p[4], p[5]]
        end

        a0 = pts[0]
        (1...pts.size - 1).each do |k|
          b1 = pts[k]
          c1 = pts[k + 1]
          triangle = {
            x: a0[0], y: a0[1],
            x2: b1[0], y2: b1[1],
            x3: c1[0], y3: c1[1],
            z_depth: (a0[2] + b1[2] + c1[2]) * 0.333333,
            r: r, g: g, b: b, a: a
          }
          if solid
            triangle[:path] = :solid
            triangle[:source_x] = 0
            triangle[:source_y] = 0
            triangle[:source_x2] = 1
            triangle[:source_y2] = 0
            triangle[:source_x3] = 0
            triangle[:source_y3] = 1
          end
          if path
            triangle[:path] = path
            triangle[:source_x] = a0[3]
            triangle[:source_y] = a0[4]
            triangle[:source_x2] = b1[3]
            triangle[:source_y2] = b1[4]
            triangle[:source_x3] = c1[3]
            triangle[:source_y3] = c1[4]
          end
          triangles << triangle
        end
      end

      # Pixel size [w, h] of a model's texture: model.texture_size (Integer
      # or [w, h]) or, in DragonRuby, the image size (cached per path). nil
      # when unknown (e.g. CRuby without texture_size): uvs are then emitted
      # unscaled.
      def texture_size_of(model)
        size = model.texture_size
        return size.is_a?(Array) ? size : [size, size] if size

        path = model.texture
        return nil unless path

        sizes = (@texture_sizes ||= {})
        return sizes[path] if sizes.key?(path)

        sizes[path] = detect_texture_size(path)
      end

      private

      def detect_texture_size(path)
        return nil unless $gtk

        $gtk.calcspritebox(path)
      rescue StandardError
        nil
      end

      # [lx, ly, lz, ambient] with a normalized direction, or nil.
      def light_setup(light)
        return nil unless light

        dx, dy, dz = light[:direction] || [0.4, 1.0, 0.3]
        len = Math.sqrt(dx * dx + dy * dy + dz * dz)
        [dx / len, dy / len, dz / len, light[:ambient] || 0.35]
      end

      # [near, far, r, g, b, 1 / (far - near)], or nil.
      def fog_setup(fog)
        return nil unless fog

        near = fog[:near].to_f
        far = fog[:far].to_f
        color = fog[:color] || [0, 0, 0]
        [near, far, color[0], color[1], color[2], 1.0 / (far - near)]
      end

      # Inverse of the upper 3x3 of a row-major 4x4 matrix as 9 row-major
      # values, or nil if it is singular (e.g. a zero scale).
      def invert3(m)
        a = m[0]
        b = m[1]
        c = m[2]
        d = m[4]
        e = m[5]
        f = m[6]
        g = m[8]
        h = m[9]
        i = m[10]
        det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        return nil if det.abs < 1e-12

        s = 1.0 / det
        [(e * i - f * h) * s, (c * h - b * i) * s, (b * f - c * e) * s,
         (f * g - d * i) * s, (a * i - c * g) * s, (c * d - a * f) * s,
         (d * h - e * g) * s, (b * g - a * h) * s, (a * e - b * d) * s]
      end

      def model_behind_camera?(model, cam_pos, cam_forward)
        # Vector from camera to model center
        dx = model.position.x - cam_pos.x
        dy = model.position.y - cam_pos.y
        dz = model.position.z - cam_pos.z

        # Dot product with camera forward
        dot = dx * cam_forward.x + dy * cam_forward.y + dz * cam_forward.z

        # If negative, model is behind camera (with margin for model size)
        dot < -5.0
      end

      def render_model_optimized(triangles, model, m, mvp, cam_pos, near, lit, fogs)
        mesh = model.mesh
        vertices = mesh.vertices
        faces = mesh.faces
        cull = mesh.face_cull_data
        f_i0 = cull[0]
        f_i1 = cull[1]
        f_i2 = cull[2]
        f_v0x = cull[3]
        f_v0y = cull[4]
        f_v0z = cull[5]
        f_nx = cull[6]
        f_ny = cull[7]
        f_nz = cull[8]
        uvs = mesh.uvs
        texture = model.texture
        if texture
          tex_size = texture_size_of(model)
          tex_w = tex_size && tex_size[0]
          tex_h = tex_size && tex_size[1]
        end
        color = model.color
        color_r = color[:r]
        color_g = color[:g]
        color_b = color[:b]
        color_a = color[:a]
        fog_far = fogs ? fogs[1] : nil

        # The inverse model matrix brings the camera into model space for back
        # face culling, and (transposed) face normals into world space.
        inv = invert3(m)
        return unless inv

        tx = cam_pos.x - m[3]
        ty = cam_pos.y - m[7]
        tz = cam_pos.z - m[11]
        cx = inv[0] * tx + inv[1] * ty + inv[2] * tz
        cy = inv[3] * tx + inv[4] * ty + inv[5] * tz
        cz = inv[6] * tx + inv[7] * ty + inv[8] * tz

        # Lighting needs n_world . L with n_world = inv^T n / |inv^T n|. Since
        # (inv^T n) . L = n . (inv L), the light goes into model space once
        # (lmx, lmy, lmz). |inv^T n|^2 = n . (inv inv^T) n; with a uniform
        # scale inv inv^T is c * I and, as face normals are unit length (or
        # zero), the length is sqrt(c) for every face, so no per-face sqrt.
        if lit
          lx = lit[0]
          ly = lit[1]
          lz = lit[2]
          ambient = lit[3]
          diffuse = 1.0 - ambient
          lmx = inv[0] * lx + inv[1] * ly + inv[2] * lz
          lmy = inv[3] * lx + inv[4] * ly + inv[5] * lz
          lmz = inv[6] * lx + inv[7] * ly + inv[8] * lz
          g00 = inv[0] * inv[0] + inv[1] * inv[1] + inv[2] * inv[2]
          g11 = inv[3] * inv[3] + inv[4] * inv[4] + inv[5] * inv[5]
          g22 = inv[6] * inv[6] + inv[7] * inv[7] + inv[8] * inv[8]
          g01 = inv[0] * inv[3] + inv[1] * inv[4] + inv[2] * inv[5]
          g02 = inv[0] * inv[6] + inv[1] * inv[7] + inv[2] * inv[8]
          g12 = inv[3] * inv[6] + inv[4] * inv[7] + inv[5] * inv[8]
          tol = g00 * 1e-9
          if (g00 - g11).abs <= tol && (g00 - g22).abs <= tol &&
             g01.abs <= tol && g02.abs <= tol && g12.abs <= tol
            light_scale = 1.0 / Math.sqrt(g00)
          end
        end
        if fogs
          fog_near = fogs[0]
          fog_r = fogs[2]
          fog_g = fogs[3]
          fog_b = fogs[4]
          fog_inv = fogs[5]
        end

        # The loop below runs in C when the optional extension is loaded
        # (D3D::Ext.render_model mirrors it exactly, textures included).
        if Native.enabled?
          Ext.render_model(triangles, mesh.native_data, mvp, inv, [
            cx, cy, cz, near, fog_far, HALF_WIDTH, HALF_HEIGHT, NDC_MARGIN,
            lit ? true : false, lmx, lmy, lmz, ambient, diffuse, light_scale,
            fogs ? true : false, fog_near, fog_r, fog_g, fog_b, fog_inv,
            color_r, color_g, color_b, color_a
          ], texture, uvs, tex_size)
          return
        end

        # Vertices are transformed lazily, only when a front face uses them
        # (about half of a closed mesh's vertices belong only to back faces),
        # and their perspective divide and screen position are cached, since
        # faces share vertices (up to 6 per sphere vertex). A cache entry is
        # valid for this model pass when its stamp equals the pass counter;
        # the arrays are reused across models and frames. Clip values are
        # always cached (the near plane clipping path reads them), NDC and
        # screen values only for vertices not behind the near plane, the only
        # ones that reach the projection code.
        xs = (@clip_x ||= [])
        ys = (@clip_y ||= [])
        zs = (@clip_z ||= [])
        ws = (@clip_w ||= [])
        ndx = (@ndc_x ||= [])
        ndy = (@ndc_y ||= [])
        ndz = (@ndc_z ||= [])
        scx = (@screen_x ||= [])
        scy = (@screen_y ||= [])
        st = (@vert_stamp ||= [])
        pass = (@vert_pass = (@vert_pass || 0) + 1)
        half_w = HALF_WIDTH
        half_h = HALF_HEIGHT
        m0 = mvp[0]
        m1 = mvp[1]
        m2 = mvp[2]
        m3 = mvp[3]
        m4 = mvp[4]
        m5 = mvp[5]
        m6 = mvp[6]
        m7 = mvp[7]
        m8 = mvp[8]
        m9 = mvp[9]
        m10 = mvp[10]
        m11 = mvp[11]
        m12 = mvp[12]
        m13 = mvp[13]
        m14 = mvp[14]
        m15 = mvp[15]

        margin = NDC_MARGIN
        neg_margin = -NDC_MARGIN
        nf = faces.length
        fi = -1
        while (fi += 1) < nf
          # Back face culling in model space, before any projection work
          nx = f_nx[fi]
          ny = f_ny[fi]
          nz = f_nz[fi]
          next if (cx - f_v0x[fi]) * nx + (cy - f_v0y[fi]) * ny + (cz - f_v0z[fi]) * nz <= 0

          face = faces[fi]
          i0 = f_i0[fi]
          if st[i0] != pass
            v = vertices[i0]
            x = v.x
            y = v.y
            z = v.z
            px = xs[i0] = m0 * x + m1 * y + m2 * z + m3
            py = ys[i0] = m4 * x + m5 * y + m6 * z + m7
            pz = zs[i0] = m8 * x + m9 * y + m10 * z + m11
            pw = ws[i0] = m12 * x + m13 * y + m14 * z + m15
            unless pw < near
              iw = 1.0 / pw
              qx = ndx[i0] = px * iw
              qy = ndy[i0] = py * iw
              ndz[i0] = pz * iw
              scx[i0] = (qx + 1.0) * half_w
              scy[i0] = (qy + 1.0) * half_h
            end
            st[i0] = pass
          end
          i1 = f_i1[fi]
          if st[i1] != pass
            v = vertices[i1]
            x = v.x
            y = v.y
            z = v.z
            px = xs[i1] = m0 * x + m1 * y + m2 * z + m3
            py = ys[i1] = m4 * x + m5 * y + m6 * z + m7
            pz = zs[i1] = m8 * x + m9 * y + m10 * z + m11
            pw = ws[i1] = m12 * x + m13 * y + m14 * z + m15
            unless pw < near
              iw = 1.0 / pw
              qx = ndx[i1] = px * iw
              qy = ndy[i1] = py * iw
              ndz[i1] = pz * iw
              scx[i1] = (qx + 1.0) * half_w
              scy[i1] = (qy + 1.0) * half_h
            end
            st[i1] = pass
          end
          i2 = f_i2[fi]
          if st[i2] != pass
            v = vertices[i2]
            x = v.x
            y = v.y
            z = v.z
            px = xs[i2] = m0 * x + m1 * y + m2 * z + m3
            py = ys[i2] = m4 * x + m5 * y + m6 * z + m7
            pz = zs[i2] = m8 * x + m9 * y + m10 * z + m11
            pw = ws[i2] = m12 * x + m13 * y + m14 * z + m15
            unless pw < near
              iw = 1.0 / pw
              qx = ndx[i2] = px * iw
              qy = ndy[i2] = py * iw
              ndz[i2] = pz * iw
              scx[i2] = (qx + 1.0) * half_w
              scy[i2] = (qy + 1.0) * half_h
            end
            st[i2] = pass
          end
          w0 = ws[i0]
          w1 = ws[i1]
          w2 = ws[i2]

          # Skip triangles entirely behind the near plane or beyond the fog
          next if w0 < near && w1 < near && w2 < near
          next if fog_far && w0 > fog_far && w1 > fog_far && w2 > fog_far

          uv0 = uv1 = uv2 = nil
          if texture && face[:uv] && uvs.length > 0
            uv_indices = face[:uv]
            uv0_idx = uv_indices[0]
            uv1_idx = uv_indices[1]
            uv2_idx = uv_indices[2]

            if uv0_idx && uv0_idx >= 0 && uv0_idx < uvs.length &&
               uv1_idx && uv1_idx >= 0 && uv1_idx < uvs.length &&
               uv2_idx && uv2_idx >= 0 && uv2_idx < uvs.length
              uv0 = uvs[uv0_idx]
              uv1 = uvs[uv1_idx]
              uv2 = uvs[uv2_idx]
            end
          end
          # Texture pixels from the 0..1 uvs (unscaled when the size is unknown)
          if uv0
            if tex_w
              su0 = uv0[0] * tex_w
              sv0 = uv0[1] * tex_h
              su1 = uv1[0] * tex_w
              sv1 = uv1[1] * tex_h
              su2 = uv2[0] * tex_w
              sv2 = uv2[1] * tex_h
            else
              su0 = uv0[0]
              sv0 = uv0[1]
              su1 = uv1[0]
              sv1 = uv1[1]
              su2 = uv2[0]
              sv2 = uv2[1]
            end
          end

          r = color_r
          g = color_g
          b = color_b
          # Flat Lambert light and distance fog, inline (no [r, g, b] Array)
          if lit
            d = nx * lmx + ny * lmy + nz * lmz
            if light_scale
              d *= light_scale
            else
              # Non-uniform scale: world normal length per face
              wx = inv[0] * nx + inv[3] * ny + inv[6] * nz
              wy = inv[1] * nx + inv[4] * ny + inv[7] * nz
              wz = inv[2] * nx + inv[5] * ny + inv[8] * nz
              wl = Math.sqrt(wx * wx + wy * wy + wz * wz)
              d /= wl if wl > 0
            end
            k = ambient + diffuse * (d > 0 ? d : 0.0)
            r *= k
            g *= k
            b *= k
          end
          if fogs
            f = ((w0 + w1 + w2) * 0.333333 - fog_near) * fog_inv
            if f > 0
              f = 1.0 if f > 1.0
              r += (fog_r - r) * f
              g += (fog_g - g) * f
              b += (fog_b - b) * f
            end
          end

          # Triangles crossing the near plane are clipped instead of dropped
          if w0 < near || w1 < near || w2 < near
            emit_clipped(triangles, [
              [xs[i0], ys[i0], zs[i0], w0, uv0 ? su0 : 0, uv0 ? sv0 : 0],
              [xs[i1], ys[i1], zs[i1], w1, uv0 ? su1 : 0, uv0 ? sv1 : 0],
              [xs[i2], ys[i2], zs[i2], w2, uv0 ? su2 : 0, uv0 ? sv2 : 0]
            ], near, r, g, b, color_a, uv0 ? texture : nil, !uv0)
            next
          end

          # Inline frustum culling on the cached perspective divide
          next if ndz[i0] > 1.0 && ndz[i1] > 1.0 && ndz[i2] > 1.0

          ndc0x = ndx[i0]
          ndc1x = ndx[i1]
          ndc2x = ndx[i2]
          next if ndc0x < neg_margin && ndc1x < neg_margin && ndc2x < neg_margin
          next if ndc0x > margin && ndc1x > margin && ndc2x > margin
          ndc0y = ndy[i0]
          ndc1y = ndy[i1]
          ndc2y = ndy[i2]
          next if ndc0y < neg_margin && ndc1y < neg_margin && ndc2y < neg_margin
          next if ndc0y > margin && ndc1y > margin && ndc2y > margin

          z_depth = (zs[i0] + zs[i1] + zs[i2]) * 0.333333

          # Solid colours are :solid sprites with source coordinates (see
          # render_voxel_world); one hash literal with all keys.
          if uv0
            path = texture
            sx0 = su0
            sy0 = sv0
            sx1 = su1
            sy1 = sv1
            sx2 = su2
            sy2 = sv2
          else
            path = :solid
            sx0 = 0
            sy0 = 0
            sx1 = 1
            sy1 = 0
            sx2 = 0
            sy2 = 1
          end

          triangles << {
            x: scx[i0], y: scy[i0],
            x2: scx[i1], y2: scy[i1],
            x3: scx[i2], y3: scy[i2],
            z_depth: z_depth,
            r: r, g: g, b: b, a: color_a,
            path: path,
            source_x: sx0, source_y: sy0,
            source_x2: sx1, source_y2: sy1,
            source_x3: sx2, source_y3: sy2
          }
        end
      end
    end
  end
end
