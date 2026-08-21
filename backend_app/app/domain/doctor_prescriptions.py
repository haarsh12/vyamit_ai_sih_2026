"""Safety-first formatting for doctor dictation.

The formatter is intentionally extractive: it never diagnoses, recommends, or
creates a prescription record.  A licensed user edits and explicitly confirms
the resulting draft before the print record endpoint persists anything.
"""

from __future__ import annotations

import re
from typing import Any


_MEDICATION_FIELDS = ("name", "dose", "frequency", "duration", "timing", "route", "instructions")


def _text(value: object, maximum: int) -> str:
    return str(value or "").strip()[:maximum]


def _extract_draft(transcription: str) -> dict[str, Any]:
    """Make a conservative local draft when an authorised LiveKit turn is absent."""

    text = transcription.strip()
    patient: dict[str, str | int | None] = {"name": "", "age": None, "gender": "", "phone": ""}
    name_match = re.search(r"(?:patient(?:\s+name)?\s*(?:is|:)?\s*)([A-Za-z][A-Za-z .'-]{1,80})", text, re.I)
    if name_match:
        patient["name"] = re.sub(
            r"\s+\b(?:age|years?|yrs?|male|female|other|\d{1,3})\b.*$", "", name_match.group(1), flags=re.I
        ).strip(" ,.-:")[:120]
    age_match = re.search(
        r"\b(?:age\s*(\d{1,3})\b|(\d{1,3})\s*(?:years?|yrs?)\b)",
        text,
        re.I,
    )
    if age_match:
        age = int(age_match.group(1) or age_match.group(2))
        if age <= 130:
            patient["age"] = age
    gender_match = re.search(r"\b(male|female|other)\b", text, re.I)
    if gender_match:
        patient["gender"] = gender_match.group(1).title()
    phone_match = re.search(r"\b(?:phone|mobile)\s*(?:number)?\s*(?:is|:)?\s*(\+?\d[\d -]{8,18})", text, re.I)
    if phone_match:
        patient["phone"] = re.sub(r"\s+", "", phone_match.group(1))[:20]

    diagnosis_match = re.search(r"\b(?:diagnosis|diagnosed with|for)\s*[:\-]?\s*([^,.;]+)", text, re.I)
    diagnosis = diagnosis_match.group(1).strip()[:500] if diagnosis_match else ""
    frequency = next((label for pattern, label in (
        (r"\b(?:once daily|ek baar(?: roz)?|din mein ek baar)\b", "Once daily"),
        (r"\b(?:twice daily|do baar(?: roz)?|din mein do baar)\b", "Twice daily"),
        (r"\b(?:three times daily|thrice daily|teen baar(?: roz)?|din mein teen baar)\b", "Three times daily"),
    ) if re.search(pattern, text, re.I)), "")
    every_hours = re.search(r"\bevery\s+(\d+)\s+hours?\b", text, re.I)
    if not frequency and every_hours:
        frequency = f"Every {every_hours.group(1)} hours"
    timing = "After food" if re.search(r"\b(?:after\s+(?:food|meal)|kha?ne\s+ke\s+baad)\b", text, re.I) else ""
    if not timing and re.search(r"\b(?:before\s+(?:food|meal)|kha?ne\s+se\s+pehle)\b", text, re.I):
        timing = "Before food"
    duration_match = re.search(r"\b(?:for\s+)?(\d+)\s*(day|days|week|weeks|month|months|din|haft(?:a|e)|mahine?)\b", text, re.I)
    duration = ""
    if duration_match:
        count, unit = duration_match.groups()
        normalised = {"din": "day", "hafta": "week", "hafte": "week", "mahine": "month"}.get(unit.casefold(), unit.casefold().rstrip("s"))
        duration = f"{count} {normalised}{'' if count == '1' else 's'}"
    dose_match = re.search(r"\b(\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|tablet(?:s)?|tab(?:s)?|capsule(?:s)?|cap(?:s)?))\b", text, re.I)
    dose = dose_match.group(1)[:80] if dose_match else ""

    medication_source = ""
    introduced = re.search(r"\b(?:prescribe|prescribed|give|take|medicine(?:\s+name)?\s*(?:is)?|tablet|capsule)\s+(.+)$", text, re.I)
    if introduced:
        medication_source = introduced.group(1)
    dose_match = re.search(
        r"\b(\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|tablet(?:s)?|tab(?:s)?|capsule(?:s)?|cap(?:s)?))\b",
        medication_source,
        re.I,
    )
    medicine_name = ""
    if medication_source:
        # A dose unambiguously ends the drug name. Keeping that boundary stops
        # frequency/timing words becoming part of the editable medicine name.
        medicine_source = medication_source[:dose_match.start()] if dose_match else medication_source
        medicine_match = re.match(r"\s*([A-Za-z][A-Za-z0-9-]*(?:\s+[A-Za-z0-9-]+){0,2})", medicine_source)
        medicine_name = medicine_match.group(1).strip(" ,.")[:120] if medicine_match else ""
    medications: list[dict[str, str]] = []
    if medicine_name and medicine_name.casefold() not in {"patient", "diagnosis", "medicine"}:
        start = medication_source.casefold().find(dose.casefold()) + len(dose) if dose else len(medicine_name)
        instructions = medication_source[max(start, 0):].strip(" ,.;:-")[:400]
        medications.append({
            "name": medicine_name, "dose": dose, "frequency": frequency, "duration": duration,
            "timing": timing, "route": "", "instructions": instructions,
        })
    return {
        "patient": patient, "diagnosis": diagnosis, "medications": medications,
        "additional_notes": "", "english_transcript": text[:2_000],
    }


def format_dictation(transcription: str) -> dict[str, object]:
    """Return only an editable draft; callers must not persist this response."""

    draft = _extract_draft(transcription)
    # Retain only defined fields even if the parser changes in the future.
    draft["medications"] = [
        {field: _text(medication.get(field), 400 if field == "instructions" else 120) for field in _MEDICATION_FIELDS}
        for medication in draft["medications"][:20]
        if medication.get("name")
    ]
    return {
        "type": "PRESCRIPTION_DRAFT",
        "draft": draft,
        "message": "Prescription draft ready for clinical review.",
    }
