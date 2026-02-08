#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "securerandom"
require "fileutils"
require "time"
require "webrick"

require_relative "lib/apple_health/import"
require_relative "lib/llm/gemini"
require_relative "lib/screening/baseline"
require_relative "lib/screening/clustering_model"
require_relative "lib/screening/survey_labeling"

ROOT = File.expand_path(__dir__)
PUBLIC_DIR = File.join(ROOT, "public")
REACT_DIST_DIR = File.join(ROOT, "HeartWavesUIReact", "dist")
TMP_DIR = File.join(ROOT, "tmp")
FileUtils.mkdir_p(TMP_DIR)

def json(res, status:, body:)
  res.status = status
  res["Content-Type"] = "application/json"
  res.body = JSON.pretty_generate(body)
end

def session_path(session_id)
  File.join(TMP_DIR, "#{session_id}.json")
end

def load_session(session_id)
  path = session_path(session_id)
  return nil unless File.file?(path)
  JSON.parse(File.read(path))
end

def save_session(session_id, data)
  File.write(session_path(session_id), JSON.generate(data))
end

def serve_react_asset(req, res)
  return false unless Dir.exist?(REACT_DIST_DIR)

  path = req.path.to_s
  relative = path.sub(%r{\A/react/?}, "")
  relative = "index.html" if relative.empty?
  relative = relative.sub(%r{\A/+}, "")

  candidate = File.expand_path(relative, REACT_DIST_DIR)
  base = File.expand_path(REACT_DIST_DIR)
  unless candidate.start_with?(base)
    res.status = 403
    res.body = "forbidden"
    return true
  end

  if File.file?(candidate)
    ext = File.extname(candidate).downcase
    res["Content-Type"] =
      case ext
      when ".html" then "text/html; charset=utf-8"
      when ".js", ".mjs" then "application/javascript; charset=utf-8"
      when ".css" then "text/css; charset=utf-8"
      when ".json" then "application/json; charset=utf-8"
      when ".svg" then "image/svg+xml"
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".webp" then "image/webp"
      when ".ico" then "image/x-icon"
      else "application/octet-stream"
      end
    res.body = File.binread(candidate)
    return true
  end

  # SPA fallback for /react routes
  index_path = File.join(REACT_DIST_DIR, "index.html")
  return false unless File.file?(index_path)

  res["Content-Type"] = "text/html; charset=utf-8"
  res.body = File.read(index_path)
  true
end

def screening_get(screening, key)
  return screening[key.to_s] if screening.key?(key.to_s)
  return screening[key.to_sym] if screening.key?(key.to_sym)
  nil
end

def screening_set(screening, key, value)
  if screening.key?(key.to_sym)
    screening[key.to_sym] = value
  else
    screening[key.to_s] = value
  end
end

def model_get(model_result, key)
  return model_result[key.to_s] if model_result.key?(key.to_s)
  return model_result[key.to_sym] if model_result.key?(key.to_sym)
  nil
end

def model_set(model_result, key, value)
  if model_result.key?(key.to_sym)
    model_result[key.to_sym] = value
  else
    model_result[key.to_s] = value
  end
end

def parse_optional_float(value)
  text = value.to_s.strip
  return nil if text.empty?
  Float(text)
rescue ArgumentError
  nil
end

