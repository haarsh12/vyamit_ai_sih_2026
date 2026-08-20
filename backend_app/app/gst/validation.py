"""Format-level GST validation; no external taxpayer lookup is implied."""

from __future__ import annotations

import re

from app.gst.constants import GST_STATE_NAMES_TO_CODES, GST_STATES


GSTIN_PATTERN = re.compile(r"^(?P<state>\d{2})(?P<pan>[A-Z]{5}\d{4}[A-Z])(?P<entity>[1-9A-Z])Z(?P<check>[0-9A-Z])$")
_CHECKSUM_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def normalize_gstin(value: str) -> str:
    return re.sub(r"\s+", "", value or "").upper()


def gstin_checksum(gstin_without_checksum: str) -> str:
    if len(gstin_without_checksum) != 14:
        raise ValueError("GSTIN checksum input must contain 14 characters")
    total, factor = 0, 2
    for character in reversed(gstin_without_checksum):
        try:
            value = _CHECKSUM_ALPHABET.index(character)
        except ValueError as error:
            raise ValueError("GSTIN contains an invalid checksum character") from error
        product = value * factor
        total += (product // 36) + (product % 36)
        factor = 1 if factor == 2 else 2
    return _CHECKSUM_ALPHABET[(36 - (total % 36)) % 36]


def validate_gstin(value: str) -> str:
    gstin = normalize_gstin(value)
    match = GSTIN_PATTERN.fullmatch(gstin)
    if match is None:
        raise ValueError("GSTIN must be a 15-character GST identification number")
    if match.group("state") not in GST_STATES:
        raise ValueError("GSTIN contains an unsupported state code")
    if gstin[-1] != gstin_checksum(gstin[:-1]):
        raise ValueError("GSTIN checksum is invalid")
    return gstin


def validate_state_code(value: str) -> str:
    code = str(value or "").strip().zfill(2)
    if code not in GST_STATES:
        raise ValueError("state_code must be a valid Indian GST state or UT code")
    return code


def validate_state_matches_code(state: str, state_code: str) -> str:
    code = validate_state_code(state_code)
    canonical = GST_STATE_NAMES_TO_CODES.get(" ".join(str(state or "").split()).casefold())
    if canonical is None:
        raise ValueError("state must be a valid Indian GST state or UT name")
    if canonical != code:
        raise ValueError("state name must match the supplied GST state code")
    return GST_STATES[code]


def validate_gstin_matches_state(gstin: str, state_code: str) -> None:
    if gstin[:2] != validate_state_code(state_code):
        raise ValueError("GSTIN state code must match the configured registration state")
