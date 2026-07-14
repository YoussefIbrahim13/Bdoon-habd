"""Hybrid fact verification for the Smart Judge, backed by Groq.

Two paths, per the project spec:

- Objective claims (capital, population, area, currency, language) are judged
  against the REST-Countries-style dataset. The dataset is injected into the
  prompt as the only allowed source, so the verdict is grounded in structured
  data rather than the model's memory. A fast Llama model handles the
  Arabic/English comparison; no web access is needed.
- General claims (history, culture, "known for ...") use a Groq **compound**
  system, which automatically triggers a built-in web search (Tavily) so the
  verdict is grounded in live sources instead of parametric memory.

If the objective path can't decide from the dataset, it escalates to the
compound/web path automatically.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any

from groq import APIStatusError, AsyncGroq, RateLimitError

logger = logging.getLogger(__name__)

# Fast, non-reasoning model for grounded objective judging (temperature 0).
OBJECTIVE_MODEL = "llama-3.3-70b-versatile"
# Agentic system with built-in web search for general/subjective claims.
# compound-mini does a single web search (lighter token footprint than the
# full `groq/compound`, which can do several) — a better fit for the free
# tier's 6k tokens/minute budget, since search results are injected into the
# request and a multi-page search can exceed the per-request cap.
GENERAL_MODEL = "groq/compound-mini"

MAX_TOKENS = 1024
# Keep the completion small so an over-budget web search is less likely to trip
# the free-tier per-minute token cap (413 request_too_large).
GENERAL_MAX_TOKENS = 512

# Honest fallback when the online check can't complete (rate/size limited).
# We never fabricate a true/false from the model's memory for general claims —
# the human judge decides.
_RATE_LIMITED_VERDICT = {
    "verdict": "uncertain",
    "explanation": "تعذّر التحقق عبر الإنترنت الآن (تجاوز حد الاستخدام المجاني للحظة) — الحكم للبشري.",
}

# Keyword heuristic for claim classification (Arabic + English).
# Deliberately simple — the spec calls for a refinable starting point.
OBJECTIVE_KEYWORDS = [
    # capital
    "عاصم", "capital",
    # population
    "سكان", "population", "نسمة",
    # area
    "مساح", "area", "كيلومتر", "كم مربع",
    # currency
    "عمل", "currency", "جنيه", "دينار", "ريال", "درهم", "ليرة",
    # language
    "لغ", "language",
]

SYSTEM_PROMPT = """\
You are the "Smart Judge" (الحكم الذكي) in a party game about country facts. \
Two players take turns saying facts about a country; when the human judge is \
unsure about a claim, they ask you. Your answer is advisory — the human judge \
makes the final call.

Rules:
- Judge ONLY the single claim given, about the given country.
- Players speak colloquial (often Egyptian) Arabic or English. Interpret the \
claim charitably: accept common alternate spellings, transliterations, and \
rounded numbers (within about 10% for population/area).
- verdict "true": the claim is essentially correct.
- verdict "false": the claim is clearly wrong.
- verdict "uncertain": you cannot verify it either way.
- explanation: one or two short sentences, in the SAME language as the claim \
(Arabic claim → Arabic explanation). If the claim is false, state the correct \
fact.

Reply with exactly one JSON object and nothing else:
{"verdict": "true" | "false" | "uncertain", "explanation": "..."}
"""

_JSON_RE = re.compile(r"\{[^{}]*\}", re.DOTALL)


def classify_claim(claim: str) -> str:
    """Return 'objective' if the claim looks checkable against the dataset."""
    lowered = claim.casefold()
    if any(kw in lowered for kw in OBJECTIVE_KEYWORDS):
        return "objective"
    return "general"


def _parse_verdict(text: str) -> dict[str, Any]:
    """Extract the {"verdict": ..., "explanation": ...} object from model text."""
    for match in reversed(_JSON_RE.findall(text or "")):
        try:
            data = json.loads(match)
        except json.JSONDecodeError:
            continue
        if data.get("verdict") in ("true", "false", "uncertain"):
            return {
                "verdict": data["verdict"],
                "explanation": str(data.get("explanation", "")).strip(),
            }
    logger.warning("Could not parse verdict JSON from model reply: %r", (text or "")[:300])
    return {"verdict": "uncertain", "explanation": (text or "").strip()[:400]}


class SmartJudge:
    def __init__(self, api_key: str | None = None):
        # Falls back to the GROQ_API_KEY env var if api_key is None.
        self._client = AsyncGroq(api_key=api_key) if api_key else AsyncGroq()

    async def verify(self, country: dict[str, Any], claim: str, fact_sheet: str) -> dict[str, Any]:
        category = classify_claim(claim)
        if category == "objective":
            result = await self._verify_objective(country, claim, fact_sheet)
            if result["verdict"] != "uncertain":
                result["source_type"] = "objective_data"
                return result
            # Dataset couldn't settle it — fall through to web search.
        result = await self._verify_general(country, claim)
        result["source_type"] = "web_search"
        return result

    async def _verify_objective(
        self, country: dict[str, Any], claim: str, fact_sheet: str
    ) -> dict[str, Any]:
        completion = await self._client.chat.completions.create(
            model=OBJECTIVE_MODEL,
            temperature=0,
            max_completion_tokens=MAX_TOKENS,
            # JSON object mode (the system prompt names the JSON shape).
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": (
                        "Authoritative data (use ONLY this — if the claim can't be "
                        "decided from it, answer uncertain):\n"
                        f"{fact_sheet}\n\n"
                        f"Country: {country['name_en']}\n"
                        f"Claim: {claim}"
                    ),
                },
            ],
        )
        return _parse_verdict(completion.choices[0].message.content)

    async def _verify_general(self, country: dict[str, Any], claim: str) -> dict[str, Any]:
        # The compound system decides on its own whether to hit the web, runs
        # the search server-side, and returns the final answer in one call.
        try:
            completion = await self._client.chat.completions.create(
                model=GENERAL_MODEL,
                temperature=0,
                max_completion_tokens=GENERAL_MAX_TOKENS,
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": (
                            f"Country: {country['name_en']} ({country['name_ar']})\n"
                            f"Claim: {claim}\n\n"
                            "Verify this using web search before answering."
                        ),
                    },
                ],
            )
        except (RateLimitError, APIStatusError) as exc:
            # 429 (per-minute rate limit) or 413 (a big web search blew past the
            # free-tier token budget). Degrade to an honest "uncertain" instead
            # of failing the whole request.
            status = getattr(exc, "status_code", None)
            if isinstance(exc, RateLimitError) or status in (413, 429):
                logger.warning("Web verification degraded (Groq %s): %s", status, exc)
                return dict(_RATE_LIMITED_VERDICT)
            raise
        return _parse_verdict(completion.choices[0].message.content)