def calibrate_model_result(model_result)
  return model_result unless model_result.is_a?(Hash)
  return model_result unless model_get(model_result, :error).to_s.empty?

  coverage = model_get(model_result, :feature_coverage).to_f
  features = model_get(model_result, :features_used)
  return model_result unless coverage >= 0.8
  return model_result unless features.is_a?(Hash)

  delta_hr = parse_optional_float(features["delta_hr_stand_minus_sit"] || features[:delta_hr_stand_minus_sit])
  delta_sbp = parse_optional_float(features["delta_sbp_stand_minus_sit"] || features[:delta_sbp_stand_minus_sit])
  resting_hr = parse_optional_float(features["resting_hr_mean"] || features[:resting_hr_mean])

  if !delta_hr.nil? && delta_hr >= 30.0 && (delta_sbp.nil? || delta_sbp > -20.0)
    model_set(model_result, :status, "needs_followup")
    model_set(model_result, :phenotype_hint, "pots_like")
    model_set(model_result, :confidence, "medium")
    model_set(
      model_result,
      :reason,
      "Orthostatic quick-check shows HR rise #{delta_hr.round(1)} bpm without major SBP drop; POTS-like follow-up pattern."
    )
    return model_result
  end

  if !delta_sbp.nil? && delta_sbp <= -20.0
    model_set(model_result, :status, "needs_followup")
    model_set(model_result, :phenotype_hint, "oh_like")
    model_set(model_result, :confidence, "medium")
    model_set(
      model_result,
      :reason,
      "Orthostatic quick-check shows SBP drop #{delta_sbp.round(1)} mmHg; OH-like follow-up pattern."
    )
    return model_result
  end

  if !resting_hr.nil? && resting_hr >= 90.0 && (delta_hr.nil? || delta_hr < 30.0)
    model_set(model_result, :status, "needs_followup")
    model_set(model_result, :phenotype_hint, "ist_like")
    model_set(model_result, :confidence, "medium")
    model_set(
      model_result,
      :reason,
      "Orthostatic quick-check shows high resting HR with limited stand-related rise; IST-like follow-up pattern."
    )
  end

  model_result
end

def normalize_screening_profile!(screening)
  return unless screening.is_a?(Hash)

  status = screening_get(screening, :status).to_s
  phenotype = screening_get(screening, :phenotype_hint).to_s

  if status == "normal"
    screening_set(screening, :phenotype_hint, "normal")
    screening_set(screening, :phenotype_confidence, "high")
    reason = screening_get(screening, :phenotype_reason).to_s
    screening_set(screening, :phenotype_reason, "No strong follow-up pattern after current screening.") if reason.empty?
    return
  end

  return unless status == "needs_followup"

  if phenotype.empty? || phenotype == "normal"
    screening_set(screening, :phenotype_hint, "unspecified_autonomic")
    confidence = screening_get(screening, :phenotype_confidence).to_s
    reason = screening_get(screening, :phenotype_reason).to_s
    screening_set(screening, :phenotype_confidence, "low") if confidence.empty?
    screening_set(screening, :phenotype_reason, "Follow-up pattern detected, but no specific subtype was high-confidence.") if reason.empty?
  end
end

def confidence_rank(confidence)
  case confidence.to_s
  when "high" then 3
  when "medium" then 2
  when "low" then 1
  else 0
  end
end

