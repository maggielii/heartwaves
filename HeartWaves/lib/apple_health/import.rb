# frozen_string_literal: true

require "date"
require "open3"

module AppleHealth
  module Import
    # Apple Health export contains many types; we keep MVP narrow and fast.
    TARGET_TYPES = {
      "HKQuantityTypeIdentifierRestingHeartRate" => :resting_hr_bpm,
      "HKQuantityTypeIdentifierHeartRateVariabilitySDNN" => :hrv_sdnn_ms,
      "HKQuantityTypeIdentifierAppleStandTime" => :stand_minutes,
      "HKQuantityTypeIdentifierAppleExerciseTime" => :active_minutes
    }.freeze

    def self.from_export_zip(zip_path, days:)
      raise "ZIP not found: #{zip_path}" unless File.file?(zip_path)
      raise "unzip not available" if system("command -v unzip >/dev/null 2>&1") == false

      xml_entry = find_export_xml_entry(zip_path)
      raise "Could not find export.xml inside ZIP" if xml_entry.nil?

      # We stream the XML from the zip so we don't explode memory on large exports.
      daily = Hash.new { |h, k| h[k] = { resting_hr_bpm: [], hrv_sdnn_ms: [], stand_minutes: 0.0, active_minutes: 0.0 } }

      start_cutoff = (Date.today - (days - 1))
      counts = { total_records: 0, kept_records: 0 }

      IO.popen(["unzip", "-p", zip_path, xml_entry], "r") do |io|
        parse_export_io(io, daily: daily, start_cutoff: start_cutoff, counts: counts)
      end

      totals = parse_totals(daily: daily, start_cutoff: start_cutoff, days: days, counts: counts, xml_entry: xml_entry)
      totals
    end

    def self.from_export_xml(xml_path, days:)
      raise "export.xml not found: #{xml_path}" unless File.file?(xml_path)

      daily = Hash.new { |h, k| h[k] = { resting_hr_bpm: [], hrv_sdnn_ms: [], stand_minutes: 0.0, active_minutes: 0.0 } }
      start_cutoff = (Date.today - (days - 1))
      counts = { total_records: 0, kept_records: 0 }

      File.open(xml_path, "r") do |io|
        parse_export_io(io, daily: daily, start_cutoff: start_cutoff, counts: counts)
      end

      parse_totals(daily: daily, start_cutoff: start_cutoff, days: days, counts: counts, xml_entry: "export.xml")
    end

    def self.parse_export_io(io, daily:, start_cutoff:, counts:)
      io.each_line do |line|
        # Apple export typically uses one <Record ... /> per line. We keep it simple and fast.
        next unless line.include?("<Record ")
        next unless (m = line.match(/<Record\b([^>]*)\/>/))

        attrs = parse_attrs(m[1])
        type = attrs["type"]
        metric = TARGET_TYPES[type]
        next if metric.nil?

        # startDate is the most useful for daily bucketing.
        sd = attrs["startDate"]
        next if sd.nil?

        begin
          date = Date.parse(sd)
        rescue ArgumentError
          next
        end

        counts[:total_records] += 1
        next if date < start_cutoff

        value_s = attrs["value"]
        next if value_s.nil?
        value = value_s.to_f

        counts[:kept_records] += 1
        day = daily[date]

        case metric
        when :resting_hr_bpm
          day[:resting_hr_bpm] << value
        when :hrv_sdnn_ms
          day[:hrv_sdnn_ms] << value
        when :stand_minutes
          day[:stand_minutes] += value
        when :active_minutes
          day[:active_minutes] += value
        end
      end
    end

    def self.parse_totals(daily:, start_cutoff:, days:, counts:, xml_entry:)
      dates = (start_cutoff..Date.today).to_a
      series = dates.map do |d|
        day = daily[d]
        {
          date: d.to_s,
          resting_hr_mean: mean(day[:resting_hr_bpm]),
          hrv_sdnn_mean: mean(day[:hrv_sdnn_ms]),
          stand_minutes: day[:stand_minutes].round(2),
          active_minutes: day[:active_minutes].round(2)
        }
      end

      {
        window_days: days,
        start_date: start_cutoff.to_s,
        end_date: Date.today.to_s,
        export_xml_entry: xml_entry,
        record_counts: { total_seen: counts[:total_records], kept: counts[:kept_records] },
        daily: series
      }
    end

    def self.find_export_xml_entry(zip_path)
      stdout, status = Open3.capture2("unzip", "-Z1", zip_path)
      return nil unless status.success?

      # Typical: apple_health_export/export.xml
      entries = stdout.split("\n")
      entries.find { |e| e.end_with?("export.xml") }
    end

    def self.parse_attrs(attr_str)
      attrs = {}
      # Attributes are well-formed key="value" pairs.
      attr_str.scan(/(\w+)="([^"]*)"/) { |k, v| attrs[k] = v }
      attrs
    end

    def self.mean(arr)
      return nil if arr.empty?
      (arr.sum / arr.length.to_f).round(2)
    end
  end
end
