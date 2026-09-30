# Registry and in-game menu for D3D demos.
#
# A demo is a class with:
#   self.title       - name shown in the menu (required)
#   self.description - one-liner shown in the menu (optional)
#   setup(args)      - called once when the demo is started
#   tick(args)       - called every tick while the demo is active
#
# Register a demo at the bottom of its file: Demos.register(MyDemo)
module Demos
  NUMBER_KEYS = [:one, :two, :three, :four, :five, :six, :seven, :eight, :nine].freeze

  @demos = []
  @selected = 0
  @active = nil

  class << self
    attr_reader :demos

    def register(klass)
      @demos << klass unless @demos.include?(klass)
    end

    def tick(args)
      if @active
        tick_demo(args)
      else
        tick_menu(args)
      end
    end

    private

    def tick_demo(args)
      # ESC with a captured mouse only releases the mouse (handled by the
      # camera inside the demo); ESC with a free mouse returns to the menu.
      if args.inputs.keyboard.key_down.escape && !args.state.camera&.mouse_captured
        @active = nil
        args.state.camera = nil
        return
      end

      @active.tick(args)
    end

    def tick_menu(args)
      kb = args.inputs.keyboard

      @selected = (@selected - 1) % @demos.size if kb.key_down.up || kb.key_down.w
      @selected = (@selected + 1) % @demos.size if kb.key_down.down || kb.key_down.s

      NUMBER_KEYS.each_with_index do |key, i|
        start_demo(args, @demos[i]) if i < @demos.size && kb.key_down.send(key)
      end

      start_demo(args, @demos[@selected]) if kb.key_down.enter || kb.key_down.space

      render_menu(args)
    end

    def start_demo(args, klass)
      @active = klass.new
      @active.setup(args)
    end

    def render_menu(args)
      args.outputs.background_color = [20, 24, 32]

      args.outputs.labels << { x: 640, y: 620, text: "D3D Engine", size_enum: 10,
                               r: 255, g: 255, b: 255, alignment_enum: 1 }
      args.outputs.labels << { x: 640, y: 570, text: "Select a demo", size_enum: 2,
                               r: 160, g: 170, b: 190, alignment_enum: 1 }

      @demos.each_with_index do |demo, i|
        y = 480 - i * 70
        selected = i == @selected

        if selected
          args.outputs.primitives << { x: 340, y: y - 42, w: 600, h: 56,
                                       r: 60, g: 90, b: 150, a: 120, path: :solid }
        end

        args.outputs.labels << { x: 360, y: y, text: "#{i + 1}. #{demo.title}", size_enum: 4,
                                 r: selected ? 255 : 190, g: selected ? 255 : 190,
                                 b: selected ? 255 : 190 }
        if demo.respond_to?(:description)
          args.outputs.labels << { x: 360, y: y - 24, text: demo.description, size_enum: -1,
                                   r: 140, g: 150, b: 170 }
        end
      end

      args.outputs.labels << { x: 640, y: 80,
                               text: "Up/Down: Select | Enter: Start | 1-#{@demos.size}: Quick start | In demo: ESC returns here",
                               size_enum: 0, r: 140, g: 150, b: 170, alignment_enum: 1 }
    end
  end
end
