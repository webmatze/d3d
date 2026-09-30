module D3D
  # Position plus an orthonormal basis (right, up, fwd). Rotations are applied
  # around the pose's own axes, so there is no gimbal lock and full roll -
  # suitable for six degrees of freedom flight. Also used as the camera of a
  # SceneRenderer.
  class Pose
    attr_accessor :position, :right, :up, :fwd

    def initialize(position = [0.0, 0.0, 0.0], fwd = [0.0, 0.0, 1.0], up_hint = [0.0, 1.0, 0.0])
      @position = position.map(&:to_f)
      look!(fwd, up_hint)
    end

    # Resets the orientation to look along fwd.
    def look!(fwd, up_hint = [0.0, 1.0, 0.0])
      @fwd = V.norm(fwd)
      @right, @up = V.basis_from_forward(@fwd, up_hint)
      self
    end

    # Turn right (positive) / left (negative).
    def yaw!(ang)
      @fwd, @right = V.rotate_pair(@fwd, @right, ang) if ang != 0
      self
    end

    # Nose up (positive) / down (negative).
    def pitch!(ang)
      @fwd, @up = V.rotate_pair(@fwd, @up, ang) if ang != 0
      self
    end

    # Roll clockwise (positive) / counter-clockwise (negative).
    def roll!(ang)
      @up, @right = V.rotate_pair(@up, @right, ang) if ang != 0
      self
    end

    # Removes accumulated floating point drift. Call once per frame after rotating.
    def orthonormalize!
      @fwd = V.norm(@fwd)
      @right = V.norm(V.cross(@up, @fwd))
      @up = V.cross(@fwd, @right)
      self
    end

    def dup
      p = Pose.allocate
      p.position = @position.dup
      p.right = @right.dup
      p.up = @up.dup
      p.fwd = @fwd.dup
      p
    end
  end
end
