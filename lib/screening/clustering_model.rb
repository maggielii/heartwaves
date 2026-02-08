# frozen_string_literal: true

require "json"

module Screening
  module ClusteringModel
    ROOT = File.expand_path("../..", __dir__)
    DEFAULT_MODEL_PATH = File.join(ROOT, "data", "models", "clustering_baseline", "model.json")

    def self.available?(path = DEFAULT_MODEL_PATH)
      File.file?(path)
    end

    def self.score(imported:, orthostatic_override: nil, model_path: DEFAULT_MODEL_PATH)
      return nil unless available?(model_path)

      model = JSON.parse(File.read(model_path))
      feature_space = model.fetch("feature_space")
      preprocess = model.fetch("preprocess")

      continuous = Array(feature_space["continuous_features"])
      indicators = Array(feature_space["indicator_features"])
      all_features = Array(feature_space["all_features"])

      raw_values = build_feature_values(imported, continuous, orthostatic_override: orthostatic_override)
      vector = build_vector(
        raw_values: raw_values,
        continuous: continuous,
        indicators: indicators,
        all_features: all_features,
        medians: preprocess.fetch("medians"),
        means: preprocess.fetch("means"),
        stds: preprocess.fetch("stds")
      )

      centroids = Array(model["centroids"])
      cluster_idx, dist = nearest_centroid(vector, centroids)

      cluster_id = cluster_idx.to_s
      hint = model.dig("cluster_hint_map", cluster_id).to_s
      status = model.dig("cluster_status_map", cluster_id).to_s
      purity = model.dig("cluster_purity", cluster_id).to_f
      followup_rate = model.dig("cluster_followup_rates", cluster_id).to_f
      coverage = feature_coverage(raw_values)

      hint = "normal" if hint.empty?
      status = hint == "normal" ? "normal" : "needs_followup" if status.empty?
      confidence = confidence_for(status: status, purity: purity, coverage: coverage)

      {
        source: "kmeans_baseline",
        model_path: model_path,
        status: status,
        phenotype_hint: hint,
        confidence: confidence,
        reason: reason_for(
          status: status,
          hint: hint,
          confidence: confidence,
          purity: purity,
          followup_rate: followup_rate,
          coverage: coverage
        ),
        cluster_id: cluster_idx,
        distance_to_centroid: dist.round(6),
        cluster_purity: purity.round(4),
        cluster_followup_rate: followup_rate.round(4),
        feature_coverage: coverage.round(4),
        features_used: raw_values
      }
    rescue StandardError => e
      { source: "kmeans_baseline", error: e.message }
    end

    def self.build_feature_values(imported, continuous_features, orthostatic_override: nil)
      daily = imported["daily"] || imported[:daily] || []
      values = {}
      continuous_features.each { |feature| values[feature] = nil }
      ortho = orthostatic_override || imported["orthostatic_input"] || imported[:orthostatic_input] || {}

      if continuous_features.include?("resting_hr_mean")
        values["resting_hr_mean"] = mean(daily.map { |d| d["resting_hr_mean"] || d[:resting_hr_mean] })
      end
      if continuous_features.include?("hrv_sdnn_mean")
        values["hrv_sdnn_mean"] = mean(daily.map { |d| d["hrv_sdnn_mean"] || d[:hrv_sdnn_mean] })
      end
      if continuous_features.include?("age")
        values["age"] = numeric(imported["age"] || imported[:age])
      end

      if continuous_features.include?("sit_hr_mean")
        values["sit_hr_mean"] = numeric(ortho_value(ortho, "sit_hr_mean", :sit_hr_mean, "rest_hr", :rest_hr))
      end
      if continuous_features.include?("stand_hr_mean")
        values["stand_hr_mean"] = numeric(ortho_value(ortho, "stand_hr_mean", :stand_hr_mean))
      end
      if continuous_features.include?("sit_sbp_mean")
        values["sit_sbp_mean"] = numeric(ortho_value(ortho, "sit_sbp_mean", :sit_sbp_mean, "rest_sbp", :rest_sbp))
      end
      if continuous_features.include?("stand_sbp_mean")
        values["stand_sbp_mean"] = numeric(ortho_value(ortho, "stand_sbp_mean", :stand_sbp_mean))
      end
      if continuous_features.include?("delta_hr_stand_minus_sit")
        values["delta_hr_stand_minus_sit"] = numeric(ortho_value(ortho, "delta_hr_stand_minus_sit", :delta_hr_stand_minus_sit))
        if values["delta_hr_stand_minus_sit"].nil? && values["sit_hr_mean"] && values["stand_hr_mean"]
          values["delta_hr_stand_minus_sit"] = values["stand_hr_mean"] - values["sit_hr_mean"]
        end
      end
      if continuous_features.include?("delta_sbp_stand_minus_sit")
        values["delta_sbp_stand_minus_sit"] = numeric(ortho_value(ortho, "delta_sbp_stand_minus_sit", :delta_sbp_stand_minus_sit))
        if values["delta_sbp_stand_minus_sit"].nil? && values["sit_sbp_mean"] && values["stand_sbp_mean"]
          values["delta_sbp_stand_minus_sit"] = values["stand_sbp_mean"] - values["sit_sbp_mean"]
        end
      end

      values
    end

    def self.ortho_value(ortho, *keys)
      keys.each do |key|
        return ortho[key] if ortho.is_a?(Hash) && ortho.key?(key)
      end
      nil
    end

    def self.numeric(value)
      return nil if value.nil?
      return value.to_f if value.is_a?(Numeric)

      text = value.to_s.strip
      return nil if text.empty?
      Float(text)
    rescue ArgumentError
      nil
    end

    def self.feature_coverage(values)
      total = values.keys.length.to_f
      present = values.values.count { |v| !v.nil? }
      return 0.0 if total.zero?
      present / total
    end

    def self.build_vector(raw_values:, continuous:, indicators:, all_features:, medians:, means:, stds:)
      unscaled = {}

      continuous.each do |feature|
        val = raw_values[feature]
        unscaled[feature] = val.nil? ? medians.fetch(feature, 0.0).to_f : val.to_f
      end

      indicators.each do |feature|
        base = feature.sub(/_missing\z/, "")
        unscaled[feature] = raw_values[base].nil? ? 1.0 : 0.0
      end

      vector = []
      all_features.each_with_index do |feature, idx|
        value = unscaled.fetch(feature, 0.0).to_f
        mean = means[idx].to_f
        std = stds[idx].to_f
        std = 1.0 if std.zero?
        vector << ((value - mean) / std)
      end
      vector
    end

    def self.nearest_centroid(vector, centroids)
      best_idx = 0
      best_dist = Float::INFINITY
      centroids.each_with_index do |centroid, idx|
        dist = sq_dist(vector, centroid)
        if dist < best_dist
          best_idx = idx
          best_dist = dist
        end
      end
      [best_idx, best_dist]
    end

    def self.sq_dist(a, b)
      sum = 0.0
      a.each_with_index do |val, idx|
        d = val.to_f - b[idx].to_f
        sum += d * d
      end
      sum
    end

    def self.confidence_for(status:, purity:, coverage:)
      base =
        if purity >= 0.75
          "high"
        elsif purity >= 0.55
          "medium"
        else
          "low"
        end

      if coverage < 0.35
        return "low" if status == "needs_followup"
        return base == "high" ? "medium" : base
      end

      base
    end

    def self.reason_for(status:, hint:, confidence:, purity:, followup_rate:, coverage:)
      if status == "needs_followup"
        "Cluster pattern suggests #{hint.tr('_', '-')} (confidence #{confidence}; cluster purity #{(purity * 100).round(1)}%; follow-up rate #{(followup_rate * 100).round(1)}%; feature coverage #{(coverage * 100).round(1)}%)."
      else
        "Cluster pattern aligns with normal range (confidence #{confidence}; cluster purity #{(purity * 100).round(1)}%; feature coverage #{(coverage * 100).round(1)}%)."
      end
    end

    def self.mean(values)
      nums = values.compact.map(&:to_f)
      return nil if nums.empty?
      nums.sum / nums.length.to_f
    end
  end
end
