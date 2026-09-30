# Basic demo: rotating cube, orbiting sphere, ground plane, click-to-raycast.
class BasicDemo
  LIGHT = { direction: [0.5, 1.0, 0.3], ambient: 0.35 }.freeze
  # Fog fades into the background colour, so both use the same value.
  FOG = { near: 12.0, far: 40.0, color: [24, 28, 40] }.freeze

  def self.title
    "Basic 3D Models"
  end

  def self.description
    "Cube, sphere and plane with first-person camera and raycasting"
  end

  def setup(args)
    args.state.camera = D3D::Camera.new(
      position: D3D::Vec3.new(0, 2, 8),
      fov: 70
    )

    # Create a colored cube (no texture)
    args.state.cube = D3D::Model.new(
      mesh: D3D.cube_mesh,
      color: { r: 100, g: 150, b: 255, a: 255 }
    )
    args.state.cube.set_scale(2)

    # Create a sphere
    args.state.sphere = D3D::Model.new(
      mesh: D3D.sphere_mesh(radius: 0.5, segments: 12, rings: 8),
      color: { r: 255, g: 200, b: 100, a: 255 }
    )
    args.state.sphere.position.y = 1

    # Create a ground plane (subdivided so fog and light vary across it)
    args.state.ground = D3D::Model.new(
      mesh: D3D.plane_mesh(width: 20, depth: 20, segments_x: 10, segments_z: 10),
      color: { r: 80, g: 120, b: 80, a: 255 }
    )
    args.state.ground.position.y = -1.5

    args.state.models = [args.state.cube, args.state.sphere, args.state.ground]
    args.state.hit_info = "Click to raycast"
    args.state.orbit_angle = 0
  end

  def tick(args)
    args.state.dt = 1.0 / 60.0

    # Camera controls
    args.state.camera.first_person_movement(args)
    args.state.camera.first_person_look(args)

    # Animate the cube
    args.state.cube.rotation.y += 0.01
    args.state.cube.rotation.x += 0.005

    # Animate the sphere orbiting the cube
    orbit_speed = 0.02
    orbit_radius = 3
    args.state.orbit_angle += orbit_speed
    args.state.sphere.position.x = Math.cos(args.state.orbit_angle) * orbit_radius
    args.state.sphere.position.z = Math.sin(args.state.orbit_angle) * orbit_radius
    args.state.sphere.rotation.y += 0.03

    # Mark models as dirty after position/rotation changes
    args.state.cube.mark_dirty!
    args.state.sphere.mark_dirty!

    # Raycast on click
    if args.inputs.mouse.click && !args.state.camera.mouse_captured
      ray_dir = args.state.camera.screen_to_ray(args.inputs.mouse.x, args.inputs.mouse.y)
      hit = D3D::Collisions.ray_models(
        args.state.camera.position,
        ray_dir,
        args.state.models
      )
      if hit
        args.state.hit_info = "Hit: #{model_name(args, hit[:model])} at distance #{hit[:t].round(2)}"
      else
        args.state.hit_info = "No hit"
      end
    end

    # Render 3D scene
    args.outputs.background_color = FOG[:color]
    # The ground is drawn first, then the objects. Sorting everything together
    # by triangle depth lets ground tiles that reach out in front of the cube
    # paint over its bottom edge; nothing is ever below the ground, and from
    # below it is back face culled.
    args.outputs.primitives << D3D.render(args.state.camera, [args.state.ground], light: LIGHT, fog: FOG)
    args.outputs.primitives << D3D.render(args.state.camera, [args.state.cube, args.state.sphere], light: LIGHT, fog: FOG)

    # UI
    render_ui(args)
  end

  private

  def model_name(args, model)
    return 'Cube' if model == args.state.cube
    return 'Sphere' if model == args.state.sphere

    'Ground'
  end

  def render_ui(args)
    args.outputs.labels << {
      x: 10, y: 710,
      text: "D3D Engine Demo",
      size_enum: 2,
      r: 255, g: 255, b: 255
    }

    args.outputs.labels << {
      x: 10, y: 680,
      text: "WASD: Move | Space/Shift: Up/Down | Mouse: Look (click to capture, ESC to release)",
      size_enum: 0,
      r: 200, g: 200, b: 200
    }

    args.outputs.labels << {
      x: 10, y: 655,
      text: "Camera: #{format_vec3(args.state.camera.position)}",
      size_enum: 0,
      r: 200, g: 200, b: 200
    }

    args.outputs.labels << {
      x: 10, y: 630,
      text: args.state.hit_info || "",
      size_enum: 0,
      r: 255, g: 255, b: 100
    }

    args.outputs.labels << {
      x: 1270, y: 20,
      text: "#{args.gtk.current_framerate.to_i} FPS",
      size_enum: 0,
      r: 200, g: 200, b: 200,
      alignment_enum: 2
    }
  end

  def format_vec3(v)
    "(#{v.x.round(2)}, #{v.y.round(2)}, #{v.z.round(2)})"
  end
end

Demos.register(BasicDemo)
