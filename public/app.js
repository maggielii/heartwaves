function $(id) { return document.getElementById(id); }

const GEMINI_KEY_SESSION_KEY = "heartwaves_google_api_key";
const GEMINI_MODEL_STORAGE_KEY = "heartwaves_gemini_model";

let rhrChart = null;
let hrvChart = null;
let currentSessionId = "";
let currentQuestions = [];
let currentData = null;

function fetchWithTimeout(url, options, timeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  return fetch(url, { ...(options || {}), signal: controller.signal })
    .finally(() => clearTimeout(timeout));
}

function mean(nums) {
  const xs = nums.filter((x) => Number.isFinite(x));
  if (!xs.length) return null;
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

function sum(nums) {
  const xs = nums.filter((x) => Number.isFinite(x));
  return xs.reduce((a, b) => a + b, 0);
}

function appendFormFieldIfPresent(formData, fieldName, elementId) {
  const input = $(elementId);
  if (!input) return;
  const value = String(input.value || "").trim();
  if (!value) return;
  formData.append(fieldName, value);
}

function setStatus(text, kind) {
  const pill = $("statusPill");
  pill.textContent = text;
  pill.classList.remove("pill--ok", "pill--bad");
  if (kind === "ok") pill.classList.add("pill--ok");
  if (kind === "bad") pill.classList.add("pill--bad");
}

function formatPhenotypeHint(hint) {
  switch (String(hint || "")) {
    case "normal": return "Normal pattern";
    case "pots_like": return "POTS-like pattern";
    case "ist_like": return "IST-like pattern";
    case "oh_like": return "OH-like pattern";
    case "vvs_like": return "VVS-like pattern";
    case "unspecified_autonomic": return "Unspecified autonomic pattern";
    default: return "Unspecified";
  }
}

function formatConfidence(confidence) {
  switch (String(confidence || "")) {
    case "high": return "High";
    case "medium": return "Medium";
    case "low": return "Low";
    default: return "Unknown";
  }
}

function formatSurveyAssessment(assessment) {
  if (!assessment || typeof assessment !== "object") return "";
  if (assessment.summary) return assessment.summary;

  const alignment = String(assessment.alignment || "inconclusive").replaceAll("_", " ");
  const score = Number(assessment.support_score);
  const scoreText = Number.isFinite(score) ? score.toFixed(2) : "-";
  const informative = Number(assessment.informative_answers);
  const informativeText = Number.isFinite(informative) ? informative : 0;
  return `Survey alignment: ${alignment} (score ${scoreText}, informative answers ${informativeText}).`;
}

function reconcileScreeningProfile(screening) {
  if (!screening || typeof screening !== "object") return;

  if (screening.status === "normal") {
    screening.phenotype_hint = "normal";
    screening.phenotype_confidence = "high";
    screening.phenotype_reason = screening.phenotype_reason || "No strong follow-up pattern in this window.";
    return;
  }

  if (!screening.phenotype_hint || screening.phenotype_hint === "normal") {
    screening.phenotype_hint = "unspecified_autonomic";
  }
  if (!screening.phenotype_confidence) {
    screening.phenotype_confidence = "low";
  }
}

function renderSignals(signals) {
  const ul = $("signals");
  ul.innerHTML = "";
  if (!signals || !signals.length) {
    const li = document.createElement("li");
    li.textContent = "No strong signals detected in the last 30 days based on this demo logic.";
    ul.appendChild(li);
    return;
  }
  for (const signal of signals) {
    const li = document.createElement("li");
    li.textContent = signal.detail || signal.key;
    ul.appendChild(li);
  }
}

function answerMapFromSymptoms(symptoms) {
  const map = {};
  const items = symptoms && Array.isArray(symptoms.answers) ? symptoms.answers : [];
  for (const item of items) {
    if (item && item.id && item.answer) {
      map[item.id] = item.answer;
    }
  }
  return map;
}

function renderQuestions(questions, answerMap) {
  const root = $("questions");
  root.innerHTML = "";
  for (const question of (questions || [])) {
    const div = document.createElement("div");
    div.className = "q";
    div.dataset.qid = question.id;

    const prompt = document.createElement("div");
    prompt.className = "q__prompt";
    prompt.textContent = question.prompt;
    div.appendChild(prompt);

    const options = document.createElement("div");
    options.className = "q__opts";
    for (const option of (question.options || [])) {
      const label = document.createElement("label");
      label.className = "q__opt";

      const input = document.createElement("input");
      input.type = "radio";
      input.name = `q_${question.id}`;
      input.value = option;
      if (answerMap && answerMap[question.id] === option) {
        input.checked = true;
      }

      const text = document.createElement("span");
      text.textContent = option;

      label.appendChild(input);
      label.appendChild(text);
      options.appendChild(label);
    }
    div.appendChild(options);
    root.appendChild(div);
  }
}

function collectAnswers() {
  const answers = {};
  for (const question of currentQuestions) {
    const selected = document.querySelector(`input[name="q_${question.id}"]:checked`);
    if (selected) {
      answers[question.id] = selected.value;
    }
  }
  return answers;
}

function renderCharts(daily) {
  const labels = daily.map((day) => day.date);
  const rhr = daily.map((day) => (day.resting_hr_mean == null ? null : Number(day.resting_hr_mean)));
  const hrv = daily.map((day) => (day.hrv_sdnn_mean == null ? null : Number(day.hrv_sdnn_mean)));

  const common = {
    responsive: true,
    maintainAspectRatio: false,
    scales: { x: { ticks: { maxTicksLimit: 7 } } },
    plugins: { legend: { display: false } }
  };

  const rhrCtx = $("rhrChart").getContext("2d");
  const hrvCtx = $("hrvChart").getContext("2d");

  if (rhrChart) rhrChart.destroy();
  if (hrvChart) hrvChart.destroy();

  rhrChart = new Chart(rhrCtx, {
    type: "line",
    data: { labels, datasets: [{ data: rhr, borderColor: "#1f5c52", tension: 0.25, spanGaps: true }] },
    options: { ...common }
  });

  hrvChart = new Chart(hrvCtx, {
    type: "line",
    data: { labels, datasets: [{ data: hrv, borderColor: "#b11f3a", tension: 0.25, spanGaps: true }] },
    options: { ...common }
  });

  $("rhrChart").parentElement.style.height = "260px";
  $("hrvChart").parentElement.style.height = "260px";
}

function extractJson(text) {
  const trimmed = String(text || "").trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();

  if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
    return trimmed;
  }
  const match = trimmed.match(/\{[\s\S]*\}/);
  if (!match) {
    throw new Error("Gemini did not return JSON");
  }
  return match[0];
}

