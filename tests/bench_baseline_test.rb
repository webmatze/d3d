require "minitest/autorun"
require "tmpdir"
require_relative "../bench/baseline"

class BenchBaselineTest < Minitest::Test
  def test_load_missing_returns_nil
    missing = File.join(Dir.tmpdir, "d3d_bench_does_not_exist.json")
    assert_nil Bench::Baseline.load(missing)
  end

  def test_load_corrupt_file_returns_nil
    Dir.mktmpdir do |dir|
      path = File.join(dir, "baseline.json")
      File.write(path, "{ this is not valid json")
      assert_nil Bench::Baseline.load(path)
    end
  end

  def test_load_wrong_shape_cases_returns_nil
    Dir.mktmpdir do |dir|
      path = File.join(dir, "baseline.json")
      File.write(path, JSON.generate({ "cases" => [] }))
      assert_nil Bench::Baseline.load(path)
    end
  end

  def test_load_skips_entries_without_numeric_ns_per_op
    Dir.mktmpdir do |dir|
      path = File.join(dir, "baseline.json")
      File.write(path, JSON.generate({ "cases" => {
        "good/case" => { "ns_per_op" => 100.0, "noise" => 1.0 },
        "bad/string" => { "ns_per_op" => "oops", "noise" => 1.0 },
        "bad/missing" => { "noise" => 1.0 }
      } }))
      loaded = Bench::Baseline.load(path)
      assert_equal ["good/case"], loaded.keys
      assert_in_delta 100.0, loaded["good/case"]["ns_per_op"], 1e-9
    end
  end

  def test_save_then_load_roundtrip
    Dir.mktmpdir do |dir|
      path = File.join(dir, "baseline.json")
      results = [
        { name: "a/x", ns_per_op: 123.4, noise: 2.5 },
        { name: "b/y", ns_per_op: 9.0, noise: 0.0 }
      ]
      Bench::Baseline.save(path, results)
      loaded = Bench::Baseline.load(path)

      assert_in_delta 123.4, loaded["a/x"]["ns_per_op"], 1e-9
      assert_in_delta 2.5,   loaded["a/x"]["noise"], 1e-9
      assert_in_delta 9.0,   loaded["b/y"]["ns_per_op"], 1e-9
    end
  end
end
