require "minitest/autorun"
require "open3"

# Engine output must match bench/golden.json. If a change is intended, run
# `ruby bench/golden.rb --update` and explain why in the commit.
class GoldenTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_engine_output_matches_golden_fingerprints
    out, err, status = Open3.capture3("ruby", File.join(ROOT, "bench/golden.rb"), chdir: ROOT)
    assert status.success?, "#{out}#{err}"
  end
end
