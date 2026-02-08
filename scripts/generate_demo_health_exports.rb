#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
OUT_DIR = File.join(ROOT, "data", "demo")

TZ = "+0000"
SOURCE_NAME = "Apple Watch"
SOURCE_VERSION = "10.0"
DEVICE = "<<HKDevice: 0xDEMO>, name:Apple Watch, model:Watch, hardware:Watch7,4, software:10.0>"

def ts(date, hour:, min:)
  format("%<date>s %<hour>02d:%<min>02d:00 %<tz>s", date: date.to_s, hour: hour, min: min, tz: TZ)
end

def record_line(type:, unit:, value:, start_at:, end_at:)
  %(<Record type="#{type}" sourceName="#{SOURCE_NAME}" sourceVersion="#{SOURCE_VERSION}" unit="#{unit}" creationDate="#{end_at}" startDate="#{start_at}" endDate="#{end_at}" value="#{value}" device="#{DEVICE}"/>\n)
end

def build_day_metrics(day_idx, flare: false)
  # Deterministic pseudo-variation so data looks realistic but reproducible.
  wobble = Math.sin((day_idx + 1) * 0.9)
  drift = Math.cos((day_idx + 3) * 0.33)

  if flare
    {
      rhr_values: [
        (84.0 + 3.2 * wobble + 1.5 * drift).round(1),
        (88.0 + 2.7 * wobble).round(1),
        (91.0 + 2.1 * drift).round(1)
      ],
      hrv_values: [
        (24.0 + 2.2 * drift).round(1),
        (28.0 + 2.0 * wobble).round(1)
      ],
      stand_minutes: (88.0 + 7.0 * drift).round(1),
      active_minutes: (24.0 + 5.0 * wobble).round(1)
    }
  else
    {
      rhr_values: [
        (61.0 + 1.8 * wobble).round(1),
        (63.0 + 1.4 * drift).round(1),
        (64.0 + 1.3 * wobble).round(1)
      ],
      hrv_values: [
        (50.0 + 3.4 * drift).round(1),
        (55.0 + 2.8 * wobble).round(1)
      ],
      stand_minutes: (80.0 + 8.0 * drift).round(1),
      active_minutes: (42.0 + 7.0 * wobble).round(1)
    }
  end
end

def write_export_xml(path:, mode:, include_hrv: true)
  today = Date.today
  start_date = today - 29

  FileUtils.mkdir_p(File.dirname(path))

  File.open(path, "w") do |f|
    f.write %(<?xml version="1.0" encoding="UTF-8"?>\n)
    f.write %(<HealthData locale="en_US">\n)
    f.write %(  <ExportDate value="#{ts(today, hour: 12, min: 0)}"/>\n)
    f.write %(  <Me HKCharacteristicTypeIdentifierDateOfBirth="1998-04-14" HKCharacteristicTypeIdentifierBiologicalSex="HKBiologicalSexFemale" HKCharacteristicTypeIdentifierBloodType="HKBloodTypeNotSet" HKCharacteristicTypeIdentifierFitzpatrickSkinType="HKFitzpatrickSkinTypeNotSet"/>\n)

    (start_date..today).each_with_index do |d, idx|
      flare = mode == :needs_followup && idx >= 23
      metrics = build_day_metrics(idx, flare: flare)

      metrics[:rhr_values].each_with_index do |value, i|
        minute = 10 + i * 8
        start_at = ts(d, hour: 7, min: minute)
        end_at = ts(d, hour: 7, min: minute + 2)
        f.write("  ")
        f.write(
          record_line(
            type: "HKQuantityTypeIdentifierRestingHeartRate",
            unit: "count/min",
            value: value,
            start_at: start_at,
            end_at: end_at
          )
        )
      end

      if include_hrv
        metrics[:hrv_values].each_with_index do |value, i|
          minute = 40 + i * 10
          start_at = ts(d, hour: 6, min: minute)
          end_at = ts(d, hour: 6, min: minute + 3)
          f.write("  ")
          f.write(
            record_line(
              type: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
              unit: "ms",
              value: value,
              start_at: start_at,
              end_at: end_at
            )
          )
        end
      end

      f.write("  ")
      f.write(
        record_line(
          type: "HKQuantityTypeIdentifierAppleStandTime",
          unit: "min",
          value: metrics[:stand_minutes],
          start_at: ts(d, hour: 21, min: 0),
          end_at: ts(d, hour: 21, min: 1)
        )
      )

      f.write("  ")
      f.write(
        record_line(
          type: "HKQuantityTypeIdentifierAppleExerciseTime",
          unit: "min",
          value: metrics[:active_minutes],
          start_at: ts(d, hour: 21, min: 5),
          end_at: ts(d, hour: 21, min: 6)
        )
      )
    end

    f.write %(</HealthData>\n)
  end
end

def package_export(folder_name:, xml_path:)
  return unless system("command -v zip >/dev/null 2>&1")

  folder_path = File.join(OUT_DIR, folder_name)
  zip_path = File.join(OUT_DIR, "#{folder_name}.zip")
  FileUtils.mkdir_p(folder_path)
  FileUtils.cp(xml_path, File.join(folder_path, "export.xml"))

  Dir.chdir(OUT_DIR) do
    system("zip", "-rq", zip_path, folder_name)
  end
end

normal_xml = File.join(OUT_DIR, "normal_export.xml")
followup_xml = File.join(OUT_DIR, "needs_followup_export.xml")
normal_cluster_xml = File.join(OUT_DIR, "normal_cluster_export.xml")

write_export_xml(path: normal_xml, mode: :normal, include_hrv: true)
write_export_xml(path: followup_xml, mode: :needs_followup)
write_export_xml(path: normal_cluster_xml, mode: :normal, include_hrv: false)

package_export(folder_name: "normal_export_bundle", xml_path: normal_xml)
package_export(folder_name: "needs_followup_export_bundle", xml_path: followup_xml)
package_export(folder_name: "normal_cluster_export_bundle", xml_path: normal_cluster_xml)

puts "Generated:"
puts "- #{normal_xml}"
puts "- #{followup_xml}"
puts "- #{normal_cluster_xml}"
puts "- #{File.join(OUT_DIR, 'normal_export_bundle.zip')} (if zip installed)"
puts "- #{File.join(OUT_DIR, 'needs_followup_export_bundle.zip')} (if zip installed)"
puts "- #{File.join(OUT_DIR, 'normal_cluster_export_bundle.zip')} (if zip installed)"