def merge_clustering_model!(screening, model_result)
  return if model_result.nil?
  model_result = calibrate_model_result(model_result)

  screening_set(screening, :clustering_model, model_result)

  model_error = model_get(model_result, :error).to_s
  if model_error != ""
    notes = Array(screening_get(screening, :data_notes))
    notes << "Clustering model unavailable: #{model_error}"
    screening_set(screening, :data_notes, notes.uniq)
    return
  end

  model_status = model_get(model_result, :status).to_s
  model_hint = model_get(model_result, :phenotype_hint).to_s
  model_confidence = model_get(model_result, :confidence).to_s
  model_reason = model_get(model_result, :reason).to_s
  coverage = model_get(model_result, :feature_coverage).to_f

  notes = Array(screening_get(screening, :data_notes))
  notes << "Clustering model: #{model_reason}"

  current_status = screening_get(screening, :status).to_s
  current_confidence = screening_get(screening, :phenotype_confidence).to_s
  current_hint = screening_get(screening, :phenotype_hint).to_s
  bp_present = !!screening_get(screening, :bp_data_present)

  if model_status == "needs_followup" && confidence_rank(model_confidence) >= 2
    if current_status == "normal"
      screening_set(screening, :status, "needs_followup")
      screening_set(screening, :phenotype_hint, model_hint.empty? ? "unspecified_autonomic" : model_hint)
      screening_set(screening, :phenotype_confidence, model_confidence)
      screening_set(screening, :phenotype_reason, model_reason)
      screening_set(
        screening,
        :questionnaire,
        Screening::Baseline.questionnaire_for(
          status: "needs_followup",
          phenotype_hint: screening_get(screening, :phenotype_hint).to_s,
          bp_data_present: bp_present
        )
      )

      signals = Array(screening_get(screening, :signals))
      unless signals.any? { |s| (s["key"] || s[:key]).to_s == "cluster_model_followup" }
        signals << {
          key: "cluster_model_followup",
          severity: model_confidence == "high" ? "moderate" : "low",
          detail: "Clustering model flagged a #{screening_get(screening, :phenotype_hint)} pattern (#{model_confidence} confidence)."
        }
      end
      screening_set(screening, :signals, signals)
      notes << "Model upgraded status from normal to needs_followup."
    else
      if confidence_rank(model_confidence) > confidence_rank(current_confidence)
        screening_set(screening, :phenotype_confidence, model_confidence)
      end
      if (current_hint.empty? || current_hint == "unspecified_autonomic" || current_hint == "normal") && !model_hint.empty?
        screening_set(screening, :phenotype_hint, model_hint)
        screening_set(screening, :questionnaire, Screening::Baseline.questionnaire_for(
          status: "needs_followup",
          phenotype_hint: model_hint,
          bp_data_present: bp_present
        ))
      end
    end
  elsif model_status == "needs_followup" && confidence_rank(model_confidence) < 2
    notes << "Model suggested possible follow-up, but confidence is #{model_confidence} (coverage #{(coverage * 100).round(1)}%)."
  else
    notes << "Model aligned with normal screening pattern."
  end

  screening_set(screening, :data_notes, notes.uniq)
end

server = WEBrick::HTTPServer.new(
  Port: 4567,
  BindAddress: "127.0.0.1",
  AccessLog: [],
  Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
)

trap("INT") { server.shutdown }

server.mount_proc "/api/health" do |_req, res|
  json(res, status: 200, body: { ok: true })
end

