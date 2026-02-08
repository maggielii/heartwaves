# HeartWaves (Hackathon Demo)

Local-only, non-diagnostic health screening demo:
- Upload Apple Health export ZIP or `export.xml`
- Compute last-30-day aggregates (Resting HR, HRV SDNN, stand/exercise minutes)
- Optionally add orthostatic quick-check values (sit/stand HR and optional BP) to improve subtype clustering
- Classify `normal` vs `needs_followup` using personal-baseline rules
- Add phenotype hints with confidence (`pots_like` / `ist_like` prioritized high-confidence, `oh_like` / `vvs_like` low-confidence without BP)
- Capture questionnaire answers and use them to confirm or downgrade follow-up labels in-session
- Generate a doctor-ready HTML report (print to PDF)

## Run

```bash
cd /Users/master_of_puppets/Desktop/HeartWaves
ruby server.rb
```

Open `http://localhost:4567`.

For a quick start/stop/status wrapper:

```bash
cd /Users/master_of_puppets/Desktop/HeartWaves
./scripts/mvp_server.sh start
./scripts/mvp_server.sh status
./scripts/mvp_server.sh open
```

When done:

```bash
cd /Users/master_of_puppets/Desktop/HeartWaves
./scripts/mvp_server.sh stop
```

## Gemini (Optional)

Browser mode (recommended for this demo):
- Start the app normally (no key needed in terminal).
- In the UI, check `Use Gemini from browser`.
- Paste your Google AI Studio key in `Google AI Studio key`.
- The app calls Gemini directly from the browser and saves output back to session report data.

```bash
cd /Users/master_of_puppets/Desktop/HeartWaves
ruby server.rb
```

Legacy server mode:
- If you still want server-side Gemini, run with `GOOGLE_API_KEY` or `GEMINI_API_KEY`.

## Notes

- Data is processed locally and stored only in `./tmp` during the session.
- This is not a diagnosis tool.
- If `/Users/master_of_puppets/Desktop/HeartWaves/data/models/clustering_baseline/model.json` exists, import flow runs clustering inference automatically and stores results in `screening.clustering_model`.

## Data Pipeline (PhysioNet Bootstrap)

Build the first training table aligned to HeartWaves features:

```bash
cd /Users/master_of_puppets/Desktop/HeartWaves
./scripts/fetch_physionet_data.sh
./scripts/build_training_table.rb
./scripts/split_training_table.rb
./scripts/train_clustering_baseline.rb
```

Outputs:
- `/Users/master_of_puppets/Desktop/HeartWaves/data/processed/training_table.csv`
- `/Users/master_of_puppets/Desktop/HeartWaves/data/processed/training_table_summary.json`
- `/Users/master_of_puppets/Desktop/HeartWaves/data/processed/splits/train.csv`
- `/Users/master_of_puppets/Desktop/HeartWaves/data/processed/splits/val.csv`
- `/Users/master_of_puppets/Desktop/HeartWaves/data/processed/splits/test.csv`
- `/Users/master_of_puppets/Desktop/HeartWaves/data/models/clustering_baseline/model.json`
- `/Users/master_of_puppets/Desktop/HeartWaves/data/models/clustering_baseline/evaluation.json`
