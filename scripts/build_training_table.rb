#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "fileutils"
require "json"
require "open3"
require "time"

ROOT = File.expand_path("..", __dir__)
RAW_DIR = File.join(ROOT, "data", "raw", "physionet", "cves")
PROCESSED_DIR = File.join(ROOT, "data", "processed")
SOURCE_CSV = File.join(RAW_DIR, "subjects.csv")
SOURCE_URL = "https://physionet.org/files/cves/1.0.0/subjects.csv"
OUT_CSV = File.join(PROCESSED_DIR, "training_table.csv")
OUT_SUMMARY = File.join(PROCESSED_DIR, "training_table_summary.json")

def download_if_missing(path, url)
  return if File.file?(path) && File.size(path) > 0

  FileUtils.mkdir_p(File.dirname(path))
  stdout, status = Open3.capture2e("curl", "-fsSL", url, "-o", path)
  raise "Failed to download #{url}: #{stdout}" unless status.success?
end

def normalize_name(name)
  name.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
end

def find_header(headers, candidates)
  normalized = headers.map { |h| [h, normalize_name(h)] }.to_h
  candidates.each do |candidate|
    candidate_norm = normalize_name(candidate)
    exact = normalized.find { |_raw, norm| norm == candidate_norm }
    return exact[0] if exact
  end
  candidates.each do |candidate|
    candidate_norm = normalize_name(candidate)
    partial = normalized.find { |_raw, norm| norm.include?(candidate_norm) || candidate_norm.include?(norm) }
    return partial[0] if partial
  end
  nil
end

def yes_value?(value)
  value.to_s.strip.upcase == "YES"
end

def parse_float(value)
  str = value.to_s.strip
  return nil if str.empty?
  Float(str)
rescue ArgumentError
  nil
end

def phenotype_for(row)
  oh_symptom = yes_value?(row[:symptom_oh])
  syncope_symptom = yes_value?(row[:symptom_syncope])
  dizziness_symptom = yes_value?(row[:symptom_dizziness])

  delta_hr = row[:delta_hr_stand_minus_sit]
  delta_sbp = row[:delta_sbp_stand_minus_sit]
  resting_hr = row[:resting_hr_mean]

  if oh_symptom || (!delta_sbp.nil? && delta_sbp <= -20.0)
    confidence = (oh_symptom && !delta_sbp.nil? && delta_sbp <= -20.0) ? "medium" : "low"
    return {
      status_target: "needs_followup",
      phenotype_hint_target: "oh_like",
      phenotype_confidence_target: confidence,
      notes: "OH symptom or orthostatic SBP drop pattern."
    }
  end

  if syncope_symptom
    return {
      status_target: "needs_followup",
      phenotype_hint_target: "vvs_like",
      phenotype_confidence_target: "low",
      notes: "Syncope symptom history suggests vasovagal-like pattern."
    }
  end

  if !delta_hr.nil? && delta_hr >= 30.0 && (delta_sbp.nil? || delta_sbp > -20.0)
    return {
      status_target: "needs_followup",
      phenotype_hint_target: "pots_like",
      phenotype_confidence_target: "medium",
      notes: "Large stand-related HR rise without major SBP drop."
    }
  end

  if !resting_hr.nil? && resting_hr >= 90.0 && (delta_hr.nil? || delta_hr < 30.0)
    return {
      status_target: "needs_followup",
      phenotype_hint_target: "ist_like",
      phenotype_confidence_target: "medium",
      notes: "High resting HR with limited orthostatic HR rise."
    }
  end

  confidence = row[:group].to_s.upcase.include?("CONTROL") ? "high" : "low"
  notes = if dizziness_symptom
            "No strong objective subtype signal; dizziness symptom present."
          else
            "No strong dysautonomia-like subtype signal from available fields."
          end
  {
    status_target: "normal",
    phenotype_hint_target: "normal",
    phenotype_confidence_target: confidence,
    notes: notes
  }
end

download_if_missing(SOURCE_CSV, SOURCE_URL)
FileUtils.mkdir_p(PROCESSED_DIR)

input_rows = CSV.read(SOURCE_CSV, headers: true)
headers = input_rows.headers.compact

subject_col = find_header(headers, ["subject_number"])
group_col = find_header(headers, ["group"])
age_col = find_header(headers, ["age"])
resting_hr_col = find_header(headers, ["(Baseline Mean) HR BP BASELINE", "baseline hr"])
hrv_sdnn_col = find_header(headers, ["HRV_ SDNN", "hrv sdnn"])
sit_hr_col = find_header(headers, ["(SitEO mn) SitEO HR mean", "siteo hr mean"])
stand_hr_col = find_header(headers, ["(StandEO mn) Mean HR StandEO", "standeo mean hr"])
sit_sbp_col = find_header(headers, ["Systolic BP SitEO", "sys bp siteo"])
stand_sbp_col = find_header(headers, ["Sys BP StandEO", "standeo sys bp"])
symptom_dizziness_col = find_header(headers, ["Dizziness AUTONOMIC SYMPTOMS", "dizziness autonomic symptoms"])
symptom_syncope_col = find_header(headers, ["Syncope AUTONOMIC SYMPTOMS", "syncope autonomic symptoms"])
symptom_oh_col = find_header(headers, ["OH AUTONOMIC SYMPTOMS", "oh autonomic symptoms"])

