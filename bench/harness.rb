module Bench
  Case = Struct.new(:name, :setup, :body)

  module Registry
    @cases = []

    class << self
      def register(name, setup: nil, &body)
        c = Case.new(name, setup, body)
        @cases << c
        c
      end

      def cases
        @cases
      end

      def reset!
        @cases = []
      end
    end
  end

  # Runs on CRuby (bench.rb) and on DragonRuby's mruby (mruby_runner.rb), so
  # it avoids module_function and CRuby-only APIs unless guarded.
  module Timer
    extend self

    def clock
      if Object.const_defined?(:Process)
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      else
        Time.now.to_f
      end
    end

    # Objects allocated so far, or nil where the VM can't tell (mruby).
    def allocated_objects
      GC.stat(:total_allocated_objects)
    rescue StandardError
      nil
    end

    # Returns { ns_per_op: Float, noise: Float, allocs_per_op: Float or nil }.
    # ns_per_op is the MINIMUM per-op time across rounds -- the most reproducible
    # single number for a CPU-bound microbenchmark, since interference (GC, OS
    # scheduling, other processes) only ever adds time. noise is the relative
    # spread (max-min)/min across rounds, as a percent. allocs_per_op is
    # deterministic, so it is a noise-free second signal.
    def measure(setup:, body:, target_time: 0.4, rounds: 8, warmup_time: 0.3)
      fixture = setup ? setup.call : nil

      # Time-based warmup: run until warmup_time elapses so caches are warm and
      # the CPU has settled to a sustained clock (past the turbo-boost ramp).
      warmup_deadline = clock + warmup_time
      body.call(fixture) while clock < warmup_deadline

      iters = calibrate(body, fixture, target_time)
      allocs_per_op = count_allocations(body, fixture, iters)

      seconds_per_op = []
      rounds.times do
        GC.start
        t0 = clock
        iters.times { body.call(fixture) }
        elapsed = clock - t0
        seconds_per_op << elapsed / iters
      end

      best = seconds_per_op.min
      worst = seconds_per_op.max
      noise = best > 0 ? (worst - best) / best * 100.0 : 0.0

      { ns_per_op: best * 1e9, noise: noise, allocs_per_op: allocs_per_op }
    end

    def count_allocations(body, fixture, iters)
      n = iters < 100 ? iters : 100
      before = allocated_objects
      return nil unless before

      n.times { body.call(fixture) }
      (allocated_objects - before).to_f / n
    end

    # Scale iteration count so one measured batch runs ~target_time seconds.
    def calibrate(body, fixture, target_time)
      iters = 1
      loop do
        t0 = clock
        iters.times { body.call(fixture) }
        elapsed = clock - t0

        return iters if iters >= 100_000_000
        return iters if elapsed >= target_time

        if elapsed <= 0.0
          iters *= 100
        else
          factor = (target_time / elapsed * 1.2).ceil
          factor = 2 if factor < 2
          factor = 1000 if factor > 1000
          iters *= factor
        end
      end
    end
  end
end
