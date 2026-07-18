"""The real "الحكم الذكي" for online rooms: an async LLM fact evaluator.

Speaks the OpenAI-compatible chat-completions dialect, so one set of env
vars covers Groq, OpenRouter, OpenAI, Gemini's OpenAI endpoint, etc.:

    LLM_API_KEY     falls back to GROQ_API_KEY (already configured), so the
                    online judge works with zero new secrets
    LLM_MODEL_NAME  default: llama-3.3-70b-versatile (Groq free tier)
    LLM_BASE_URL    default: https://api.groq.com/openai/v1

Contract with the room engine (rooms.FactEvaluator):
    async (country_dict, fact) -> {"verdict": "true"|"false"|"unreliable",
                                   "explanation": str}
The LLM itself is instructed to answer with capitalized "True"/"False"/
"Unreliable"; verdicts are normalized to the engine's lowercase wire form
here. EVERY failure mode (no key, HTTP error, rate limit, timeout,
unparseable output) degrades to a safe "unreliable" verdict — the room must
never freeze or crash because a model misbehaved.

Called by rooms.evaluate_fact OUTSIDE the room lock, so a slow model never
blocks other players' actions.
"""

from __future__ import annotations

import json
import logging
import os
import re
from typing import Any

import httpx

from .countries import fact_sheet

logger = logging.getLogger(__name__)

LLM_API_KEY = (
    os.environ.get("LLM_API_KEY", "").strip()
    or os.environ.get("GROQ_API_KEY", "").strip()
)
LLM_MODEL_NAME = os.environ.get("LLM_MODEL_NAME", "llama-3.3-70b-versatile").strip()
LLM_BASE_URL = os.environ.get(
    "LLM_BASE_URL", "https://api.groq.com/openai/v1"
).strip().rstrip("/")

REQUEST_TIMEOUT_SECONDS = 25
MAX_COMPLETION_TOKENS = 400

_JSON_RE = re.compile(r"\{.*\}", re.DOTALL)

# Safe defaults for every failure mode — voting always proceeds.
_FALLBACK = {
    "verdict": "unreliable",
    "explanation": "الحكم الذكي واخد بريك دلوقتي 😅 — القرار كله لتصويتكم!",
}
_NOT_CONFIGURED = {
    "verdict": "unreliable",
    "explanation": "الحكم الذكي مش مفعّل على السيرفر — التصويت هو الحكم!",
}

SYSTEM_PROMPT = """\
انت "الحكم الذكي" في لعبة "بدون هبد!" — لعبة جماعية بيتبادل فيها اللاعيبة \
معلومات عن الدول، وانت بتحكم: المعلومة دي حقيقية ولا هبد؟

قواعدك:
- احكم على المعلومة الواحدة المذكورة عن الدولة المذكورة بس.
- اللاعيبة بيتكلموا عامية مصرية أو عربية بسيطة أو إنجليزي. افهمهم بذمة: \
اقبل الإملاء التقريبي والأرقام المقربة (في حدود ١٠٪ للسكان والمساحة).
- لو معاك بيانات موثوقة في الرسالة، اعتمد عليها الأول.

ردّك لازم يكون JSON object واحد بالظبط ومن غير أي كلام خارجه:
{"explanation": "...", "verdict": "True"}

- explanation: شرح قصير وذكي وخفيف الدم بالعامية المصرية أو العربية \
المبسطة. كلم اللاعب مباشرة: ابدأ بالحقيقة الجغرافية أو التاريخية ورا \
الموضوع، وبعدين اختم بالاستنتاج (جملتين لتلاتة بالكتير).
- verdict: قيمة واحدة بالظبط من دول: "True" لو المعلومة صح في جوهرها، \
"False" لو غلط بوضوح, "Unreliable" لو مش قادر تتأكد منها.
"""


def _normalize_verdict(raw: Any) -> str:
    """Map the model's capitalized verdict onto the engine's wire form."""
    v = str(raw or "").strip().strip('"').lower()
    return v if v in ("true", "false") else "unreliable"


def _parse_reply(content: str) -> dict[str, Any] | None:
    """Extract {"explanation", "verdict"} from model text, tolerantly."""
    candidates = [content]
    match = _JSON_RE.search(content or "")
    if match:
        candidates.append(match.group(0))
    for candidate in candidates:
        try:
            data = json.loads(candidate)
        except (json.JSONDecodeError, TypeError):
            continue
        if isinstance(data, dict) and "verdict" in data:
            return {
                "verdict": _normalize_verdict(data.get("verdict")),
                "explanation": str(data.get("explanation", "")).strip()
                or _FALLBACK["explanation"],
            }
    return None


async def llm_fact_evaluator(
    country: dict[str, Any], fact: str
) -> dict[str, Any]:
    """Judge one fact about one country. Never raises."""
    if not LLM_API_KEY:
        return dict(_NOT_CONFIGURED)

    user_prompt = (
        "بيانات موثوقة عن الدولة (اعتمد عليها لو المعلومة بتخصها):\n"
        f"{fact_sheet(country)}\n\n"
        f"الدولة: {country.get('name_ar') or country.get('name_en')}\n"
        f"معلومة اللاعب: {fact}"
    )
    payload = {
        "model": LLM_MODEL_NAME,
        "temperature": 0.2,
        "max_tokens": MAX_COMPLETION_TOKENS,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
    }

    try:
        async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT_SECONDS) as client:
            resp = await client.post(
                f"{LLM_BASE_URL}/chat/completions",
                headers={"Authorization": f"Bearer {LLM_API_KEY}"},
                json=payload,
            )
        resp.raise_for_status()
        content = resp.json()["choices"][0]["message"]["content"]
    except httpx.TimeoutException:
        logger.warning("LLM judge timed out after %ss", REQUEST_TIMEOUT_SECONDS)
        return dict(_FALLBACK)
    except httpx.HTTPStatusError as exc:
        # 429 rate limits, 413 too large, 5xx — all degrade the same way.
        logger.warning("LLM judge HTTP %s: %s",
                       exc.response.status_code, exc.response.text[:200])
        return dict(_FALLBACK)
    except Exception:
        logger.exception("LLM judge request failed")
        return dict(_FALLBACK)

    parsed = _parse_reply(content)
    if parsed is None:
        logger.warning("LLM judge returned unparseable reply: %r",
                       (content or "")[:200])
        return dict(_FALLBACK)
    return parsed
