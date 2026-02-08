#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "fileutils"
require "json"
require "time"

ROOT = File.expand_path("..", __dir__)
SPLIT_DIR = File.join(ROOT, "data", "processed", "splits")
TRAIN_CSV = File.join(SPLIT_DIR, "train.csv")
VAL_CSV = File.join(SPLIT_DIR, "val.csv")
TEST_CSV = File.join(SPLIT_DIR, "test.csv")

MODEL_DIR = File.join(ROOT, "data", "models", "clustering_baseline")
MODEL_JSON = File.join(MODEL_DIR, "model.json")
EVAL_JSON = File.join(MODEL_DIR, "evaluation.json")
TRAIN_PRED_CSV = File.join(MODEL_DIR, "train_predictions.csv")
VAL_PRED_CSV = File.join(MODEL_DIR, "val_predictions.csv")
TEST_PRED_CSV = File.join(MODEL_DIR, "test_predictions.csv")

SEED = (ENV["SEED"] || "42").to_i
K = (ENV["K"] || "5").to_i
N_INIT = (ENV["N_INIT"] || "30").to_i
MAX_ITERS = (ENV["MAX_ITERS"] || "120").to_i
FOLLOWUP_THRESHOLD = (ENV["FOLLOWUP_THRESHOLD"] || "0.55").to_f
EPS = 1e-9

CONTINUOUS_FEATURES = [
  "age",
  "resting_hr_mean",
  "hrv_sdnn_mean",
  "sit_hr_mean",
  "stand_hr_mean",
  "delta_hr_stand_minus_sit",
  "sit_sbp_mean",
  "stand_sbp_mean",
  "delta_sbp_stand_minus_sit"
].freeze

INDICATOR_FEATURES = CONTINUOUS_FEATURES.reject { |f| f == "age" }.map { |f| "#{f}_missing" }.freeze

def require_file(path)
  return if File.file?(path)
  warn "Missing file: #{path}"
  exit 1
end

def parse_float(value)
  str = value.to_s.strip
  return nil if str.empty?
  Float(str)
rescue ArgumentError
  nil
end

def median(values)
  vals = values.compact.sort
  return nil if vals.empty?
  mid = vals.length / 2
  if vals.length.even?
    (vals[mid - 1] + vals[mid]) / 2.0
  else
    vals[mid]
  end
end

def mean(values)
  return 0.0 if values.empty?
  values.sum / values.length.to_f
end

def stddev(values, avg)
  return 1.0 if values.empty?
  var = values.sum { |v| (v - avg) ** 2 } / values.length.to_f
  sd = Math.sqrt(var)
  sd > EPS ? sd : 1.0
end

def sq_dist(a, b)
  sum = 0.0
  a.each_index do |idx|
    d = a[idx] - b[idx]
    sum += d * d
  end
  sum
end

def nearest_centroid(vector, centroids)
  best_idx = 0
  best_dist = Float::INFINITY
  centroids.each_with_index do |centroid, idx|
    dist = sq_dist(vector, centroid)
    if dist < best_dist
      best_dist = dist
      best_idx = idx
    end
  end
  [best_idx, best_dist]
end

def choose_weighted_index(weights, rng)
  total = weights.sum
  return rng.rand(weights.length) if total <= EPS

  threshold = rng.rand * total
  running = 0.0
  weights.each_with_index do |w, idx|
    running += w
    return idx if running >= threshold
  end
  weights.length - 1
end

def init_kmeans_pp(vectors, k, rng)
  centroids = []
  centroids << vectors[rng.rand(vectors.length)].dup

  while centroids.length < k
    dists = vectors.map { |vec| nearest_centroid(vec, centroids)[1] }
    idx = choose_weighted_index(dists, rng)
    centroids << vectors[idx].dup
  end
  centroids
end

