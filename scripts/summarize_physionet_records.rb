#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"
require "time"

root = Pathname.new(File.expand_path("..", __dir__))
raw_root = root.join("data/raw/physionet")
out_path = root.join("data/sources/physionet_inventory.json")
manifest_path = root.join("data/sources/physionet_manifest.json")

unless raw_root.directory?
  warn "Missing directory: #{raw_root}"
  exit 1
end

summary = {
  generated_on: Time.now.utc.iso8601,
  datasets: []
}

manifest = JSON.parse(File.read(manifest_path.to_s))
dataset_ids = manifest.fetch("datasets").map { |d| d.fetch("id") }

dataset_ids.each do |dataset_id|
  dataset_dir = raw_root.join(dataset_id)
  records_path = dataset_dir.join("RECORDS")
  files_path = dataset_dir.join("FILES.txt")
  entry = {
    id: dataset_id,
    has_records: records_path.file?,
    has_files_listing: files_path.file?
  }

  if records_path.file?
    lines = records_path.each_line.map(&:strip).reject(&:empty?)
    ext_counts = Hash.new(0)
    lines.each do |line|
      ext = File.extname(line)
      ext = "(none)" if ext.empty?
      ext_counts[ext] += 1
    end
    entry[:records_count] = lines.length
    entry[:extension_counts] = ext_counts.sort.to_h
    entry[:sample_records] = lines.first(5)
  end

  if files_path.file?
    file_lines = files_path.each_line.map(&:strip).reject(&:empty?)
    file_lines = file_lines.reject { |line| line == "../" }
    file_ext_counts = Hash.new(0)
    file_lines.each do |line|
      ext = File.extname(line)
      ext = "(none)" if ext.empty?
      file_ext_counts[ext] += 1
    end
    entry[:files_count] = file_lines.length
    entry[:file_extension_counts] = file_ext_counts.sort.to_h
    entry[:sample_files] = file_lines.first(5)
  end

  summary[:datasets] << entry
end

File.write(out_path, JSON.pretty_generate(summary))
puts "Wrote #{out_path}"
