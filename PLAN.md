# PLAN — POTS Early Warning System (Imminent Detection First)

## Goal
Build a **high-precision early warning system** using Apple Watch data to detect **imminent fainting / pre-syncope risk** in people with POTS.

**Primary objective (Phase 1):**
- Predict **pre-syncope within 30–60 seconds**
- Optimize for **precision first** (very few false alarms)
- Gradually increase recall without destroying trust

**Secondary objective (later phases):**
- Extend predictions to **2–15 minute lead times** once short-horizon detection is reliable

---

## Core Design Principles
- Personalized > population averages
- Pattern-of-change > absolute thresholds
- Precision before recall
- User trust > aggressive alerting
- Actionable alerts only when it matters

---

## PHASE 1 — Define the Target Event (Ground Truth)

### Event Definition
**Imminent pre-syncope (30–60s):**
- Lightheadedness
- Tunnel vision
- Sudden weakness
- Nausea / clamminess
- “I might faint”

### Labeling Strategy
- Primary input: **“Pre-syncope now”** button
- Secondary (optional): **“Did you faint?”**
- Post-event logging allowed if user couldn’t tap during event

No automatic labeling at this stage — user confirmation is required to keep labels clean.

---

## PHASE 2 — High-Frequency Data Capture (Apple Watch)

### Monitoring Mode
- Use an **Apple Watch Workout session** to unlock higher-frequency heart rate data
- Enable/disable manually to respect battery and privacy

### Signals Collected
**Physiology**
- Heart rate (high frequency)
- Resting HR baseline (historical)
- HR variability (when available)

**Motion / Context**
- Accelerometer + gyroscope
- Motion intensity
- Sudden motion changes
- Upright / standing proxies
- Time of day

**User Input**
- “Pre-syncope now” button
- Optional context tags (later): dehydration, heat, stress

---

## PHASE 3 — Feature Engineering (30–60s Windows)

Use rolling windows of **5s, 10s, 30s, 60s**.

### Core Features
- HR slope (ΔHR / Δt)
- HR acceleration (change in slope)
- Short-term HR volatility
- HR above personal baseline
- HR rising without motion increase (HR–motion mismatch)
- Motion instability (micro-sway / brace patterns)
- Sudden motion drop after movement (possible pre-collapse signature)

Raw HR alone is insufficient — **change dynamics are key**.

---

## PHASE 4 — Two-Layer Detection System

### Layer A — Context Gating (Precision Filter)
Only allow predictions when context makes sense:
- User is awake
- User is upright or recently upright
- Not in sustained vigorous exercise
- Recent standing OR prolonged standing OR known trigger context

This dramatically reduces false positives.

### Layer B — Imminent Risk Model
- Small, fast classifier (logistic regression or small gradient-boosted trees)
- Inputs: rolling features + context flags
- Output: probability of pre-syncope within 60s

Initial alert threshold: **very high (e.g., ≥0.9)**

---

## PHASE 5 — Alert Design (Imminent Only)

### Hard Alert (High Confidence)
- Strong haptic
- Minimal text:
  > **“High faint risk. Sit or lie down now.”**

Optional second line:
- “Leg pump + fluids if possible”

No long explanations during imminent alerts.

---

## PHASE 6 — Precision → Recall Optimization

### Stage 1: Precision-First
- High threshold
- Few alerts
- Collect missed-event data

### Stage 2: Add Soft Alerts
- Moderate-risk probability range (e.g., 0.6–0.9)
- Gentle haptic or “Heads up”
- Hard alerts remain strict

### Stage 3: Personal Thresholds
- User-adjustable sensitivity
- Target constraints:
  - Hard alerts: ≤1 false/day
  - Soft alerts: ≤3/day

---

## PHASE 7 — Personalized Learning Loop

- Train per-user models first
- Use user-confirmed events as positives
- Sample non-event windows as negatives
- Incorporate feedback:
  - “Did this alert help?”
  - “Did symptoms still worsen?”

Over time, the model adapts to each individual’s physiology.

---

## PHASE 8 — Evaluation Metrics (Correct Ones)

Do **not** rely on generic accuracy.

Track:
- Precision of hard alerts
- Recall of labeled pre-syncope events
- Median lead time (seconds)
- False alerts per hour upright
- Analysis of missed events (what patterns were present?)

---

## PHASE 9 — Extension to Longer Horizons (Later)

Only after Phase 1 is solid:

- Add **2–15 minute risk window model**
- Chain models:
  - Long-horizon → preventive coaching
  - Short-horizon → emergency action

This preserves trust while expanding usefulness.

---

## Immediate Build Order (Recommended)
1. Apple Watch Monitoring Mode + HR/motion streaming
2. “Pre-syncope now” + post-event logging
3. Rolling-window feature extraction
4. Context gating + small classifier
5. High-threshold hard alert
6. Threshold tuning with real user data

---

## Positioning & Ethics
- Physiological awareness and coaching tool
- Not diagnostic
- Not a replacement for medical care
- User retains full control over alerts and data

---

## End of PLAN
