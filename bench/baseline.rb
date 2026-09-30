require "json"

module Bench
  module Baseline
    module_function

    # Returns a Hash mapping case name => { "ns_per_op" => Float, "noise" => Float },
    # or nil when the baseline file is missing, unparseable, or not shaped like a
    # baseline. Entries missing a numeric ns_per_op are dropped so a hand-edited
    # file can't crash the runner later (e.g. indexing an Array or calling .zero?
    # on a String). ns_per_op is the only field the runner reads back.
    def load(path)
      return nil unless File.exist?(path)
      data = JSON.parse(File.read(path))
      cases = data.is_a?(Hash) ? data["cases"] : nil
      return nil unless cases.is_a?(Hash)

      cases.select { |_name, entry| entry.is_a?(Hash) && entry["ns_per_op"].is_a?(Numeric) }
    rescue JSON::ParserError
      warn "Bench::Baseline: malformed JSON in #{path}, ignoring baseline"
      nil
    end

    # results: [{ name:, ns_per_op:, noise: }]
    def save(path, results)
      cases = {}
      results.each do |r|
        cases[r[:name]] = { "ns_per_op" => r[:ns_per_op], "noise" => r[:noise] }
      end
      File.write(path, JSON.pretty_generate({ "cases" => cases }) + "\n")
    end
  end
end
