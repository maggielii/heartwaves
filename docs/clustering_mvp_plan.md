# HeartWaves Clustering MVP Plan

Last updated: 2026-02-08

## 1) Product target for 24 hours

Build a **screening** demo (not diagnosis) with:

- Input: Apple Health export (`export.xml` or ZIP)
- Output:
  - `normal`
  - `needs_followup` with phenotype hint (`pots_like`, `oh_like`, `ist_like`, `vvs_like`, or `unspecified_autonomic`)
- If follow-up is flagged: trigger symptom questionnaire and optional doctor PDF.

## 2) Recommended modeling approach (MVP)

Use a **hybrid** design to keep precision practical in 24h:

1. Unsupervised clustering on physiologic features (`HDBSCAN` or `KMeans` baseline).
2. Clinical rule layer to map clusters to phenotype hints.
3. Questionnaire gate before showing follow-up recommendation.

Why this approach:

- Public dysautonomia datasets are limited for fully supervised subtype training.
- Pure clustering alone is unstable for direct medical labels.
- Rule + questionnaire gating improves precision and interpretability.

## 3) Data source strategy (PhysioNet-first)

Primary bootstrap source (open, fast to access):

1. PhysioNet: Autonomic Aging Cardiovascular Variability Dataset  
   https://physionet.org/content/autonomic-aging-cardiovascular/1.0.0/
2. PhysioNet: Cardiorespiratory Response to Orthostatic Challenge  
   https://physionet.org/content/cardioresp-response-orthostat/1.0/
3. PhysioNet: Continuous Monitoring of Cerebral Blood Flow and Arterial Pressure in Adults With Type 2 Diabetes  
   https://physionet.org/content/cerebral-vasoreg-diabetes/1.0.0/
4. PhysioNet: Cerebral Vasoregulation in Elderly with Stroke  
   https://physionet.org/content/cves/1.0.0/

Important caveat:

- These sources are strong for autonomic physiology but are **not** all explicit diagnosed POTS/IST/OH/VVS cohorts.
- Subtype naming in MVP should be presented as `*_like` pattern with confidence, not diagnosis.

## 4) HealthKit-aligned feature schema

Current HeartWaves importer already provides daily values:

- `resting_hr_mean`
- `hrv_sdnn_mean`
- `stand_minutes`
- `active_minutes`

Derived features for clustering (windowed 7d/30d):

- `rhr_7d_mean`, `rhr_30d_mean`, `rhr_trend`
- `hrv_7d_mean`, `hrv_30d_mean`, `hrv_trend`
- `stand_7d_mean`, `active_7d_mean`
- `orthostatic_proxy = z(rhr_trend) - z(hrv_trend)`
- data completeness features (`days_with_rhr`, `days_with_hrv`)

## 5) Phenotype hint rules (MVP)

Use cluster output + rule checks:

- `pots_like`: elevated orthostatic tachycardia pattern with preserved BP proxy and compatible symptoms.
- `oh_like`: BP-drop pattern if BP exists; otherwise low confidence and questionnaire-led.
- `ist_like`: high resting/average HR pattern not tied only to standing.
- `vvs_like`: episodic presyncope/syncope pattern + abrupt autonomic shift signals.

If BP is missing, OH/VVS remain low-confidence hints.

## 6) Execution steps

1. Build source manifest and ingestion scripts for selected PhysioNet datasets.
2. Convert external data into a common daily feature table matching HealthKit schema.
3. Train baseline clustering model on external data + healthy windows.
4. Learn cluster centroids and map to `*_like` phenotype hints.
5. Add questionnaire gating per phenotype hint.
6. Add evaluation:
   - internal split: train/val/test
   - external check: second source or held-out cohort
7. Integrate into app pipeline and PDF report text.

## 7) Step 1 deliverable (next action)

Create these artifacts:

- `data/sources/physionet_manifest.json`
- `scripts/fetch_physionet_data.sh`
- `scripts/summarize_physionet_records.rb`
- `data/sources/physionet_inventory.json`
- `scripts/build_training_table.rb` (next)
- `data/processed/training_table.csv` (next)

Then run an initial baseline clustering pass and inspect cluster separability before subtype naming.
