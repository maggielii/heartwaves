# frozen_string_literal: true

require "date"

module Screening
  module Baseline
    BP_KEYS = %i[systolic_bp_mean diastolic_bp_mean bp_systolic_mean bp_diastolic_mean].freeze

    def self.run(imported)
      daily = imported.fetch("daily") { imported[:daily] }
      raise "No daily series computed" if daily.nil? || daily.empty?

      rhr = series_for(daily, :resting_hr_mean)
      hrv = series_for(daily, :hrv_sdnn_mean)
      stand = series_for(daily, :stand_minutes)
      active = series_for(daily, :active_minutes)

      # We use robust stats so a few odd days don't dominate.
      rhr_stats = robust_stats(rhr)
      hrv_stats = robust_stats(hrv)
      stand_stats = robust_stats(stand)
      active_stats = robust_stats(active)

      recent_days = 7
      recent = daily.last(recent_days)

      recent_rhr = series_for(recent, :resting_hr_mean)
      recent_hrv = series_for(recent, :hrv_sdnn_mean)
      recent_stand = series_for(recent, :stand_minutes)
      recent_active = series_for(recent, :active_minutes)

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
      bp_data_present = bp_data_present?(daily)

      phenotype = classify_phenotype(
        status: status,
        signals: signals,
        stand_stats: stand_stats,
        recent_stand: recent_stand,
        recent_active: recent_active,
        bp_data_present: bp_data_present
      )
      notes.concat(phenotype[:notes])

      questionnaire = questionnaire_for(
        status: status,
        phenotype_hint: phenotype[:hint],
        bp_data_present: bp_data_present
      )

      {
        status: status,
        phenotype_hint: phenotype[:hint],
        phenotype_confidence: phenotype[:confidence],
        phenotype_reason: phenotype[:reason],
        bp_data_present: bp_data_present,
        signals: signals,
        questionnaire: questionnaire,
        safety_notes: [
          "This tool is not a diagnosis.",
          "If you have chest pain, severe shortness of breath, fainting, or severe symptoms, seek urgent medical care."
        ],
        data_notes: notes.uniq,
        stats: {
          resting_hr: rhr_stats,
          hrv_sdnn: hrv_stats,
          stand_minutes: stand_stats,
          active_minutes: active_stats
        }
      }
    end

    def self.series_for(rows, key)
      rows.map { |row| value_for(row, key) }.compact
    end

    def self.value_for(row, key)
      val = row[key] || row[key.to_s]
      return nil if val.nil?
      num = val.to_f
      num.finite? ? num : nil
    end

    def self.bp_data_present?(daily)
      daily.any? do |row|
        BP_KEYS.any? { |key| !value_for(row, key).nil? }
      end
    end

    def self.signal_keys(signals)
      signals.map { |s| (s[:key] || s["key"]).to_s }
    end

    def self.classify_phenotype(status:, signals:, stand_stats:, recent_stand:, recent_active:, bp_data_present:)
      if status == "normal"
        return {
          hint: "normal",
          confidence: "high",
          reason: "No strong autonomic risk pattern was detected in this 30-day window.",
          notes: []
        }
      end

      keys = signal_keys(signals)
      has_tachy = keys.include?("elevated_resting_hr")
      has_hrv_suppression = keys.include?("suppressed_hrv")
      stand_recent_mean = mean(recent_stand)
      active_recent_mean = mean(recent_active)
      stand_baseline = stand_stats && stand_stats[:median]
      stand_shift = if stand_recent_mean && stand_baseline
                      stand_recent_mean - stand_baseline
                    end

      if has_tachy
        if stand_shift && stand_shift <= -5.0
          return {
            hint: "ist_like",
            confidence: "high",
            reason: "Elevated resting heart-rate pattern appears less tied to standing load, which is more IST-like than orthostatic.",
            notes: []
          }
        end

        return {
          hint: "pots_like",
          confidence: "high",
          reason: "Elevated resting heart-rate trend with orthostatic-focused signals suggests a POTS-like follow-up pattern.",
          notes: []
        }
      end

      if has_hrv_suppression
        hint = (stand_shift && stand_shift >= 5.0) ? "vvs_like" : "oh_like"
        reason =
          if hint == "vvs_like"
            "Autonomic suppression pattern overlaps with vasovagal-like states, but confirmation requires blood-pressure context."
          else
            "Autonomic suppression pattern could overlap orthostatic hypotension-like states, but blood-pressure confirmation is needed."
          end
        notes = []
        unless bp_data_present
          notes << "Blood pressure data not present; OH/VVS hints are low-confidence until BP trends are available."
        end
        return {
          hint: hint,
          confidence: "low",
          reason: reason,
          notes: notes
        }
      end

      notes = []
      unless bp_data_present
        notes << "Blood pressure data not present; subtype confidence is limited."
      end
      if active_recent_mean && active_recent_mean >= 45.0
        notes << "Higher recent activity may contribute to non-specific autonomic signals."
      end
      {
        hint: "unspecified_autonomic",
        confidence: "low",
        reason: "Follow-up pattern detected, but no specific dysautonomia-like subtype was high-confidence.",
        notes: notes
      }
    end

    def self.questionnaire_for(status:, phenotype_hint:, bp_data_present:)
      return normal_questionnaire if status == "normal"

      case phenotype_hint
      when "pots_like"
        [
          q("orthostatic", "Do symptoms worsen when standing and improve when lying down?", %w[no unsure yes]),
          q("tachy_upright", "Do you notice rapid heartbeat shortly after standing?", %w[no unsure yes]),
          q("brain_fog", "Any brain fog, fatigue, or reduced concentration on upright days?", %w[no mild moderate severe]),
          q("heat_trigger", "Do heat, hot showers, or long standing make symptoms worse?", %w[no sometimes often]),
          q("hydration", "Do fluids/salt intake noticeably change your symptoms?", %w[no unsure yes])
        ]
      when "ist_like"
        [
          q("fast_resting_hr", "Do you notice persistent fast heart rate even while resting?", %w[no sometimes often]),
          q("palpitations_rest", "Do palpitations happen while seated or lying down?", %w[no sometimes often]),
          q("standing_relation", "Are symptoms mainly triggered by standing (vs present regardless of posture)?", %w[mostly_posture mixed regardless_posture]),
          q("stimulants", "Any caffeine/energy drink or stimulant use on high-HR days?", %w[no low high]),
          q("med_changes", "Any medication changes in the last 30 days?", %w[no unsure yes])
        ]
      when "oh_like"
        low_confidence_oh_questionnaire(bp_data_present: bp_data_present)
      when "vvs_like"
        low_confidence_vvs_questionnaire(bp_data_present: bp_data_present)
      else
        [
          q("orthostatic", "Do symptoms worsen when standing and improve when lying down?", %w[no unsure yes]),
          q("presyncope", "Any near-fainting or fainting episodes in the last 30 days?", %w[no near_faint faint]),
          q("tachy", "Do you notice a rapid heart rate upon standing?", %w[no unsure yes]),
          q("hydration", "Have you increased fluids/salt recently or been dehydrated?", %w[no unsure yes]),
          q("illness", "Any recent illness, fever, or new medication changes?", %w[no unsure yes])
        ]
      end
    end

    def self.normal_questionnaire
      [
        q("fatigue", "In the last 30 days, have you had unusual fatigue?", %w[no mild moderate severe]),
        q("dizziness", "In the last 30 days, have you had dizziness when standing?", %w[no sometimes often]),
        q("palpitations", "In the last 30 days, have you had palpitations/rapid heartbeat episodes?", %w[no sometimes often])
      ]
    end

    def self.low_confidence_oh_questionnaire(bp_data_present:)
      items = [
        q("dizzy_standing", "Do you feel lightheaded within a few minutes of standing?", %w[no sometimes often]),
        q("vision_dim", "Do you notice dim vision or weakness when upright?", %w[no sometimes often]),
        q("presyncope", "Any near-fainting/fainting episodes in the last 30 days?", %w[no near_faint faint]),
        q("recovery_lying", "Do symptoms improve quickly after sitting or lying down?", %w[no unsure yes])
      ]
      if bp_data_present
        items << q("bp_drop", "If measured, does your blood pressure drop after standing?", %w[no unsure yes])
      else
        items << q("bp_not_measured", "Have you measured blood pressure lying and then standing during symptoms?", %w[not_measured once multiple_times])
      end
      items
    end

    def self.low_confidence_vvs_questionnaire(bp_data_present:)
      items = [
        q("trigger_pattern", "Do episodes follow triggers like prolonged standing, heat, pain, or stress?", %w[no sometimes often]),
        q("warning_signs", "Before symptoms, do you get nausea, sweating, or tunnel vision?", %w[no sometimes often]),
        q("fainting", "Any brief loss of consciousness in the last 30 days?", %w[no once multiple]),
        q("position_relief", "Do symptoms improve after lying down?", %w[no unsure yes])
      ]
      if bp_data_present
        items << q("bp_during_event", "If measured during events, does blood pressure drop?", %w[no unsure yes])
      else
        items << q("bp_not_measured", "Would you be able to record seated/standing BP during a future episode?", %w[no maybe yes])
      end
      items
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
