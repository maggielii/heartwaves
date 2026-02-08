# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module LLM
  module Gemini
    DEFAULT_MODEL = "gemini-2.5-flash".freeze

    # Uses the Gemini Developer API (AI Studio) key.
    # If you are using Vertex AI instead, this module will need to change.
    API_BASE = "https://generativelanguage.googleapis.com/v1beta".freeze

    def self.screen(imported:, baseline_screening:)
      key = ENV["GEMINI_API_KEY"].to_s.strip
      key = ENV["GOOGLE_API_KEY"].to_s.strip if key.empty?
      raise "Missing GEMINI_API_KEY/GOOGLE_API_KEY" if key.empty?

      model = ENV["GEMINI_MODEL"].to_s.strip
      model = DEFAULT_MODEL if model.empty?

      summary = build_summary(imported: imported, baseline_screening: baseline_screening)
      prompt = build_prompt(summary)

      uri = URI.parse("#{API_BASE}/models/#{model}:generateContent")
      req_body = {
        contents: [
          {
            role: "user",
            parts: [{ text: prompt }]
          }
        ],
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: 900
        }
      }

      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"] = "application/json"
      req["x-goog-api-key"] = key
      req.body = JSON.generate(req_body)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 8
      http.read_timeout = 25
      http.write_timeout = 25 if http.respond_to?(:write_timeout=)
      res = http.request(req)
      raise "Gemini HTTP #{res.code}: #{res.body.to_s[0, 300]}" unless res.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(res.body)
      text = parsed.dig("candidates", 0, "content", "parts", 0, "text").to_s
      json_str = extract_json(text)
      out = JSON.parse(json_str)

      # Minimal normalization for downstream UI.
      out["status"] = out["status"].to_s
      out["signals"] = Array(out["signals"])
      out["questionnaire"] = Array(out["questionnaire"])
      out["doctor_summary_bullets"] = Array(out["doctor_summary_bullets"])
      out["safety_notes"] = Array(out["safety_notes"])
      out
    end

    def self.build_summary(imported:, baseline_screening:)
      daily = imported[:daily] || imported["daily"] || []
      last7 = daily.last(7)

      {
        window: {
          start_date: imported[:start_date] || imported["start_date"],
          end_date: imported[:end_date] || imported["end_date"],
          window_days: imported[:window_days] || imported["window_days"]
        },
        recent_7d: {
          resting_hr_mean: mean(last7.map { |d| d[:resting_hr_mean] || d["resting_hr_mean"] }),
          hrv_sdnn_mean: mean(last7.map { |d| d[:hrv_sdnn_mean] || d["hrv_sdnn_mean"] }),
          stand_minutes_total: sum(last7.map { |d| d[:stand_minutes] || d["stand_minutes"] }),
          active_minutes_total: sum(last7.map { |d| d[:active_minutes] || d["active_minutes"] })
        },
        baseline_stats: baseline_screening[:stats] || baseline_screening["stats"] || {},
        missingness: {
          days_with_resting_hr: daily.count { |d| !(d[:resting_hr_mean] || d["resting_hr_mean"]).nil? },
          days_with_hrv: daily.count { |d| !(d[:hrv_sdnn_mean] || d["hrv_sdnn_mean"]).nil? }
        },
        baseline_status: baseline_screening[:status] || baseline_screening["status"],
        baseline_signals: baseline_screening[:signals] || baseline_screening["signals"] || []
      }
    end

    def self.build_prompt(summary)
      <<~PROMPT
        You are assisting with a non-diagnostic health screening and self-advocacy tool.
        You must be conservative, avoid diagnosis, and avoid claiming certainty.

        INPUT: You will receive aggregated wearable features only (no raw streams).
        TASK: Produce JSON ONLY matching this schema:
        {
          "status": "normal" | "needs_followup",
          "signals": [{"key": string, "severity": "low"|"moderate"|"high", "detail": string}],
          "questionnaire": [{"id": string, "prompt": string, "options": [string]}],
          "doctor_summary_bullets": [string],
          "safety_notes": [string]
        }

        Rules:
        - Do not diagnose (no "you have POTS" etc). Use "may warrant evaluation" phrasing.
        - Status means: "needs_followup" if patterns or missingness suggest talking to a clinician.
        - Keep signals to 2-5 items max and make them specific to the numbers provided.
        - Questionnaire should be 5-8 questions if needs_followup, otherwise 3-5.
        - Include a safety note about urgent red flags (chest pain, fainting, severe shortness of breath).
        - Use dysautonomia examples only as "possible issues to watch for" (e.g., orthostatic intolerance/POTS-like patterns).

        SUMMARY JSON:
        #{JSON.pretty_generate(summary)}
      PROMPT
    end

    def self.extract_json(text)
      t = text.to_s.strip
      t = t.gsub(/\A```(?:json)?\s*/i, "").gsub(/```\s*\z/, "").strip
      return t if t.start_with?("{") && t.end_with?("}")

      # Fallback: extract the first {...} block.
      if (m = t.match(/\{.*\}/m))
        return m[0]
      end

      raise "Gemini did not return JSON"
    rescue Net::OpenTimeout, Net::ReadTimeout
      raise "Gemini timed out; try again or uncheck Use Gemini."
    end

    def self.mean(arr)
      xs = arr.compact.map(&:to_f)
      return nil if xs.empty?
      (xs.sum / xs.length.to_f).round(2)
    end

    def self.sum(arr)
      xs = arr.compact.map(&:to_f)
      xs.sum.round(2)
    end
  end
end
