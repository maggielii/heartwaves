function $(id) { return document.getElementById(id); }

let rhrChart = null;
let hrvChart = null;
let currentSessionId = "";
let currentQuestions = [];

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

function setStatus(text, kind) {
  const pill = $("statusPill");
  pill.textContent = text;
  pill.classList.remove("pill--ok", "pill--bad");
  if (kind === "ok") pill.classList.add("pill--ok");
  if (kind === "bad") pill.classList.add("pill--bad");
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
  for (const s of signals) {
    const li = document.createElement("li");
    li.textContent = s.detail || s.key;
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
  for (const q of (questions || [])) {
    const div = document.createElement("div");
    div.className = "q";
    div.dataset.qid = q.id;

    const prompt = document.createElement("div");
    prompt.className = "q__prompt";
    prompt.textContent = q.prompt;
    div.appendChild(prompt);

    const options = document.createElement("div");
    options.className = "q__opts";
    for (const option of (q.options || [])) {
      const label = document.createElement("label");
      label.className = "q__opt";

      const input = document.createElement("input");
      input.type = "radio";
      input.name = `q_${q.id}`;
      input.value = option;
      if (answerMap && answerMap[q.id] === option) {
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
  const labels = daily.map((d) => d.date);
  const rhr = daily.map((d) => (d.resting_hr_mean == null ? null : Number(d.resting_hr_mean)));
  const hrv = daily.map((d) => (d.hrv_sdnn_mean == null ? null : Number(d.hrv_sdnn_mean)));

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

async function onUpload(ev) {
  ev.preventDefault();
  const file = $("zipFile").files[0];
  if (!file) return;

  $("uploadStatus").textContent = "Processing... (this can take a bit for large exports)";
  $("results").classList.add("hidden");
  $("llmError").textContent = "";

  const fd = new FormData();
  fd.append("zip", file);
  fd.append("use_gemini", $("useGemini").checked ? "1" : "0");

  let res;
  let data;
  try {
    res = await fetchWithTimeout("/api/import/apple_health", { method: "POST", body: fd }, 120000);
    data = await res.json();
  } catch (_error) {
    $("uploadStatus").textContent = "Error: request timed out or server is unreachable. Restart server and try again.";
    return;
  }
  if (!res.ok) {
    $("uploadStatus").textContent = `Error: ${data.error || "unknown"}`;
    return;
  }

  $("uploadStatus").textContent = `OK. Parsed ${data.imported.record_counts.kept} records in-window.`;
  $("results").classList.remove("hidden");

  const status = data.screening.status;
  setStatus(status === "normal" ? "NORMAL" : "NEEDS FOLLOW-UP", status === "normal" ? "ok" : "bad");

  const daily = data.imported.daily;
  const recent = daily.slice(-7);

  const recentRhr = mean(recent.map((d) => d.resting_hr_mean));
  const recentHrv = mean(recent.map((d) => d.hrv_sdnn_mean));
  const recentStand = sum(recent.map((d) => d.stand_minutes));
  const recentActive = sum(recent.map((d) => d.active_minutes));

  $("rhrValue").textContent = recentRhr == null ? "-" : recentRhr.toFixed(1);
  $("hrvValue").textContent = recentHrv == null ? "-" : recentHrv.toFixed(1);
  $("standValue").textContent = Number.isFinite(recentStand) ? Math.round(recentStand).toString() : "-";
  $("activeValue").textContent = Number.isFinite(recentActive) ? Math.round(recentActive).toString() : "-";

  renderSignals(data.screening.signals);
  currentSessionId = data.session_id;
  currentQuestions = data.screening.questionnaire || [];
  renderQuestions(currentQuestions, answerMapFromSymptoms(data.symptoms));
  $("saveSymptomsBtn").disabled = currentQuestions.length === 0;
  $("symptomStatus").textContent = "";

  renderCharts(daily);

  $("reportLink").href = `/api/report?session_id=${encodeURIComponent(data.session_id)}`;

  if (data.screening.llm_error) {
    $("llmError").textContent = `Gemini failed, used rules-only: ${data.screening.llm_error}`;
  } else if ($("useGemini").checked && data.screening.llm) {
    $("llmError").textContent = "Gemini: enabled (signals/questions may be enhanced).";
  }
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
  const res = await fetch("/api/session/answers", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ session_id: currentSessionId, answers })
  });
  const data = await res.json();
  if (!res.ok) {
    $("symptomStatus").textContent = `Error: ${data.error || "unknown"}`;
    return;
  }

  const saved = data.symptoms && Array.isArray(data.symptoms.answers) ? data.symptoms.answers.length : 0;
  $("symptomStatus").textContent = `Saved ${saved} answer${saved === 1 ? "" : "s"} to report.`;
}

function reset() {
  $("uploadStatus").textContent = "";
  $("llmError").textContent = "";
  $("symptomStatus").textContent = "";
  $("results").classList.add("hidden");
  $("uploadForm").reset();
  currentSessionId = "";
  currentQuestions = [];
  $("saveSymptomsBtn").disabled = true;
  if (rhrChart) rhrChart.destroy();
  if (hrvChart) hrvChart.destroy();
  rhrChart = null;
  hrvChart = null;
}

async function checkServerHealth() {
  const target = $("serverStatus");
  if (!target) return;
  try {
    const res = await fetchWithTimeout("/api/health", { method: "GET" }, 2500);
    if (!res.ok) throw new Error("bad status");
    target.textContent = "Server: online";
  } catch (_error) {
    target.textContent = "Server: offline (start ruby server.rb in /Users/master_of_puppets/Desktop/HeartWaves)";
  }
}

window.addEventListener("DOMContentLoaded", () => {
  $("uploadForm").addEventListener("submit", onUpload);
  $("resetBtn").addEventListener("click", reset);
  $("saveSymptomsBtn").addEventListener("click", onSaveSymptoms);
  $("saveSymptomsBtn").disabled = true;
  checkServerHealth();
});
