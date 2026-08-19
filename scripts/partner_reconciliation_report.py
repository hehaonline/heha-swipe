#!/usr/bin/env python3
"""Build a deterministic, synthetic-only partner reconciliation report.

This tool is deliberately incapable of selecting a canonical partner or applying a
mutation. It accepts only conspicuously synthetic fixtures and emits pairwise
classifications for named-human review.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit


SCHEMA_VERSION = "heha.partner-reconciliation.synthetic/v1"
REPORT_VERSION = "heha.partner-reconciliation.report/v1"
ID_RE = re.compile(r"^SYN-[A-Z0-9-]+$")
OWNER_RE = re.compile(r"^SYN-OWNER-[A-Z0-9-]+$")
PLACE_RE = re.compile(r"^SYN-PLACE-[A-Z0-9-]+$")
PHONE_RE = re.compile(r"^1?[2-9][0-9]{2}55501[0-9]{2}$")
INSTAGRAM_RE = re.compile(r"^synthetic_[a-z0-9_]+$")

STATIC_STRONG_FIELDS = (
    "google_place_id",
    "domain",
    "phone",
    "instagram",
)

VERIFIED_EMAIL_PROVENANCE = {
    "owner_confirmed",
    "authorized_business_contact",
}
EMAIL_PROVENANCE_VALUES = VERIFIED_EMAIL_PROVENANCE | {"unverified", "not_applicable"}

ROOT_KEYS = {
    "schema_version",
    "data_classification",
    "synthetic",
    "mutation_mode",
    "records",
    "expected_pairs",
}
RECORD_KEYS = {
    "id",
    "synthetic",
    "record_kind",
    "name",
    "address",
    "google_place_id",
    "website",
    "phone",
    "email",
    "email_provenance",
    "instagram",
    "owner_account_id",
    "child_reference_counts",
}
EXPECTED_PAIR_KEYS = {"candidate_key", "classification"}
CLASSIFICATIONS = {
    "non_partner_source",
    "ownership_conflict",
    "strong_identifier_match",
    "likely_match",
    "separate_businesses",
    "insufficient_evidence",
}

CHILD_REFERENCE_FAMILIES = (
    "saves",
    "swipes",
    "analytics",
    "requests",
    "media",
    "routing",
    "local_bridge",
    "profile_changes",
    "offers",
    "readiness",
    "platform_visibility",
    "crm_links",
    "scout_links",
)


class InputRejected(ValueError):
    """Raised when an input is not provably synthetic."""


def normalize_text(value: Any) -> str:
    text = unicodedata.normalize("NFKD", str(value or ""))
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return " ".join(re.sub(r"[^a-z0-9]+", " ", text.lower()).split())


def normalize_phone(value: Any) -> str:
    digits = re.sub(r"\D", "", str(value or ""))
    if len(digits) == 11 and digits.startswith("1"):
        return digits[1:]
    return digits


def normalize_domain(value: Any) -> str:
    raw = str(value or "").strip().lower()
    if not raw:
        return ""
    _require(not any(ch.isspace() for ch in raw), "website must not contain whitespace")
    parsed = urlsplit(raw if "://" in raw else f"https://{raw}")
    _require(parsed.scheme in {"http", "https"}, "website must use http or https")
    _require(bool(parsed.netloc and parsed.hostname), "website must contain a hostname")
    _require(parsed.username is None and parsed.password is None, "website credentials are not allowed")
    try:
        parsed.port
    except ValueError as exc:
        raise InputRejected("website port is invalid") from exc
    host = str(parsed.hostname).rstrip(".")
    return host[4:] if host.startswith("www.") else host


def normalize_email(value: Any) -> str:
    return str(value or "").strip().lower()


def normalize_instagram(value: Any) -> str:
    raw = str(value or "").strip().lower()
    raw = re.sub(r"^https?://(www\.)?instagram\.com/", "", raw)
    return raw.strip("/@ ")


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise InputRejected(message)


def _validate_synthetic_record(record: dict[str, Any]) -> None:
    _require(set(record) == RECORD_KEYS, "record fields must match the declared synthetic schema exactly")
    record_id = str(record.get("id", ""))
    _require(record.get("synthetic") is True, f"{record_id or 'record'}: synthetic=true is required")
    _require(bool(ID_RE.fullmatch(record_id)), f"{record_id or 'record'}: invalid synthetic id")
    _require(
        record.get("record_kind") in {"partner_candidate", "shopping_source"},
        f"{record_id}: unsupported record_kind",
    )
    _require(str(record.get("name", "")).startswith("Synthetic "), f"{record_id}: name must start with 'Synthetic '")

    owner = str(record.get("owner_account_id", ""))
    if owner:
        _require(bool(OWNER_RE.fullmatch(owner)), f"{record_id}: owner_account_id is not synthetic")

    place_id = str(record.get("google_place_id", ""))
    if place_id:
        _require(bool(PLACE_RE.fullmatch(place_id)), f"{record_id}: google_place_id is not synthetic")

    email = normalize_email(record.get("email"))
    email_provenance = str(record.get("email_provenance", ""))
    _require(email_provenance in EMAIL_PROVENANCE_VALUES, f"{record_id}: invalid email_provenance")
    if email:
        _require("@" in email and email.rsplit("@", 1)[1].endswith(".test"), f"{record_id}: email must use a .test domain")
        _require(email_provenance != "not_applicable", f"{record_id}: email provenance is required")
    else:
        _require(email_provenance == "not_applicable", f"{record_id}: email_provenance must be not_applicable without email")

    domain = normalize_domain(record.get("website"))
    if domain:
        _require(domain.endswith(".test"), f"{record_id}: website must use a .test domain")

    phone = re.sub(r"\D", "", str(record.get("phone", "")))
    if phone:
        _require(bool(PHONE_RE.fullmatch(phone)), f"{record_id}: phone must use the reserved 555-01xx fixture range")

    instagram = normalize_instagram(record.get("instagram"))
    if instagram:
        _require(bool(INSTAGRAM_RE.fullmatch(instagram)), f"{record_id}: Instagram handle is not synthetic")

    address = str(record.get("address", ""))
    if address:
        _require("Example" in address, f"{record_id}: address must contain the synthetic marker 'Example'")

    counts = record.get("child_reference_counts", {})
    _require(isinstance(counts, dict), f"{record_id}: child_reference_counts must be an object")
    _require(set(counts) == set(CHILD_REFERENCE_FAMILIES), f"{record_id}: child-reference family inventory is incomplete")
    for family, count in counts.items():
        _require(isinstance(count, int) and not isinstance(count, bool) and count >= 0, f"{record_id}: invalid {family} count")


def validate_dataset(dataset: dict[str, Any]) -> list[dict[str, Any]]:
    _require(isinstance(dataset, dict), "input root must be an object")
    _require(set(dataset) == ROOT_KEYS, "input fields must match the declared synthetic schema exactly")
    _require(dataset.get("schema_version") == SCHEMA_VERSION, "unsupported or missing synthetic schema_version")
    _require(dataset.get("data_classification") == "synthetic", "data_classification=synthetic is required")
    _require(dataset.get("synthetic") is True, "dataset synthetic=true is required")
    _require(dataset.get("mutation_mode") == "disabled", "mutation_mode=disabled is required")
    records = dataset.get("records")
    _require(isinstance(records, list) and len(records) >= 2, "at least two synthetic records are required")
    seen: set[str] = set()
    for record in records:
        _require(isinstance(record, dict), "every record must be an object")
        _validate_synthetic_record(record)
        _require(record["id"] not in seen, f"duplicate record id: {record['id']}")
        seen.add(record["id"])
    ordered = sorted(records, key=lambda item: item["id"])
    expected_pairs = dataset.get("expected_pairs")
    _require(isinstance(expected_pairs, list), "expected_pairs must be a list")
    valid_candidate_keys = {
        candidate_key_for(ordered[i]["id"], ordered[j]["id"])
        for i in range(len(ordered))
        for j in range(i + 1, len(ordered))
    }
    seen_expected: set[str] = set()
    for expected in expected_pairs:
        _require(isinstance(expected, dict), "every expected pair must be an object")
        _require(set(expected) == EXPECTED_PAIR_KEYS, "expected-pair fields must match the declared schema exactly")
        candidate_key = expected.get("candidate_key")
        _require(isinstance(candidate_key, str) and candidate_key in valid_candidate_keys, "expected pair references an unknown candidate")
        _require(candidate_key not in seen_expected, f"duplicate expected candidate: {candidate_key}")
        _require(expected.get("classification") in CLASSIFICATIONS, f"{candidate_key}: invalid expected classification")
        seen_expected.add(candidate_key)
    return ordered


def normalized_identifiers(record: dict[str, Any]) -> dict[str, str]:
    return {
        "google_place_id": str(record.get("google_place_id", "")).strip(),
        "domain": normalize_domain(record.get("website")),
        "phone": normalize_phone(record.get("phone")),
        "email": normalize_email(record.get("email")),
        "email_provenance": str(record.get("email_provenance", "")),
        "instagram": normalize_instagram(record.get("instagram")),
        "name": normalize_text(record.get("name")),
        "address": normalize_text(record.get("address")),
        "owner_account_id": str(record.get("owner_account_id", "")).strip(),
    }


def _pair_result(
    left: dict[str, Any],
    right: dict[str, Any],
    classification: str,
    reason: str,
    matched_fields: list[str],
    conflicting_fields: list[str],
    next_action: str,
) -> dict[str, Any]:
    candidate_key = candidate_key_for(left["id"], right["id"])
    return {
        "candidate_key": candidate_key,
        "left_record_id": left["id"],
        "right_record_id": right["id"],
        "classification": classification,
        "reason": reason,
        "matched_fields": sorted(matched_fields),
        "conflicting_fields": sorted(conflicting_fields),
        "next_action": next_action,
        "decision_status": "pending_named_human_review",
        "canonical_partner_id": None,
        "manual_review_required": True,
        "mutation_allowed": False,
        "claim_allowed": False,
        "official_partner_allowed": False,
        "reference_preservation_manifest": {
            left["id"]: {family: left["child_reference_counts"][family] for family in CHILD_REFERENCE_FAMILIES},
            right["id"]: {family: right["child_reference_counts"][family] for family in CHILD_REFERENCE_FAMILIES},
        },
    }


def candidate_key_for(left_id: str, right_id: str) -> str:
    """Return an injective, order-independent key using length-prefixed IDs."""
    ordered = sorted((str(left_id), str(right_id)))
    return "SYN-PAIR|" + "|".join(f"{len(record_id)}:{record_id}" for record_id in ordered)


def classify_pair(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    _require(isinstance(left, dict) and isinstance(right, dict), "pair records must be objects")
    _validate_synthetic_record(left)
    _validate_synthetic_record(right)
    _require(left["id"] != right["id"], "pair records must have different ids")
    left_norm = normalized_identifiers(left)
    right_norm = normalized_identifiers(right)
    matched = [field for field in STATIC_STRONG_FIELDS if left_norm[field] and left_norm[field] == right_norm[field]]
    conflicts = [
        field
        for field in STATIC_STRONG_FIELDS
        if left_norm[field] and right_norm[field] and left_norm[field] != right_norm[field]
    ]
    both_emails_verified = (
        left_norm["email_provenance"] in VERIFIED_EMAIL_PROVENANCE
        and right_norm["email_provenance"] in VERIFIED_EMAIL_PROVENANCE
    )
    unverified_email_matches: list[str] = []
    if left_norm["email"] and left_norm["email"] == right_norm["email"]:
        if both_emails_verified:
            matched.append("email")
        else:
            unverified_email_matches.append("email_unverified")
    elif both_emails_verified and left_norm["email"] and right_norm["email"]:
        conflicts.append("email")
    owners_conflict = bool(
        left_norm["owner_account_id"]
        and right_norm["owner_account_id"]
        and left_norm["owner_account_id"] != right_norm["owner_account_id"]
    )
    name_equal = bool(left_norm["name"] and left_norm["name"] == right_norm["name"])
    address_equal = bool(left_norm["address"] and left_norm["address"] == right_norm["address"])
    name_similarity = SequenceMatcher(None, left_norm["name"], right_norm["name"]).ratio()
    place_match = "google_place_id" in matched
    place_conflict = "google_place_id" in conflicts
    secondary_matches = [field for field in matched if field != "google_place_id"]
    secondary_conflicts = [field for field in conflicts if field != "google_place_id"]

    if "shopping_source" in {left["record_kind"], right["record_kind"]}:
        return _pair_result(
            left,
            right,
            "non_partner_source",
            "A shopping-source record cannot become a claimable or Official Partner by identity inference.",
            matched,
            conflicts,
            "retain_nonclaimable_source_and_review_any_link_separately",
        )

    if owners_conflict and (matched or (name_equal and address_equal)):
        reason = (
            "At least one provenance-qualified strong identifier matches while owner-account evidence conflicts; "
            "ownership conflict overrides matching evidence."
            if matched
            else "Normalized name and address match while owner-account evidence conflicts; ownership must be resolved by a named human."
        )
        return _pair_result(
            left,
            right,
            "ownership_conflict",
            reason,
            matched + unverified_email_matches,
            conflicts + ["owner_account_id"],
            "freeze_claim_and_escalate_to_named_human",
        )

    identity_contradiction = (
        (place_conflict and len(secondary_matches) >= 2)
        or (place_match and len(secondary_conflicts) >= 3 and left_norm["address"] and right_norm["address"] and not address_equal)
    )
    if identity_contradiction:
        return _pair_result(
            left,
            right,
            "ownership_conflict",
            "Strong identity signals contradict one another; reconciliation must stop for named-human review.",
            matched,
            conflicts + ["identity_contradiction"],
            "freeze_claim_and_escalate_to_named_human",
        )

    strong_match = place_match or (len(secondary_matches) >= 2 and (name_similarity >= 0.82 or address_equal))

    if strong_match:
        return _pair_result(
            left,
            right,
            "strong_identifier_match",
            "An exact Google Place ID or at least two independent normalized signals match, but no canonical record is selected automatically.",
            matched,
            conflicts,
            "prepare_private_dry_run_for_named_human_review",
        )

    if name_equal and address_equal and not owners_conflict:
        return _pair_result(
            left,
            right,
            "likely_match",
            "Normalized name and address match, but fewer than two provenance-qualified strong identifiers are present; corroboration is still required.",
            matched + unverified_email_matches + ["normalized_name", "normalized_address"],
            conflicts,
            "collect_authorized_corroboration_for_named_human_review",
        )

    separation_signals = len(conflicts) + int(owners_conflict) + int(bool(left_norm["address"] and right_norm["address"] and not address_equal))
    if name_similarity >= 0.82 and separation_signals >= 2:
        conflict_list = conflicts + (["owner_account_id"] if owners_conflict else [])
        if left_norm["address"] and right_norm["address"] and not address_equal:
            conflict_list.append("normalized_address")
        return _pair_result(
            left,
            right,
            "separate_businesses",
            "Names are similar, but location, ownership, or strong identifiers conflict; keep the records separate.",
            [],
            conflict_list,
            "keep_separate_and_block_automatic_reconciliation",
        )

    if matched or unverified_email_matches:
        return _pair_result(
            left,
            right,
            "likely_match",
            "One normalized identifier matches, but strong-match requirements are not met.",
            matched + unverified_email_matches,
            conflicts,
            "collect_authorized_corroboration_for_named_human_review",
        )

    return _pair_result(
        left,
        right,
        "insufficient_evidence",
        "The available synthetic identifiers do not support a deterministic relationship.",
        [],
        conflicts + (["owner_account_id"] if owners_conflict else []),
        "leave_unresolved_for_named_human_review",
    )


def build_report(dataset: dict[str, Any]) -> dict[str, Any]:
    records = validate_dataset(dataset)
    canonical_input = json.dumps(dataset, sort_keys=True, separators=(",", ":")).encode("utf-8")
    pairs = sorted(
        (classify_pair(records[i], records[j]) for i in range(len(records)) for j in range(i + 1, len(records))),
        key=lambda item: item["candidate_key"],
    )
    return {
        "schema_version": REPORT_VERSION,
        "source_schema_version": SCHEMA_VERSION,
        "source_sha256": hashlib.sha256(canonical_input).hexdigest(),
        "synthetic_only": True,
        "record_count": len(records),
        "pair_count": len(pairs),
        "canonical_selection_performed": False,
        "mutation_allowed": False,
        "required_child_reference_families": list(CHILD_REFERENCE_FAMILIES),
        "pairs": pairs,
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Synthetic JSON fixture")
    parser.add_argument("--output", type=Path, help="Report path; omit to write to stdout")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        dataset = json.loads(args.input.read_text(encoding="utf-8"))
        report = build_report(dataset)
    except (OSError, json.JSONDecodeError, InputRejected) as exc:
        print(f"partner reconciliation input rejected: {exc}", file=sys.stderr)
        return 2

    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(payload, encoding="utf-8")
    else:
        sys.stdout.write(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