function normalizeLlmOutput(output) {
  const llm = output && typeof output === "object" ? output : {};
  llm.status = String(llm.status || "");
  llm.signals = Array.isArray(llm.signals) ? llm.signals : [];
  llm.questionnaire = Array.isArray(llm.questionnaire) ? llm.questionnaire : [];
  llm.doctor_summary_bullets = Array.isArray(llm.doctor_summary_bullets) ? llm.doctor_summary_bullets : [];
  llm.safety_notes = Array.isArray(llm.safety_notes) ? llm.safety_notes : [];
  return llm;
}

function buildGeminiSummary(imported, screening) {
  const daily = Array.isArray(imported.daily) ? imported.daily : [];
  const last7 = daily.slice(-7);
  return {
    window: {
      start_date: imported.start_date,
      end_date: imported.end_date,
      window_days: imported.window_days
    },
    recent_7d: {
      resting_hr_mean: mean(last7.map((d) => d.resting_hr_mean)),
      hrv_sdnn_mean: mean(last7.map((d) => d.hrv_sdnn_mean)),
      stand_minutes_total: sum(last7.map((d) => d.stand_minutes)),
      active_minutes_total: sum(last7.map((d) => d.active_minutes))
    },
    baseline_stats: screening.stats || {},
    missingness: {
      days_with_resting_hr: daily.filter((d) => d.resting_hr_mean != null).length,
      days_with_hrv: daily.filter((d) => d.hrv_sdnn_mean != null).length
    },
    baseline_status: screening.status,
    baseline_signals: screening.signals || []
  };
}

