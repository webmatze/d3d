require "fileutils"

module Bench
  # Runs DragonRuby headless (SDL dummy video driver) for compare.rb --mruby
  # and smoke.rb. The binary comes from DRAGONRUBY_BIN or the Smaug install
  # matching the version/edition in Smaug.toml.
  module DragonRuby
    module_function

    ROOT = File.expand_path("..", __dir__)
    TIMEOUT = 900

    def bin
      return ENV["DRAGONRUBY_BIN"] if ENV["DRAGONRUBY_BIN"]

      section = File.read(File.join(ROOT, "Smaug.toml"))[/\[dragonruby\][^\[]*/m] || ""
      version = section[/^version\s*=\s*"([^"]+)"/, 1]
      edition = section[/^edition\s*=\s*"([^"]+)"/, 1] || "standard"
      path = File.expand_path("~/Library/Application Support/org.Erebor-Studios.Smaug/dragonruby/#{edition}-#{version}/dragonruby")
      abort "Error: DragonRuby not found at #{path}; set DRAGONRUBY_BIN." unless File.exist?(path)
      path
    end

    # Copies the game (app/, metadata/, plus extra dirs such as bench/ or
    # sprites/) from src into a fresh dir under work and returns its path.
    def game_dir(work, name, src: ROOT, extra: [])
      dir = File.join(work, name)
      FileUtils.mkdir_p(dir)
      (["app", "metadata"] + extra).each do |d|
        path = File.join(src, d)
        FileUtils.cp_r(path, dir) if File.exist?(path)
      end
      disable_shaders(dir)
      dir
    end

    # shaders=true switches DragonRuby to the SDL_GPU renderer, which can't
    # start with the dummy video driver, so headless runs go without shaders.
    def disable_shaders(dir)
      meta = File.join(dir, "metadata", "game_metadata.txt")
      return unless File.exist?(meta)

      File.write(meta, File.read(meta).gsub(/^shaders=true\s*$/, "shaders=false"))
    end

    # Runs `dragonruby game_dir --eval eval_file [--no-tick]` and waits for it
    # to quit (the eval file must call $gtk.request_quit). Returns the log path.
    def run(game_dir, eval_file, no_tick: true, timeout: TIMEOUT)
      log = File.join(game_dir, "dragonruby.log")
      args = [game_dir, "--eval", eval_file]
      args << "--no-tick" if no_tick
      pid = Process.spawn({ "SDL_VIDEODRIVER" => "dummy" }, bin, *args, out: log, err: log)
      deadline = Time.now + timeout
      until Process.wait(pid, Process::WNOHANG)
        if Time.now > deadline
          Process.kill("KILL", pid)
          Process.wait(pid)
          abort "Error: DragonRuby timed out after #{timeout}s (log: #{log})"
        end
        sleep 0.2
      end
      log
    end
  end
end
