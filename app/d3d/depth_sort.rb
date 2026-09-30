module D3D
  # Back-to-front sorting for the painter's algorithm, in one place so every
  # renderer uses the fastest variant for the Ruby it runs on. The two VMs
  # disagree on what is fast (3708 triangles): CRuby's sort_by is C code
  # (0.32 ms) and a sort block is ~2x slower; on DragonRuby's mruby sort_by
  # costs 16.1 ms and a sort block 9.7 ms. With the optional C extension
  # loaded (D3D::Native) the sort runs in C (0.19 ms). All put larger depths
  # first; triangles with equal depth may come out in either order.
  module DepthSort
    extend self

    MRUBY = Object.const_defined?(:RUBY_ENGINE) && RUBY_ENGINE == 'mruby'

    # Primitive hashes sorted by :z_depth, largest first (new Array).
    def triangles(list)
      if Native.enabled?
        Ext.sort_by_depth(list)
      elsif MRUBY
        list.sort { |a, b| b[:z_depth] <=> a[:z_depth] }
      else
        list.sort_by { |t| -t[:z_depth] }
      end
    end

    # [depth, primitive] pairs sorted by depth, largest first; returns the
    # primitives (new Array).
    def pairs(list)
      return Ext.sort_pairs(list) if Native.enabled?

      sorted = if MRUBY
                 list.sort { |a, b| b[0] <=> a[0] }
               else
                 list.sort_by { |e| -e[0] }
               end
      sorted.map { |e| e[1] }
    end
  end
end
