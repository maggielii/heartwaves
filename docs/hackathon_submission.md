# HeartWaves
Hack The Coast 2026 - HealthTech & Bioinnovation Track

## Team
- Michael Omstead - Project Lead, Prompt Engineering, Backend Development
- Maggie Li - React Web Development
- Lily - iOS UX Design
- Sophia - Swift Backend Development (iOS)

## Inspiration
Four years ago, after getting mono, I developed neurological complications and was admitted to the neurological ICU. I had severe spasms, dizziness, and could not stand upright for more than a few minutes without feeling faint. After many tests, I was discharged without a clear explanation and my symptoms were labeled as anxiety.

For months, I saw multiple specialists while living with fatigue, brain fog, and orthostatic symptoms that did not fit neatly into one specialty. Eventually, at the NIH in Maryland, a neurologist recognized the broader autonomic pattern immediately. A full autonomic workup, including a tilt table test, confirmed POTS. Once I had the right diagnosis path, treatment helped me recover significantly within months.

HeartWaves is built for people living in that uncertainty. The goal is not to diagnose, but to help users spot meaningful patterns early and advocate for the right follow-up testing with clinicians.

## What It Does
HeartWaves is a non-diagnostic screening assistant that:
- Imports Apple Health data (`export.xml` or ZIP).
- Analyzes the latest 30-day window (resting HR, HRV SDNN, stand minutes, active minutes).
- Runs a local clustering + screening pipeline to classify `normal` vs `needs_followup`.
- Adds phenotype hints (`pots_like`, `ist_like`, `oh_like`, `vvs_like`) with confidence labels.
- Triggers a short dysautonomia-oriented questionnaire when follow-up is indicated.
- Generates a clinician-ready report (HTML/PDF) with data trends and symptom responses.

Primary user: patients who want to share structured data with clinicians.

## How We Built It
- Ruby backend (`server.rb`) for ingestion, feature extraction, scoring, session state, and reporting.
- React web experience plus a local HTML report pipeline.
- PhysioNet-first data bootstrap to train a baseline clustering model.
- HealthKit-aligned training table builder and split pipeline:
  - `scripts/fetch_physionet_data.sh`
  - `scripts/build_training_table.rb`
  - `scripts/split_training_table.rb`
  - `scripts/train_clustering_baseline.rb`
- Local model inference integrated into live upload flow via `lib/screening/clustering_model.rb`.
- Survey gating logic to align cluster patterns with symptom context before stronger follow-up messaging.

## Machine Learning Approach
We implemented our own clustering baseline so users can run analysis locally without relying on a large-company LLM for core classification.

Current pipeline:
- Public data bootstrap from PhysioNet into a HealthKit-shaped schema.
- Train/validation/test split.
- KMeans baseline with confidence-aware follow-up mapping.
- Conservative safety behavior:
  - Higher-confidence pathways for `normal`, `pots_like`, `ist_like`.
  - `oh_like` and `vvs_like` treated as lower-confidence without blood pressure context.

Performance summary (high-level):
- Early validation/test behavior is promising for conservative screening.
- Current model is precision-oriented and intentionally cautious.
- We still need improved recall and broader dataset coverage in the next phase.

## Optional LLM Role
Gemini is an optional enhancer for language and explanation quality.
- Core screening and clustering run locally.
- Users who do not want LLM usage can still use the full local analysis path.

## Challenges We Ran Into
- Coordinating backend integration across multiple frontends (React web and iOS track work).
- Mapping heterogeneous public data into a HealthKit-compatible structure.
- Keeping outputs clinically useful while avoiding diagnostic overreach.

## Accomplishments We're Proud Of
- Building a sleek, approachable product that people can actually use in a stressful health journey.
- Delivering a real-world local clustering workflow rather than just an LLM-only prototype.
- Creating an end-to-end pipeline from raw health export to clinician-ready PDF.

## What We Learned
Clear team role separation and strong project organization are critical for shipping a full-stack healthcare tool quickly.

## What's Next
### Next 30 days
- Launch HeartWaves on the Apple App Store.
- Improve feature depth and begin real-time syncope-risk detection research with user-labeled episodes.
- Target a personalized warning workflow with up to ~60-second lead time for severe symptom events.

### 60+ days
- Present HeartWaves to UBC's cardiovascular research group.
- Explore collaboration on a lower-cost wearable purpose-built for dysautonomia signals, with richer data than current consumer defaults.

## Built With
- Ruby
- React
- TypeScript
- JavaScript
- WEBrick
- Swift (iOS path)
- Apple Health export schema
- PhysioNet datasets
- KMeans clustering (custom Ruby pipeline)
- Gemini API (optional enhancer)
- HTML/CSS

## Submission Notes
- This is a screening and self-advocacy tool, not a diagnostic system.
- Demo links, video, and repository links can be added once finalized.
