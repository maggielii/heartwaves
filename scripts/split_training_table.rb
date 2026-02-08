#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "fileutils"
require "json"
require "time"

ROOT = File.expand_path("..", __dir__)
INPUT_CSV = File.join(ROOT, "data", "processed", "training_table.csv")
OUT_DIR = File.join(ROOT, "data", "processed", "splits")
SUMMARY_JSON = File.join(OUT_DIR, "split_summary.json")

SEED = 42
TRAIN_RATIO = 0.70
VAL_RATIO = 0.15

unless File.file?(INPUT_CSV)
  warn "Missing input CSV: #{INPUT_CSV}"
  exit 1
end

rows = CSV.read(INPUT_CSV, headers: true)
headers = rows.headers

label_col = "phenotype_hint_target"
unless headers.include?(label_col)
  warn "Missing required label column: #{label_col}"
  exit 1
end

rng = Random.new(SEED)
by_label = Hash.new { |h, k| h[k] = [] }
rows.each { |row| by_label[row[label_col].to_s] << row }

train = []
val = []
test = []

by_label.each_value do |group_rows|
  shuffled = group_rows.shuffle(random: rng)
  n = shuffled.length
  n_train = (n * TRAIN_RATIO).round
  n_val = (n * VAL_RATIO).round
  n_test = n - n_train - n_val
  if n_test.negative?
    n_test = 0
    n_val = [0, n - n_train].max
  end

  train.concat(shuffled[0, n_train] || [])
  val.concat(shuffled[n_train, n_val] || [])
  test.concat(shuffled[n_train + n_val, n_test] || [])
end

FileUtils.mkdir_p(OUT_DIR)

{
  "train.csv" => train,
  "val.csv" => val,
  "test.csv" => test
}.each do |filename, split_rows|
  CSV.open(File.join(OUT_DIR, filename), "w") do |csv|
    csv << headers
    split_rows.each { |row| csv << headers.map { |h| row[h] } }
  end
end

split_counts = {
  "train" => train.size,
  "val" => val.size,
  "test" => test.size
}

label_counts = {}
{
  "train" => train,
  "val" => val,
  "test" => test
}.each do |split_name, split_rows|
  counts = Hash.new(0)
  split_rows.each { |row| counts[row[label_col].to_s] += 1 }
  label_counts[split_name] = counts.sort.to_h
end

summary = {
  generated_on: Time.now.utc.iso8601,
  input_csv: INPUT_CSV,
  output_dir: OUT_DIR,
  seed: SEED,
  ratios: { train: TRAIN_RATIO, val: VAL_RATIO, test: 1.0 - TRAIN_RATIO - VAL_RATIO },
  split_counts: split_counts,
  label_counts: label_counts
}

File.write(SUMMARY_JSON, JSON.pretty_generate(summary))

puts "Wrote splits to #{OUT_DIR}"
puts JSON.pretty_generate(split_counts)