function buildGeminiPrompt(summary) {
  return [
    "You are assisting with a non-diagnostic health screening and self-advocacy tool.",
    "You must be conservative, avoid diagnosis, and avoid claiming certainty.",
    "",
    "INPUT: You will receive aggregated wearable features only (no raw streams).",
    "TASK: Produce JSON ONLY matching this schema:",
    "{",
    '  "status": "normal" | "needs_followup",',
    '  "signals": [{"key": string, "severity": "low"|"moderate"|"high", "detail": string}],',
    '  "questionnaire": [{"id": string, "prompt": string, "options": [string]}],',
    '  "doctor_summary_bullets": [string],',
    '  "safety_notes": [string]',
    "}",
    "",
    "Rules:",
    "- Do not diagnose (no 'you have POTS' etc). Use 'may warrant evaluation' phrasing.",
    "- Status means: 'needs_followup' if patterns or missingness suggest talking to a clinician.",
    "- Keep signals to 2-5 items max and make them specific to the numbers provided.",
    "- Questionnaire should be 5-8 questions if needs_followup, otherwise 3-5.",
    "- Include a safety note about urgent red flags (chest pain, fainting, severe shortness of breath).",
    "- Use dysautonomia examples only as possible issues to watch for.",
    "",
    "SUMMARY JSON:",
    JSON.stringify(summary, null, 2)
  ].join("\n");
}