server.mount_proc "/api/import/apple_health" do |req, res|
  unless req.request_method == "POST"
    json(res, status: 405, body: { error: "POST required" })
    next
  end

  unless req["content-type"]&.include?("multipart/form-data")
    json(res, status: 400, body: { error: "Expected multipart/form-data with file field named 'zip'" })
    next
  end

  form = req.query
  upload = form["zip"]
  if upload.nil?
    json(res, status: 400, body: { error: "Missing file field 'zip'" })
    next
  end

  tempfile =
    if upload.respond_to?(:tempfile)
      upload.tempfile
    elsif upload.respond_to?(:[])
      upload[:tempfile] || upload["tempfile"] || upload[:temp_file] || upload["temp_file"]
    end

  filename =
    if upload.respond_to?(:filename)
      upload.filename
    elsif upload.respond_to?(:[])
      upload[:filename] || upload["filename"]
    else
      "apple_health_export.zip"
    end

  raw_upload = upload.is_a?(String) ? upload : nil
  temp_path =
    if tempfile.respond_to?(:path)
      tempfile.path
    elsif tempfile.is_a?(String)
      tempfile
    end

  if (temp_path.nil? || !File.file?(temp_path)) && raw_upload
    session_id = SecureRandom.hex(12)
    suffix = filename.to_s.downcase.end_with?(".xml") ? ".xml" : ".zip"
    dest_path = File.join(TMP_DIR, "#{session_id}-upload#{suffix}")
    File.binwrite(dest_path, raw_upload)
  else
    unless temp_path && File.file?(temp_path)
      json(res, status: 400, body: { error: "Upload parsing failed; try again" })
      next
    end

    session_id = SecureRandom.hex(12)
    dest_path = File.join(TMP_DIR, "#{session_id}-#{File.basename(filename)}")
    FileUtils.cp(temp_path, dest_path)
  end

  unless defined?(session_id) && defined?(dest_path)
    json(res, status: 400, body: { error: "Upload parsing failed; try again" })
    next
  end

  begin
    orthostatic_input = {
      "sit_hr_mean" => parse_optional_float(form["ortho_rest_hr"]),
      "stand_hr_mean" => parse_optional_float(form["ortho_stand_hr"]),
      "sit_sbp_mean" => parse_optional_float(form["ortho_rest_sbp"]),
      "stand_sbp_mean" => parse_optional_float(form["ortho_stand_sbp"])
    }.reject { |_k, v| v.nil? }
    if orthostatic_input.key?("sit_hr_mean") && orthostatic_input.key?("stand_hr_mean")
      orthostatic_input["delta_hr_stand_minus_sit"] = orthostatic_input["stand_hr_mean"] - orthostatic_input["sit_hr_mean"]
    end
    if orthostatic_input.key?("sit_sbp_mean") && orthostatic_input.key?("stand_sbp_mean")
      orthostatic_input["delta_sbp_stand_minus_sit"] = orthostatic_input["stand_sbp_mean"] - orthostatic_input["sit_sbp_mean"]
    end

    imported =
      if filename.downcase.end_with?(".xml")
        AppleHealth::Import.from_export_xml(dest_path, days: 30)
      else
        AppleHealth::Import.from_export_zip(dest_path, days: 30)
      end
    imported["orthostatic_input"] = orthostatic_input unless orthostatic_input.empty?

    screened = Screening::Baseline.run(imported)
    clustering_model_result = Screening::ClusteringModel.score(
      imported: imported,
      orthostatic_override: orthostatic_input.empty? ? nil : orthostatic_input
    )
    merge_clustering_model!(screened, clustering_model_result)

    use_gemini = form["use_gemini"].to_s.strip == "1"
    has_gemini_key = ENV["GEMINI_API_KEY"].to_s.strip != "" || ENV["GOOGLE_API_KEY"].to_s.strip != ""
    if use_gemini && has_gemini_key
      begin
        llm = LLM::Gemini.screen(imported: imported, baseline_screening: screened)
        screened = screened.merge(llm: llm)
        if llm["questionnaire"].is_a?(Array) && !llm["questionnaire"].empty?
          screened[:questionnaire] = llm["questionnaire"]
        end
        if llm["signals"].is_a?(Array) && !llm["signals"].empty?
          screened[:signals] = llm["signals"]
        end
        if llm["safety_notes"].is_a?(Array) && !llm["safety_notes"].empty?
          screened[:safety_notes] = llm["safety_notes"]
        end
      rescue StandardError => e
        screened[:llm_error] = e.message
      end
    elsif use_gemini
      screened[:llm_error] = "Gemini requested but no GOOGLE_API_KEY/GEMINI_API_KEY is set."
    end

    normalize_screening_profile!(screened)

    out = { session_id: session_id, imported: imported, screening: screened, symptoms: { answers: [], updated_at: nil } }
    save_session(session_id, out)
    json(res, status: 200, body: out)
  rescue StandardError => e
    json(res, status: 500, body: { error: e.message })
  end
end

