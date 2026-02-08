# HeartWaves Demo Exports

Generated demo files:
- `data/demo/normal_export.xml`
- `data/demo/needs_followup_export.xml`
- `data/demo/normal_cluster_export.xml`
- `data/demo/normal_export_bundle.zip`
- `data/demo/needs_followup_export_bundle.zip`
- `data/demo/normal_cluster_export_bundle.zip`

## Expected Behavior
- `normal_export.xml` -> baseline screen should land on `normal`.
- `normal_cluster_export.xml` -> tuned for clustering-model normal behavior (HRV intentionally absent for this demo profile).
- `needs_followup_export.xml` -> baseline screen should land on `needs_followup` (typically `pots_like` from HR + HRV shift).

## To Show Stronger Clustering-Model Follow-Up In Demo
After selecting `needs_followup_export.xml`, also fill the Orthostatic Quick Check fields:
- `Sitting/rest HR`: `72`
- `Standing HR`: `108`
- `Sitting SBP`: `118`
- `Standing SBP`: `114`

This gives the clustering path enough feature coverage to confidently show a `needs_followup` orthostatic pattern in the current model merge logic.

## Regenerate Anytime
```bash
cd /Users/master_of_puppets/Desktop/HeartWaves
./scripts/generate_demo_health_exports.rb
```
