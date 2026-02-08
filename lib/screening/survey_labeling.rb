# frozen_string_literal: true

module Screening
  module SurveyLabeling
    RULES = {
      "pots_like" => {
        "orthostatic" => { support: %w[yes], against: %w[no] },
        "tachy_upright" => { support: %w[yes], against: %w[no] },
        "brain_fog" => { support: %w[moderate severe], against: %w[no] },
        "heat_trigger" => { support: %w[sometimes often], against: %w[no] },
        "hydration" => { support: %w[yes], against: %w[no] }
      },
      "ist_like" => {
        "fast_resting_hr" => { support: %w[sometimes often], against: %w[no] },
        "palpitations_rest" => { support: %w[sometimes often], against: %w[no] },
        "standing_relation" => { support: %w[mixed regardless_posture], against: %w[mostly_posture] },
        "stimulants" => { support: %w[no], against: %w[high] },
        "med_changes" => { support: %w[no], against: %w[yes] }
      },
      "oh_like" => {
        "dizzy_standing" => { support: %w[sometimes often], against: %w[no] },
        "vision_dim" => { support: %w[sometimes often], against: %w[no] },
        "presyncope" => { support: %w[near_faint faint], against: %w[no] },
        "recovery_lying" => { support: %w[yes], against: %w[no] },
        "bp_drop" => { support: %w[yes], against: %w[no] },
        "bp_not_measured" => { support: %w[multiple_times], against: [] }
      },
      "vvs_like" => {
        "trigger_pattern" => { support: %w[sometimes often], against: %w[no] },
        "warning_signs" => { support: %w[sometimes often], against: %w[no] },
        "fainting" => { support: %w[once multiple], against: %w[no] },
        "position_relief" => { support: %w[yes], against: %w[no] },
        "bp_during_event" => { support: %w[yes], against: %w[no] },
        "bp_not_measured" => { support: %w[yes], against: [] }
      },
      "unspecified_autonomic" => {
        "orthostatic" => { support: %w[yes], against: %w[no] },
        "presyncope" => { support: %w[near_faint faint], against: %w[no] },
        "tachy" => { support: %w[yes], against: %w[no] },
        "illness" => { support: %w[no], against: %w[yes] },
        "med_changes" => { support: %w[no], against: %w[yes] }
      }
    }.freeze

    SEVERE_FLAGS = {
      "presyncope" => %w[faint],
      "fainting" => %w[once multiple]
    }.freeze

    def self.apply!(screening:, symptoms:)
      return nil unless screening.is_a?(Hash)

      status = s_get(screening, :status).to_s
      hint = normalized_hint(s_get(screening, :phenotype_hint))
      answers = answer_map(symptoms)
      assessment = assess(status: status, hint: hint, answers: answers)

      s_set(screening, :survey_assessment, assessment)
      append_note(screening, assessment["summary"])

      return assessment unless status == "needs_followup"

      case assessment["alignment"]
      when "supports"
        s_set(screening, :phenotype_confidence, promote_confidence(s_get(screening, :phenotype_confidence)))
        s_set(
          screening,
          :phenotype_reason,
          "Survey answers align with #{format_hint(hint)} symptoms and support follow-up."
        )
      when "does_not_support"
        severe_red_flag = assessment["severe_red_flag"] == true
        confidence = s_get(screening, :phenotype_confidence)

        if !severe_red_flag && confidence_rank(confidence) <= 2
          s_set(screening, :status, "normal")
          s_set(screening, :phenotype_hint, "normal")
          s_set(screening, :phenotype_confidence, "medium")
          s_set(screening, :phenotype_reason, "Follow-up cluster signal was not supported by symptom answers in this window.")
          s_set(screening, :questionnaire, Screening::Baseline.normal_questionnaire)
          append_note(screening, "Survey downgraded status to normal due to low symptom alignment.")
        else
          s_set(screening, :phenotype_confidence, demote_confidence(confidence))
          s_set(screening, :phenotype_reason, "Follow-up signal remains, but symptom answers did not strongly match the predicted subtype.")
        end
      when "mixed"
        confidence = s_get(screening, :phenotype_confidence)
        s_set(screening, :phenotype_confidence, demote_confidence(confidence)) if confidence_rank(confidence) >= 2
        s_set(screening, :phenotype_reason, "Symptom answers were mixed for #{format_hint(hint)} pattern; continue monitoring and re-check.")
      else
        s_set(screening, :phenotype_reason, "Not enough symptom answers yet to validate the follow-up pattern.")
      end

      if s_get(screening, :status).to_s == "needs_followup"
        bp_data_present = !!s_get(screening, :bp_data_present)
        current_hint = normalized_hint(s_get(screening, :phenotype_hint))
        s_set(
          screening,
          :questionnaire,
          Screening::Baseline.questionnaire_for(
            status: "needs_followup",
            phenotype_hint: current_hint,
            bp_data_present: bp_data_present
          )
        )
      end

      assessment
    end

    def self.assess(status:, hint:, answers:)
      rules = RULES.fetch(hint, RULES["unspecified_autonomic"])

      informative = 0
      support_votes = 0
      against_votes = 0
      raw_score = 0.0

      answers.each do |question_id, answer|
        rule = rules[question_id]
        next if rule.nil?

        informative += 1
        if includes?(rule[:support], answer)
          support_votes += 1
          raw_score += 1.0
        elsif includes?(rule[:against], answer)
          against_votes += 1
          raw_score -= 1.0
        end
      end

      severe_red_flag = severe_red_flag?(answers)
      support_score = informative.zero? ? 0.0 : (raw_score / informative.to_f)
      alignment =
        if informative < 2
          "inconclusive"
        elsif severe_red_flag || support_score >= 0.35
          "supports"
        elsif support_score <= -0.25
          "does_not_support"
        else
          "mixed"
        end

      {
        "status_context" => status,
        "hint_context" => hint,
        "answered_count" => answers.length,
        "informative_answers" => informative,
        "support_votes" => support_votes,
        "against_votes" => against_votes,
        "support_score" => support_score.round(3),
        "alignment" => alignment,
        "severe_red_flag" => severe_red_flag,
        "summary" => summary_for(hint: hint, alignment: alignment, support_score: support_score, informative: informative)
      }
    end

    def self.summary_for(hint:, alignment:, support_score:, informative:)
      "Survey alignment for #{format_hint(hint)}: #{alignment} "\
      "(score #{format('%.2f', support_score)}, informative answers #{informative})."
    end

    def self.answer_map(symptoms)
      items =
        if symptoms.is_a?(Hash)
          Array(symptoms["answers"] || symptoms[:answers])
        else
          Array(symptoms)
        end

      mapped = {}
      items.each do |item|
        next unless item.is_a?(Hash)

        id = (item["id"] || item[:id]).to_s.strip
        answer = (item["answer"] || item[:answer]).to_s.strip.downcase
        next if id.empty? || answer.empty?

        mapped[id] = answer
      end
      mapped
    end

    def self.severe_red_flag?(answers)
      SEVERE_FLAGS.any? do |question_id, severe_values|
        value = answers[question_id]
        value && includes?(severe_values, value)
      end
    end

    def self.normalized_hint(hint)
      str = hint.to_s.strip
      return "unspecified_autonomic" if str.empty?
      str
    end

    def self.format_hint(hint)
      hint.to_s.tr("_", "-")
    end

    def self.includes?(values, value)
      Array(values).map(&:to_s).include?(value.to_s)
    end

    def self.promote_confidence(confidence)
      case confidence.to_s
      when "low" then "medium"
      when "medium" then "high"
      else confidence.to_s.empty? ? "medium" : confidence.to_s
      end
    end

    def self.demote_confidence(confidence)
      case confidence.to_s
      when "high" then "medium"
      when "medium" then "low"
      when "low" then "low"
      else "low"
      end
    end

    def self.confidence_rank(confidence)
      case confidence.to_s
      when "high" then 3
      when "medium" then 2
      when "low" then 1
      else 0
      end
    end

    def self.append_note(screening, message)
      return if message.to_s.strip.empty?

      notes = Array(s_get(screening, :data_notes))
      notes << message
      s_set(screening, :data_notes, notes.uniq)
    end

    def self.s_get(hash, key)
      return hash[key.to_s] if hash.key?(key.to_s)
      return hash[key.to_sym] if hash.key?(key.to_sym)
      nil
    end

    def self.s_set(hash, key, value)
      if hash.key?(key.to_sym)
        hash[key.to_sym] = value
      else
        hash[key.to_s] = value
      end
    end
  end
end
