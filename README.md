# بدون هبد! (Bedoon Habd) — AI-Assisted Country Facts Party Game

**بدون هبد!** ("Bedoon Habd" — roughly *"No nonsense!"*) is a local
pass-and-play party game: two players take turns saying facts about a
country shown on screen, and a human **Judge** (holding the phone) rules on
each fact. When the Judge is unsure, they can ask the **Smart Judge** — an
AI fact-checker whose verdict is *advisory only*; the human always makes the
final call. A round ends when a fact is ruled false; the other player scores.
First to the target score (default 5) wins.

## Layout

```
app/       Flutter app (Arabic-first, RTL) — the Judge's UI
backend/   FastAPI service — country data + Smart Judge fact checking
```

## Backend

```powershell
cd backend
py -m venv .venv                     # already created if you ran the scaffold
.\.venv\Scripts\pip install -r requirements.txt
copy .env.example .env               # put your GROQ_API_KEY in .env
.\.venv\Scripts\python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

The Groq key (free tier — get one at <https://console.groq.com/keys>) lives
**only** on the backend — never in the Flutter app (an APK can be decompiled).
Without a key the server still runs: `/countries` works and `/verify-fact`
returns a friendly 503.

### Endpoints

| Endpoint | Description |
|---|---|
| `GET /health` | Liveness + country count |
| `GET /countries` | 194 countries: code, English/Arabic name, flag URLs |
| `POST /verify-fact` | `{"country": "EG", "claim": "..."}` → `{"verdict": "true"\|"false"\|"uncertain", "explanation": "...", "source_type": "objective_data"\|"web_search"}` |

### How verification works (hybrid, per the spec)

1. A keyword heuristic (Arabic + English) classifies the claim.
2. **Objective claims** (capital, population, area, currency, language) are
   judged by a fast Groq Llama model (`llama-3.3-70b-versatile`, temperature 0,
   JSON mode) against a fact sheet from the structured country dataset,
   injected as the *only* allowed source — grounded data, no web search, fast.
   If the dataset can't settle it, the claim escalates to path 3.
3. **General claims** (history, culture, "known for…") are judged by a Groq
   **compound** system (`groq/compound`), which automatically triggers a
   built-in web search (Tavily) so verdicts are grounded in live sources
   rather than the model's memory.

Verdicts are cached in-memory per (country, claim), and there's a naive
per-IP rate limit (20/min).

> **Data source note — deviation from the brief:** the brief suggested the
> REST Countries API ("free, no key"), but as of mid-2026 REST Countries
> v1–v4 are shut down and v5 requires a paid API key. The backend instead
> merges three free, keyless sources at startup (cached to
> `countries_cache.json` for offline restarts):
> [mledoze/countries](https://github.com/mledoze/countries) (names incl.
> Arabic, capital, area, currencies, languages), the World Bank API
> (population), and [flagcdn.com](https://flagcdn.com) (flag images).

## Flutter app

```powershell
cd app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000    # Android emulator
# real phone on the same Wi-Fi: use your PC's LAN IP
# flutter run --dart-define=API_BASE_URL=http://192.168.1.x:8000
# desktop/web on the same machine: no define needed (defaults to localhost:8000)
```

Screens:

- **Home** — player names, target score, start.
- **Game** — flag + country name (ar/en), score board, turn indicator, and the
  Judge's controls: **غلط!** (rule false → other player scores, next round),
  **صح — التالي** (accept fact, pass turn), shuffle icon (swap country without
  scoring), and **اسأل الحكم الذكي** (Smart Judge bottom sheet).
- **Smart Judge sheet** — type the disputed claim, get a color-coded advisory
  verdict (green/red/amber) with a short explanation and its source.

State is in-session only (Provider `ChangeNotifier`) — no accounts, no
persistence, per the v1 scope.

## v1 scope decisions (from the project brief)

- AI verdicts are advisory; the human Judge has final say.
- Claim input is typed text (voice is a later phase).
- Turn order is managed by the humans; the app just tracks the indicator.
- Country name is shown alongside the flag (not a guessing game).
- Match win condition configurable, default first-to-5.

## Suggested next phases

1. Voice input for claims (speech-to-text → same `/verify-fact` contract).
2. Local persistent match history (Hive/SharedPreferences).
3. Category/difficulty filters; online multiplayer.