missing_required = []
missing_required << "subject_number" if subject_col.nil?
missing_required << "group" if group_col.nil?
raise "Missing required columns: #{missing_required.join(', ')}" unless missing_required.empty?

out_headers = [
  "source_dataset",
  "source_subject_id",
  "source_group",
  "age",
  "resting_hr_mean",
  "hrv_sdnn_mean",
  "stand_minutes",
  "active_minutes",
  "sit_hr_mean",
  "stand_hr_mean",
  "delta_hr_stand_minus_sit",
  "sit_sbp_mean",
  "stand_sbp_mean",
  "delta_sbp_stand_minus_sit",
  "symptom_dizziness",
  "symptom_syncope",
  "symptom_oh",
  "status_target",
  "phenotype_hint_target",
  "phenotype_confidence_target",
  "label_quality",
  "notes"
]

rows = []
input_rows.each do |r|
  subject_id = r[subject_col].to_s.strip
  next if subject_id.empty?

  group = r[group_col].to_s.strip
  next if group.empty?

  sit_hr = sit_hr_col ? parse_float(r[sit_hr_col]) : nil
  stand_hr = stand_hr_col ? parse_float(r[stand_hr_col]) : nil
  sit_sbp = sit_sbp_col ? parse_float(r[sit_sbp_col]) : nil
  stand_sbp = stand_sbp_col ? parse_float(r[stand_sbp_col]) : nil

  delta_hr = (sit_hr && stand_hr) ? (stand_hr - sit_hr).round(3) : nil
  delta_sbp = (sit_sbp && stand_sbp) ? (stand_sbp - sit_sbp).round(3) : nil

  row = {
    source_dataset: "physionet_cves",
    source_subject_id: subject_id,
    group: group,
    age: age_col ? parse_float(r[age_col]) : nil,
    resting_hr_mean: resting_hr_col ? parse_float(r[resting_hr_col]) : nil,
    hrv_sdnn_mean: hrv_sdnn_col ? parse_float(r[hrv_sdnn_col]) : nil,
    stand_minutes: nil,
    active_minutes: nil,
    sit_hr_mean: sit_hr,
    stand_hr_mean: stand_hr,
    delta_hr_stand_minus_sit: delta_hr,
    sit_sbp_mean: sit_sbp,
    stand_sbp_mean: stand_sbp,
    delta_sbp_stand_minus_sit: delta_sbp,
    symptom_dizziness: symptom_dizziness_col ? r[symptom_dizziness_col].to_s.strip : "",
    symptom_syncope: symptom_syncope_col ? r[symptom_syncope_col].to_s.strip : "",
    symptom_oh: symptom_oh_col ? r[symptom_oh_col].to_s.strip : ""
  }

  phenotype = phenotype_for(
    symptom_oh: row[:symptom_oh],
    symptom_syncope: row[:symptom_syncope],
    symptom_dizziness: row[:symptom_dizziness],
    delta_hr_stand_minus_sit: row[:delta_hr_stand_minus_sit],
    delta_sbp_stand_minus_sit: row[:delta_sbp_stand_minus_sit],
    resting_hr_mean: row[:resting_hr_mean],
    group: row[:group]
  )

  rows << [
    row[:source_dataset],
    row[:source_subject_id],
    row[:group],
    row[:age],
    row[:resting_hr_mean],
    row[:hrv_sdnn_mean],
    row[:stand_minutes],
    row[:active_minutes],
    row[:sit_hr_mean],
    row[:stand_hr_mean],
    row[:delta_hr_stand_minus_sit],
    row[:sit_sbp_mean],
    row[:stand_sbp_mean],
    row[:delta_sbp_stand_minus_sit],
    row[:symptom_dizziness],
    row[:symptom_syncope],
    row[:symptom_oh],
    phenotype[:status_target],
    phenotype[:phenotype_hint_target],
    phenotype[:phenotype_confidence_target],
    "proxy",
    phenotype[:notes]
  ]
end

CSV.open(OUT_CSV, "w") do |csv|
  csv << out_headers
  rows.each { |row| csv << row }
end

phenotype_counts = Hash.new(0)
status_counts = Hash.new(0)
confidence_counts = Hash.new(0)

rows.each do |row|
  phenotype_counts[row[out_headers.index("phenotype_hint_target")]] += 1
  status_counts[row[out_headers.index("status_target")]] += 1
  confidence_counts[row[out_headers.index("phenotype_confidence_target")]] += 1
end

summary = {
  generated_on: Time.now.utc.iso8601,
  source_file: SOURCE_CSV,
  source_url: SOURCE_URL,
  output_csv: OUT_CSV,
  row_count: rows.length,
  counts: {
    status_target: status_counts.sort.to_h,
    phenotype_hint_target: phenotype_counts.sort.to_h,
    phenotype_confidence_target: confidence_counts.sort.to_h
  },
  schema: out_headers
}

File.write(OUT_SUMMARY, JSON.pretty_generate(summary))

puts "Wrote #{OUT_CSV} (#{rows.length} rows)"
puts "Wrote #{OUT_SUMMARY}"