def run_kmeans(vectors, k:, n_init:, max_iters:, seed:)
  rng = Random.new(seed)
  best = nil

  n_init.times do
    centroids = init_kmeans_pp(vectors, k, rng)
    assignments = Array.new(vectors.length, -1)

    max_iters.times do
      changed = false
      vectors.each_with_index do |vec, idx|
        cluster_idx, = nearest_centroid(vec, centroids)
        if assignments[idx] != cluster_idx
          assignments[idx] = cluster_idx
          changed = true
        end
      end

      break unless changed

      sums = Array.new(k) { Array.new(vectors.first.length, 0.0) }
      counts = Array.new(k, 0)

      vectors.each_with_index do |vec, idx|
        cluster = assignments[idx]
        counts[cluster] += 1
        vec.each_index { |dim| sums[cluster][dim] += vec[dim] }
      end

      k.times do |cluster|
        if counts[cluster].zero?
          centroids[cluster] = vectors[rng.rand(vectors.length)].dup
        else
          centroids[cluster] = sums[cluster].map { |v| v / counts[cluster].to_f }
        end
      end
    end

    inertia = vectors.each_with_index.sum do |vec, idx|
      sq_dist(vec, centroids[assignments[idx]])
    end

    candidate = { centroids: centroids, assignments: assignments, inertia: inertia }
    best = candidate if best.nil? || inertia < best[:inertia]
  end

  best
end

def status_from_hint(hint)
  hint == "normal" ? "normal" : "needs_followup"
end

def safe_div(num, den)
  return nil if den.to_f.zero?
  num.to_f / den.to_f
end

def binary_metrics(rows, status_preds)
  tp = 0
  fp = 0
  tn = 0
  fn = 0

  rows.each_with_index do |row, idx|
    actual_pos = row["status_target"] == "needs_followup"
    pred_pos = status_preds[idx] == "needs_followup"
    if pred_pos && actual_pos
      tp += 1
    elsif pred_pos && !actual_pos
      fp += 1
    elsif !pred_pos && !actual_pos
      tn += 1
    else
      fn += 1
    end
  end

  precision = safe_div(tp, tp + fp)
  recall = safe_div(tp, tp + fn)
  f1 = if precision.nil? || recall.nil? || (precision + recall).zero?
         nil
       else
         (2.0 * precision * recall) / (precision + recall)
       end
  accuracy = safe_div(tp + tn, rows.length)

  {
    confusion: { tp: tp, fp: fp, tn: tn, fn: fn },
    precision_needs_followup: precision,
    recall_needs_followup: recall,
    f1_needs_followup: f1,
    accuracy: accuracy
  }
end

def phenotype_metrics(rows, phenotype_preds)
  total = rows.length
  correct = rows.each_with_index.count { |row, idx| row["phenotype_hint_target"] == phenotype_preds[idx] }
  counts = Hash.new(0)
  predicted = Hash.new(0)
  by_class_correct = Hash.new(0)

  rows.each_with_index do |row, idx|
    actual = row["phenotype_hint_target"].to_s
    pred = phenotype_preds[idx].to_s
    counts[actual] += 1
    predicted[pred] += 1
    by_class_correct[actual] += 1 if actual == pred
  end

  per_class_recall = {}
  counts.each { |klass, n| per_class_recall[klass] = safe_div(by_class_correct[klass], n) }

  {
    exact_accuracy: safe_div(correct, total),
    support_by_class: counts.sort.to_h,
    predicted_by_class: predicted.sort.to_h,
    recall_by_class: per_class_recall.sort.to_h
  }
end

def rows_from_csv(path)
  CSV.read(path, headers: true)
end

