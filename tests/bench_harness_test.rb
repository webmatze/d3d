require "minitest/autorun"
require_relative "../bench/harness"

class BenchHarnessTest < Minitest::Test
  def setup
    Bench::Registry.reset!
  end

  def test_register_and_list_preserves_order
    Bench::Registry.register("t/one") { |_| 1 + 1 }
    Bench::Registry.register("t/two", setup: -> { 41 }) { |fx| fx + 1 }
    assert_equal ["t/one", "t/two"], Bench::Registry.cases.map(&:name)
  end

  def test_case_exposes_setup_and_body
    c = Bench::Registry.register("t/three", setup: -> { 10 }) { |fx| fx * 2 }
    assert_equal 10, c.setup.call
    assert_equal 20, c.body.call(c.setup.call)
  end

  def test_measure_returns_finite_positive_stats
    stats = Bench::Timer.measure(
      setup: -> { [1, 2, 3] },
      body: ->(fx) { fx.reduce(:+) },
      target_time: 0.01,
      rounds: 3,
      warmup_time: 0.001
    )
    assert stats[:ns_per_op] > 0
    assert stats[:ns_per_op].finite?
    assert stats[:noise] >= 0
    assert stats[:noise].finite?
  end

  def test_measure_works_without_setup
    stats = Bench::Timer.measure(
      setup: nil,
      body: ->(_fx) { 2 * 2 },
      target_time: 0.01,
      rounds: 2,
      warmup_time: 0.001
    )
    assert stats[:ns_per_op] > 0
  end
end
