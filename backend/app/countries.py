"""Country dataset assembled from free, keyless sources, cached to disk.

The project brief suggested the REST Countries API, but as of mid-2026 it
requires a paid account + API key (v1–v4 were taken down, v5 is key-gated).
Equivalent data comes from:

- mledoze/countries (the dataset REST Countries was built on): names incl.
  Arabic translations, capital, area, currencies, languages.
- World Bank API: population (most recent value per country).
- flagcdn.com: flag images by ISO code.

This structured data is the "ground truth" used to verify objective claims
(capital, population, area, currency, language) without relying on the
LLM's parametric memory.
"""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any

import httpx

logger = logging.getLogger(__name__)

CACHE_FILE = Path(__file__).resolve().parent.parent / "countries_cache.json"

COUNTRIES_URL = "https://raw.githubusercontent.com/mledoze/countries/master/countries.json"
POPULATION_URL = (
    "https://api.worldbank.org/v2/country/all/indicator/SP.POP.TOTL"
    "?format=json&mrnev=1&per_page=400"
)


def _parse(raw: list[dict[str, Any]], populations: dict[str, tuple[int, str]]) -> list[dict[str, Any]]:
    countries = []
    for item in raw:
        # Independent states with a capital make the best game rounds;
        # this drops territories like Bouvet Island.
        if not item.get("independent"):
            continue
        capital = (item.get("capital") or [None])[0]
        if not capital:
            continue
        name_ar = ((item.get("translations") or {}).get("ara") or {}).get("common")
        currencies = [
            c.get("name") for c in (item.get("currencies") or {}).values() if c.get("name")
        ]
        code = item["cca2"]
        population, population_year = populations.get(item["cca3"], (None, None))
        countries.append(
            {
                "code": code,
                "name_en": item["name"]["common"],
                "name_official": item["name"].get("official"),
                "name_ar": name_ar or item["name"]["common"],
                "flag_png": f"https://flagcdn.com/w320/{code.lower()}.png",
                "flag_svg": f"https://flagcdn.com/{code.lower()}.svg",
                "capital": capital,
                "population": population,
                "population_year": population_year,
                "area_km2": item.get("area"),
                "currencies": currencies,
                "languages": list((item.get("languages") or {}).values()),
                "region": item.get("region"),
            }
        )
    countries.sort(key=lambda c: c["name_en"])
    return countries


async def load_countries() -> list[dict[str, Any]]:
    """Fetch and merge the sources, falling back to the on-disk cache."""
    try:
        async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
            countries_resp, pop_resp = await asyncio.gather(
                client.get(COUNTRIES_URL), client.get(POPULATION_URL)
            )
            countries_resp.raise_for_status()
            pop_resp.raise_for_status()

        populations: dict[str, tuple[int, str]] = {}
        for entry in pop_resp.json()[1]:
            iso3 = entry.get("countryiso3code")
            if iso3 and entry.get("value") is not None:
                populations[iso3] = (int(entry["value"]), entry.get("date", ""))

        countries = _parse(countries_resp.json(), populations)
        CACHE_FILE.write_text(json.dumps(countries, ensure_ascii=False), encoding="utf-8")
        logger.info("Loaded %d countries from upstream sources", len(countries))
        return countries
    except Exception as exc:
        if CACHE_FILE.exists():
            logger.warning("Country data fetch failed (%s); using disk cache", exc)
            return json.loads(CACHE_FILE.read_text(encoding="utf-8"))
        raise RuntimeError(
            "Could not fetch country data and no local cache exists. "
            "Check the internet connection and restart."
        ) from exc


def find_country(countries: list[dict[str, Any]], query: str) -> dict[str, Any] | None:
    """Match a country by ISO code, English name, or Arabic name (case-insensitive)."""
    q = query.strip().casefold()
    for c in countries:
        if q == c["code"].casefold() or q == c["name_en"].casefold() or q == c["name_ar"]:
            return c
    # Loose fallback: unique substring match on either name.
    matches = [
        c for c in countries
        if q in c["name_en"].casefold() or q in c["name_ar"]
    ]
    return matches[0] if len(matches) == 1 else None


def fact_sheet(country: dict[str, Any]) -> str:
    """Compact, authoritative fact block injected into the objective-claim prompt."""
    area = country.get("area_km2")
    population = country.get("population")
    pop_line = (
        f"Population: {population:,} (World Bank, {country.get('population_year')})"
        if population
        else "Population: unknown"
    )
    return "\n".join(
        [
            f"Country: {country['name_en']} ({country['name_ar']}) — code {country['code']}",
            f"Official name: {country.get('name_official') or country['name_en']}",
            f"Capital: {country['capital']}",
            pop_line,
            f"Area: {f'{area:,.0f} km²' if area else 'unknown'}",
            f"Currencies: {', '.join(country['currencies']) or 'unknown'}",
            f"Official/major languages: {', '.join(country['languages']) or 'unknown'}",
            f"Region: {country.get('region') or 'unknown'}",
        ]
    )