def compute_preprocess(rows)
  medians = {}
  CONTINUOUS_FEATURES.each do |feature|
    values = rows.map { |r| parse_float(r[feature]) }
    medians[feature] = median(values) || 0.0
  end

  vectors = rows.map do |row|
    base = CONTINUOUS_FEATURES.map do |feature|
      value = parse_float(row[feature])
      value.nil? ? medians[feature] : value
    end
    indicators = CONTINUOUS_FEATURES.reject { |f| f == "age" }.map do |feature|
      parse_float(row[feature]).nil? ? 1.0 : 0.0
    end
    base + indicators
  end

  means = []
  stds = []
  dim_count = vectors.first.length
  dim_count.times do |dim|
    col = vectors.map { |vec| vec[dim] }
    avg = mean(col)
    means << avg
    stds << stddev(col, avg)
  end

  [vectors, medians, means, stds]
end

def transform_rows(rows, medians:, means:, stds:)
  rows.map do |row|
    base = CONTINUOUS_FEATURES.map do |feature|
      value = parse_float(row[feature])
      value.nil? ? medians[feature] : value
    end
    indicators = CONTINUOUS_FEATURES.reject { |f| f == "age" }.map do |feature|
      parse_float(row[feature]).nil? ? 1.0 : 0.0
    end
    unscaled = base + indicators
    unscaled.each_with_index.map { |value, idx| (value - means[idx]) / stds[idx] }
  end
end

def map_clusters_to_hints(train_rows, assignments, k, followup_threshold:)
  counts = Array.new(k) { Hash.new(0) }
  train_rows.each_with_index do |row, idx|
    cluster = assignments[idx]
    hint = row["phenotype_hint_target"].to_s
    counts[cluster][hint] += 1
  end

  hint_map = {}
  status_map = {}
  purity = {}
  followup_rates = {}

  counts.each_with_index do |label_counts, cluster|
    if label_counts.empty?
      hint_map[cluster.to_s] = "normal"
      status_map[cluster.to_s] = "normal"
      purity[cluster.to_s] = 0.0
      followup_rates[cluster.to_s] = 0.0
      next
    end

    total = label_counts.values.sum
    followup_count = total - label_counts.fetch("normal", 0)
    followup_rate = followup_count / total.to_f
    followup_rates[cluster.to_s] = followup_rate

    status = followup_rate >= followup_threshold ? "needs_followup" : "normal"
    hint =
      if status == "normal"
        "normal"
      else
        non_normal = label_counts.reject { |label, _| label == "normal" }
        if non_normal.empty?
          "unspecified_autonomic"
        else
          non_normal.sort_by { |label, count| [-count, label] }.first[0]
        end
      end

    dominant = label_counts.fetch(hint, 0)

    hint_map[cluster.to_s] = hint
    status_map[cluster.to_s] = status
    purity[cluster.to_s] = dominant / total.to_f
  end

  {
    hint_map: hint_map,
    status_map: status_map,
    counts: counts.map { |c| c.sort.to_h },
    purity: purity,
    followup_rates: followup_rates,
    followup_threshold: followup_threshold
  }
end

def predict_rows(rows, vectors, centroids, hint_map, status_map)
  phenotype_preds = []
  status_preds = []
  clusters = []
  distances = []

  vectors.each do |vec|
    cluster, dist = nearest_centroid(vec, centroids)
    hint = hint_map[cluster.to_s] || "normal"
    status = status_map[cluster.to_s] || status_from_hint(hint)
    phenotype_preds << hint
    status_preds << status
    clusters << cluster
    distances << dist
  end

  metrics = {
    binary: binary_metrics(rows, status_preds),
    phenotype: phenotype_metrics(rows, phenotype_preds)
  }

  {
    phenotype_preds: phenotype_preds,
    status_preds: status_preds,
    clusters: clusters,
    distances: distances,
    metrics: metrics
  }
end

def write_prediction_csv(path, rows, predictions)
  headers = %w[source_subject_id source_group status_target phenotype_hint_target status_pred phenotype_pred cluster_id distance_to_centroid]
  CSV.open(path, "w") do |csv|
    csv << headers
    rows.each_with_index do |row, idx|
      csv << [
        row["source_subject_id"],
        row["source_group"],
        row["status_target"],
        row["phenotype_hint_target"],
        predictions[:status_preds][idx],
        predictions[:phenotype_preds][idx],
        predictions[:clusters][idx],
        predictions[:distances][idx].round(6)
      ]
    end
  end