async function callGeminiFromBrowser(imported, screening) {
  const key = $("geminiApiKey").value.trim();
  if (!key) {
    throw new Error("Missing Google AI Studio key.");
  }
  const model = $("geminiModel").value.trim() || "gemini-2.5-flash";

  sessionStorage.setItem(GEMINI_KEY_SESSION_KEY, key);
  localStorage.setItem(GEMINI_MODEL_STORAGE_KEY, model);

  const summary = buildGeminiSummary(imported, screening);
  const prompt = buildGeminiPrompt(summary);
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  const body = {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: { temperature: 0.2, maxOutputTokens: 900 }
  };

  const response = await fetchWithTimeout(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": key
    },
    body: JSON.stringify(body)
  }, 45000);

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Gemini HTTP ${response.status}: ${text.slice(0, 120)}`);
  }

  const payload = await response.json();
  const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
  const jsonText = extractJson(text);
  return normalizeLlmOutput(JSON.parse(jsonText));
}

function applyLlmToScreening(screening, llm) {
  screening.llm = llm;
  if (llm.status === "normal" || llm.status === "needs_followup") {
    screening.status = llm.status;
  }
  if (llm.signals.length) {
    screening.signals = llm.signals;
  }
  if (llm.questionnaire.length) {
    screening.questionnaire = llm.questionnaire;
  }
  if (llm.safety_notes.length) {
    screening.safety_notes = llm.safety_notes;
  }
  reconcileScreeningProfile(screening);
}

async function persistLlmToSession(sessionId, llm) {
  const response = await fetchWithTimeout("/api/session/llm", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ session_id: sessionId, llm })
  }, 10000);
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.error || `Failed to persist Gemini output (${response.status})`);
  }
}

function renderFromData(data) {
  currentData = data;
  reconcileScreeningProfile(data.screening);

  const status = data.screening.status;
  setStatus(status === "normal" ? "NORMAL" : "NEEDS FOLLOW-UP", status === "normal" ? "ok" : "bad");
  $("phenotypeHint").textContent = formatPhenotypeHint(data.screening.phenotype_hint);
  $("phenotypeConfidence").textContent = formatConfidence(data.screening.phenotype_confidence);
  $("phenotypeReason").textContent = data.screening.phenotype_reason || "";
  const model = data.screening.clustering_model || data.screening.model;
  if (model && !model.error) {
    const status = String(model.status || "-").toUpperCase();
    const hint = formatPhenotypeHint(model.phenotype_hint || "");
    const conf = formatConfidence(model.confidence || "");
    const coverage = Number.isFinite(Number(model.feature_coverage))
      ? `${(Number(model.feature_coverage) * 100).toFixed(0)}%`
      : "-";
    $("modelStatus").textContent = `Cluster model: ${status} | ${hint} | ${conf} confidence | coverage ${coverage}`;
  } else if (model && model.error) {
    $("modelStatus").textContent = `Cluster model unavailable: ${model.error}`;
  } else {
    $("modelStatus").textContent = "";
  }
  $("surveyAssessment").textContent = formatSurveyAssessment(data.screening.survey_assessment);

  const daily = data.imported.daily;
  const recent = daily.slice(-7);

  const recentRhr = mean(recent.map((day) => day.resting_hr_mean));
  const recentHrv = mean(recent.map((day) => day.hrv_sdnn_mean));
  const recentStand = sum(recent.map((day) => day.stand_minutes));
  const recentActive = sum(recent.map((day) => day.active_minutes));

  $("rhrValue").textContent = recentRhr == null ? "-" : recentRhr.toFixed(1);
  $("hrvValue").textContent = recentHrv == null ? "-" : recentHrv.toFixed(1);
  $("standValue").textContent = Number.isFinite(recentStand) ? Math.round(recentStand).toString() : "-";
  $("activeValue").textContent = Number.isFinite(recentActive) ? Math.round(recentActive).toString() : "-";

  renderSignals(data.screening.signals);
  currentSessionId = data.session_id;
  currentQuestions = data.screening.questionnaire || [];
  renderQuestions(currentQuestions, answerMapFromSymptoms(data.symptoms));
  $("saveSymptomsBtn").disabled = currentQuestions.length === 0;

  renderCharts(daily);
  $("reportLink").href = `/api/report?session_id=${encodeURIComponent(data.session_id)}`;
}

async function onUpload(ev) {
  ev.preventDefault();
  const file = $("zipFile").files[0];
  if (!file) return;

  const wantsBrowserGemini = $("useGemini").checked;
  $("uploadStatus").textContent = "Processing... (this can take a bit for large exports)";
  $("results").classList.add("hidden");
  $("llmError").textContent = "";

  const fd = new FormData();
  fd.append("zip", file);
  // Always run server-side baseline logic only; browser Gemini runs after.
  fd.append("use_gemini", "0");
  appendFormFieldIfPresent(fd, "ortho_rest_hr", "orthoRestHr");
  appendFormFieldIfPresent(fd, "ortho_stand_hr", "orthoStandHr");
  appendFormFieldIfPresent(fd, "ortho_rest_sbp", "orthoRestSbp");
  appendFormFieldIfPresent(fd, "ortho_stand_sbp", "orthoStandSbp");

  let response;
  let data;
  try {
    response = await fetchWithTimeout("/api/import/apple_health", { method: "POST", body: fd }, 120000);
    data = await response.json();
  } catch (_error) {
    $("uploadStatus").textContent = "Error: request timed out or server is unreachable. Restart server and try again.";
    return;
  }
  if (!response.ok) {
    $("uploadStatus").textContent = `Error: ${data.error || "unknown"}`;
    return;
  }

  if (wantsBrowserGemini) {
    $("uploadStatus").textContent = `Parsed ${data.imported.record_counts.kept} records. Running Gemini in browser...`;
    try {
      const llm = await callGeminiFromBrowser(data.imported, data.screening);
      applyLlmToScreening(data.screening, llm);
      await persistLlmToSession(data.session_id, llm);
      $("llmError").textContent = "Gemini (browser): enabled.";
    } catch (error) {
      $("llmError").textContent = `Gemini failed, used rules-only: ${error.message}`;
    }
  }

  $("uploadStatus").textContent = `OK. Parsed ${data.imported.record_counts.kept} records in-window.`;
  $("results").classList.remove("hidden");
  $("symptomStatus").textContent = "";
  renderFromData(data);
}

async function onSaveSymptoms() {
  if (!currentSessionId) {
    $("symptomStatus").textContent = "Import data first.";
    return;
  }

  const answers = collectAnswers();
  if (Object.keys(answers).length === 0) {
    $("symptomStatus").textContent = "Select at least one symptom answer before saving.";
    return;
  }

  $("symptomStatus").textContent = "Saving symptoms...";
  let response;
  let data;
  try {
    response = await fetchWithTimeout("/api/session/answers", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: currentSessionId, answers })
    }, 10000);
    data = await response.json();
  } catch (_error) {
    $("symptomStatus").textContent = "Error: unable to save answers.";
    return;
  }
  if (!response.ok) {
    $("symptomStatus").textContent = `Error: ${data.error || "unknown"}`;
    return;
  }

  const saved = data.symptoms && Array.isArray(data.symptoms.answers) ? data.symptoms.answers.length : 0;
  if (currentData) {
    if (data.screening) currentData.screening = data.screening;
    if (data.symptoms) currentData.symptoms = data.symptoms;
    renderFromData(currentData);
  }

  const surveySuffix = data.survey_assessment && data.survey_assessment.summary
    ? ` ${data.survey_assessment.summary}`
    : "";
  $("symptomStatus").textContent = `Saved ${saved} answer${saved === 1 ? "" : "s"} to report.${surveySuffix}`;
}

function syncGeminiConfigVisibility() {
  const config = $("geminiConfig");
  if (!config) return;
  const enabled = $("useGemini").checked;
  config.classList.toggle("hidden", !enabled);
}

function restoreGeminiInputs() {
  const savedKey = sessionStorage.getItem(GEMINI_KEY_SESSION_KEY);
  const savedModel = localStorage.getItem(GEMINI_MODEL_STORAGE_KEY);
  if (savedKey) $("geminiApiKey").value = savedKey;
  if (savedModel) $("geminiModel").value = savedModel;
}

function reset() {
  $("uploadStatus").textContent = "";
  $("llmError").textContent = "";
  $("symptomStatus").textContent = "";
  $("results").classList.add("hidden");
  $("uploadForm").reset();
  currentSessionId = "";
  currentQuestions = [];
  currentData = null;
  $("phenotypeHint").textContent = "-";
  $("phenotypeConfidence").textContent = "-";
  $("phenotypeReason").textContent = "";
  $("modelStatus").textContent = "";
  $("surveyAssessment").textContent = "";
  $("saveSymptomsBtn").disabled = true;
  if (rhrChart) rhrChart.destroy();
  if (hrvChart) hrvChart.destroy();
  rhrChart = null;
  hrvChart = null;

  const model = localStorage.getItem(GEMINI_MODEL_STORAGE_KEY);
  if (model) $("geminiModel").value = model;
  const key = sessionStorage.getItem(GEMINI_KEY_SESSION_KEY);
  if (key) $("geminiApiKey").value = key;
  syncGeminiConfigVisibility();
}

async function checkServerHealth() {
  const target = $("serverStatus");
  if (!target) return;
  try {
    const response = await fetchWithTimeout("/api/health", { method: "GET" }, 2500);
    if (!response.ok) throw new Error("bad status");
    target.textContent = "Server: online";
  } catch (_error) {
    target.textContent = "Server: offline (start ruby server.rb in /Users/master_of_puppets/Desktop/HeartWaves)";
  }
}

window.addEventListener("DOMContentLoaded", () => {
  restoreGeminiInputs();
  syncGeminiConfigVisibility();

  $("uploadForm").addEventListener("submit", onUpload);
  $("resetBtn").addEventListener("click", reset);
  $("saveSymptomsBtn").addEventListener("click", onSaveSymptoms);
  $("saveSymptomsBtn").disabled = true;
  $("useGemini").addEventListener("change", syncGeminiConfigVisibility);
  $("geminiApiKey").addEventListener("input", () => {
    sessionStorage.setItem(GEMINI_KEY_SESSION_KEY, $("geminiApiKey").value.trim());
  });
  $("geminiModel").addEventListener("change", () => {
    localStorage.setItem(GEMINI_MODEL_STORAGE_KEY, $("geminiModel").value.trim());
  });

  checkServerHealth();
});