server.mount_proc "/api/session/answers" do |req, res|
  unless req.request_method == "POST"
    json(res, status: 405, body: { error: "POST required" })
    next
  end

  begin
    payload = JSON.parse(req.body.to_s)
  rescue JSON::ParserError
    json(res, status: 400, body: { error: "Invalid JSON body" })
    next
  end

  session_id = payload["session_id"].to_s
  if session_id.empty?
    json(res, status: 400, body: { error: "Missing session_id" })
    next
  end

  data = load_session(session_id)
  if data.nil?
    json(res, status: 404, body: { error: "Unknown session_id" })
    next
  end

  answers = payload["answers"]
  unless answers.is_a?(Hash)
    json(res, status: 400, body: { error: "answers must be an object of question_id => selected_option" })
    next
  end

  questionnaire = data.dig("screening", "questionnaire")
  unless questionnaire.is_a?(Array)
    json(res, status: 400, body: { error: "No questionnaire found in session" })
    next
  end

  question_map = {}
  questionnaire.each do |q|
    next unless q.is_a?(Hash)
    qid = q["id"].to_s
    next if qid.empty?
    question_map[qid] = q
  end

  sanitized = []
  answers.each do |question_id, option|
    q = question_map[question_id.to_s]
    next if q.nil?

    valid_options = Array(q["options"]).map(&:to_s)
    selected = option.to_s
    next unless valid_options.include?(selected)

    sanitized << {
      "id" => question_id.to_s,
      "prompt" => q["prompt"].to_s,
      "answer" => selected
    }
  end

  data["symptoms"] = {
    "answers" => sanitized,
    "updated_at" => Time.now.utc.iso8601
  }

  normalize_screening_profile!(data["screening"])
  survey_assessment = Screening::SurveyLabeling.apply!(screening: data["screening"], symptoms: data["symptoms"])
  normalize_screening_profile!(data["screening"])

  save_session(session_id, data)
  json(
    res,
    status: 200,
    body: {
      ok: true,
      symptoms: data["symptoms"],
      screening: data["screening"],
      survey_assessment: survey_assessment
    }
  )
end

server.mount_proc "/api/session/llm" do |req, res|
  unless req.request_method == "POST"
    json(res, status: 405, body: { error: "POST required" })
    next
  end

  begin
    payload = JSON.parse(req.body.to_s)
  rescue JSON::ParserError
    json(res, status: 400, body: { error: "Invalid JSON body" })
    next
  end

  session_id = payload["session_id"].to_s
  if session_id.empty?
    json(res, status: 400, body: { error: "Missing session_id" })
    next
  end

  llm = payload["llm"]
  unless llm.is_a?(Hash)
    json(res, status: 400, body: { error: "Missing llm object" })
    next
  end

  data = load_session(session_id)
  if data.nil?
    json(res, status: 404, body: { error: "Unknown session_id" })
    next
  end

  data["screening"] ||= {}
  data["screening"]["llm"] = llm

  status = llm["status"].to_s
  if %w[normal needs_followup].include?(status)
    data["screening"]["status"] = status
  end

  if llm["signals"].is_a?(Array) && !llm["signals"].empty?
    data["screening"]["signals"] = llm["signals"]
  end
  if llm["questionnaire"].is_a?(Array) && !llm["questionnaire"].empty?
    data["screening"]["questionnaire"] = llm["questionnaire"]
  end
  if llm["safety_notes"].is_a?(Array) && !llm["safety_notes"].empty?
    data["screening"]["safety_notes"] = llm["safety_notes"]
  end

  normalize_screening_profile!(data["screening"])

  data["llm_saved_at"] = Time.now.utc.iso8601
  save_session(session_id, data)
  json(res, status: 200, body: { ok: true })
end

server.mount_proc "/api/report" do |req, res|
  session_id = req.query["session_id"]
  if session_id.to_s.strip.empty?
    res.status = 400
    res.body = "missing session_id"
    next
  end

  data = load_session(session_id)
  if data.nil?
    res.status = 404
    res.body = "unknown session"
    next
  end

  res["Content-Type"] = "text/html; charset=utf-8"
  res.body = File.read(File.join(PUBLIC_DIR, "report.html"))
    .gsub("__REPORT_DATA__", JSON.generate(data))
end

server.mount_proc "/react" do |req, res|
  handled = serve_react_asset(req, res)
  unless handled
    res.status = 404
    res.body = "React UI build not found. Run npm run build in HeartWavesUIReact."
  end
end

server.mount_proc "/react/" do |req, res|
  handled = serve_react_asset(req, res)
  unless handled
    res.status = 404
    res.body = "React UI build not found. Run npm run build in HeartWavesUIReact."
  end
end

server.mount("/", WEBrick::HTTPServlet::FileHandler, PUBLIC_DIR, FancyIndexing: false)

puts "HeartWaves running on http://localhost:4567"
server.start