end

require_file(TRAIN_CSV)
require_file(VAL_CSV)
require_file(TEST_CSV)

train_rows = rows_from_csv(TRAIN_CSV)
val_rows = rows_from_csv(VAL_CSV)
test_rows = rows_from_csv(TEST_CSV)

if train_rows.size < K
  warn "Train rows (#{train_rows.size}) are fewer than K=#{K}"
  exit 1
end

train_vectors_unscaled, medians, means, stds = compute_preprocess(train_rows)
train_vectors = train_vectors_unscaled.map do |vec|
  vec.each_with_index.map { |value, idx| (value - means[idx]) / stds[idx] }
end

kmeans = run_kmeans(train_vectors, k: K, n_init: N_INIT, max_iters: MAX_ITERS, seed: SEED)
cluster_mapping = map_clusters_to_hints(
  train_rows,
  kmeans[:assignments],
  K,
  followup_threshold: FOLLOWUP_THRESHOLD
)

train_pred = predict_rows(
  train_rows,
  train_vectors,
  kmeans[:centroids],
  cluster_mapping[:hint_map],
  cluster_mapping[:status_map]
)
val_vectors = transform_rows(val_rows, medians: medians, means: means, stds: stds)
test_vectors = transform_rows(test_rows, medians: medians, means: means, stds: stds)
val_pred = predict_rows(
  val_rows,
  val_vectors,
  kmeans[:centroids],
  cluster_mapping[:hint_map],
  cluster_mapping[:status_map]
)
test_pred = predict_rows(
  test_rows,
  test_vectors,
  kmeans[:centroids],
  cluster_mapping[:hint_map],
  cluster_mapping[:status_map]
)

FileUtils.mkdir_p(MODEL_DIR)
write_prediction_csv(TRAIN_PRED_CSV, train_rows, train_pred)
write_prediction_csv(VAL_PRED_CSV, val_rows, val_pred)
write_prediction_csv(TEST_PRED_CSV, test_rows, test_pred)

model_artifact = {
  created_at: Time.now.utc.iso8601,
  algorithm: "kmeans",
  config: {
    k: K,
    n_init: N_INIT,
    max_iters: MAX_ITERS,
    seed: SEED,
    followup_threshold: FOLLOWUP_THRESHOLD
  },
  feature_space: {
    continuous_features: CONTINUOUS_FEATURES,
    indicator_features: INDICATOR_FEATURES,
    all_features: CONTINUOUS_FEATURES + INDICATOR_FEATURES
  },
  preprocess: {
    medians: medians,
    means: means,
    stds: stds
  },
  centroids: kmeans[:centroids],
  train_inertia: kmeans[:inertia],
  cluster_label_counts: cluster_mapping[:counts],
  cluster_purity: cluster_mapping[:purity],
  cluster_followup_rates: cluster_mapping[:followup_rates],
  cluster_hint_map: cluster_mapping[:hint_map],
  cluster_status_map: cluster_mapping[:status_map]
}

evaluation_artifact = {
  created_at: Time.now.utc.iso8601,
  train: train_pred[:metrics],
  val: val_pred[:metrics],
  test: test_pred[:metrics],
  row_counts: {
    train: train_rows.size,
    val: val_rows.size,
    test: test_rows.size
  }
}

File.write(MODEL_JSON, JSON.pretty_generate(model_artifact))
File.write(EVAL_JSON, JSON.pretty_generate(evaluation_artifact))

puts "Saved model: #{MODEL_JSON}"
puts "Saved evaluation: #{EVAL_JSON}"
puts "Val precision (needs_followup): #{val_pred.dig(:metrics, :binary, :precision_needs_followup)}"
puts "Test precision (needs_followup): #{test_pred.dig(:metrics, :binary, :precision_needs_followup)}"
