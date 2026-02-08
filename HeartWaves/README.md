# HeartWaves (Hackathon Demo)

Local-only, non-diagnostic health screening demo:
- Upload Apple Health export ZIP or `export.xml`
- Compute last-30-day aggregates (Resting HR, HRV SDNN, stand/exercise minutes)
- Classify `normal` vs `needs_followup` using personal-baseline rules
- Capture questionnaire answers and persist them in-session
- Generate a doctor-ready HTML report (print to PDF)

## Run

```bash
cd /Users/master_of_puppets/Desktop/HeartWaves
ruby server.rb
```

Open `http://localhost:4567`.

## Gemini (Optional)

If you have a Gemini Developer API key (Google AI Studio), run:

```bash
cd /Users/master_of_puppets/Desktop/HeartWaves
GOOGLE_API_KEY="YOUR_KEY_HERE" ruby server.rb
```

The UI has a “Use Gemini” toggle on import. If the key is missing, the app falls back to rules-only.
The app accepts either `GOOGLE_API_KEY` or `GEMINI_API_KEY`.

## Notes

- Data is processed locally and stored only in `./tmp` during the session.
- This is not a diagnosis tool.
