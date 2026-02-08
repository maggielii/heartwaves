# frozen_string_literal: true

require "date"

module Screening
  module Baseline
    def self.run(imported)
      daily = imported.fetch("daily") { imported[:daily] }
      raise "No daily series computed" if daily.nil? || daily.empty?

      rhr = daily.map { |d| d["resting_hr_mean"] || d[:resting_hr_mean] }.compact
      hrv = daily.map { |d| d["hrv_sdnn_mean"] || d[:hrv_sdnn_mean] }.compact

      # We use robust stats so a few odd days don't dominate.
      rhr_stats = robust_stats(rhr)
      hrv_stats = robust_stats(hrv)

      recent_days = 7
      recent = daily.last(recent_days)

      recent_rhr = recent.map { |d| d["resting_hr_mean"] || d[:resting_hr_mean] }.compact
      recent_hrv = recent.map { |d| d["hrv_sdnn_mean"] || d[:hrv_sdnn_mean] }.compact

      signals = []
      notes = []

      if rhr_stats && recent_rhr.length >= 3
        recent_mean = mean(recent_rhr)
        # Needs to be meaningfully above baseline median to flag.
        if recent_mean && recent_mean > (rhr_stats[:median] + [5.0, 1.5 * rhr_stats[:iqr]].max)
          signals << {
            key: "elevated_resting_hr",
            severity: "moderate",
            detail: "Recent 7-day mean resting HR (#{recent_mean.round(1)} bpm) is above baseline median (#{rhr_stats[:median].round(1)} bpm)."
          }
        end
      else
        notes << "Not enough resting HR data to assess trend."
      end

      if hrv_stats && recent_hrv.length >= 3
        recent_mean = mean(recent_hrv)
        if recent_mean && recent_mean < (hrv_stats[:median] - [10.0, 1.5 * hrv_stats[:iqr]].max)
          signals << {
            key: "suppressed_hrv",
            severity: "moderate",
            detail: "Recent 7-day mean HRV SDNN (#{recent_mean.round(1)} ms) is below baseline median (#{hrv_stats[:median].round(1)} ms)."
          }
        end
      else
        notes << "Not enough HRV data to assess trend."
      end

      status = signals.empty? ? "normal" : "needs_followup"

      questionnaire =
        if status == "normal"
          [
            q("fatigue", "In the last 30 days, have you had unusual fatigue?", %w[no mild moderate severe]),
            q("dizziness", "In the last 30 days, have you had dizziness when standing?", %w[no sometimes often]),
            q("palpitations", "In the last 30 days, have you had palpitations/rapid heartbeat episodes?", %w[no sometimes often])
          ]
        else
          [
            q("orthostatic", "Do symptoms worsen when standing and improve when lying down?", %w[no unsure yes]),
            q("presyncope", "Any near-fainting or fainting episodes in the last 30 days?", %w[no near_faint faint]),
            q("tachy", "Do you notice a rapid heart rate upon standing?", %w[no unsure yes]),
            q("hydration", "Have you increased fluids/salt recently or been dehydrated?", %w[no unsure yes]),
            q("illness", "Any recent illness, fever, or new medication changes?", %w[no unsure yes])
          ]
        end

      {
        status: status,
        signals: signals,
        questionnaire: questionnaire,
        safety_notes: [
          "This tool is not a diagnosis.",
          "If you have chest pain, severe shortness of breath, fainting, or severe symptoms, seek urgent medical care."
        ],
        data_notes: notes,
        stats: { resting_hr: rhr_stats, hrv_sdnn: hrv_stats }
      }
    end

    def self.q(id, prompt, options)
      { id: id, prompt: prompt, options: options }
    end

    def self.mean(arr)
      return nil if arr.empty?
      arr.sum / arr.length.to_f
    end

    def self.robust_stats(arr)
      vals = arr.compact.map(&:to_f).sort
      return nil if vals.length < 5

      med = percentile(vals, 50)
      q1 = percentile(vals, 25)
      q3 = percentile(vals, 75)
      iqr = (q3 - q1).abs
      { n: vals.length, median: med, q1: q1, q3: q3, iqr: iqr }
    end

    def self.percentile(sorted_vals, p)
      return nil if sorted_vals.empty?
      rank = (p.to_f / 100.0) * (sorted_vals.length - 1)
      lo = rank.floor
      hi = rank.ceil
      return sorted_vals[lo] if lo == hi

      weight = rank - lo
      sorted_vals[lo] * (1.0 - weight) + sorted_vals[hi] * weight
    end
  end
end

