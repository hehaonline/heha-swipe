from __future__ import annotations

import ast
import copy
import hashlib
import importlib.util
import io
import json
import re
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "scripts" / "partner_reconciliation_report.py"
FIXTURE_PATH = ROOT / "fixtures" / "partner-reconciliation" / "synthetic_partners.json"
SQL_PATH = ROOT / "scripts" / "partner_reconciliation_catalog_inventory.sql"

SPEC = importlib.util.spec_from_file_location("partner_reconciliation_report", SCRIPT_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class PartnerReconciliationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dataset = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
        cls.report = MODULE.build_report(cls.dataset)
        cls.by_key = {item["candidate_key"]: item for item in cls.report["pairs"]}

    def _assert_library_and_cli_reject_without_report(self, dataset):
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(dataset)

        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "invalid-oracle.json"
            output_path = Path(temp_dir) / "report.json"
            input_path.write_text(json.dumps(dataset), encoding="utf-8")
            with redirect_stderr(io.StringIO()):
                exit_code = MODULE.main(["--input", str(input_path), "--output", str(output_path)])
            self.assertEqual(2, exit_code)
            self.assertFalse(output_path.exists())

    def test_target_pairs_match_expected_fail_closed_classes(self):
        for expected in self.dataset["expected_pairs"]:
            actual = self.by_key[expected["candidate_key"]]
            self.assertEqual(expected["classification"], actual["classification"])

    def test_strong_match_still_selects_nothing_and_allows_nothing(self):
        result = self.by_key[MODULE.candidate_key_for("SYN-A-ONE", "SYN-A-TWO")]
        self.assertEqual("strong_identifier_match", result["classification"])
        self.assertIsNone(result["canonical_partner_id"])
        self.assertTrue(result["manual_review_required"])
        self.assertFalse(result["mutation_allowed"])
        self.assertFalse(result["claim_allowed"])
        self.assertFalse(result["official_partner_allowed"])

    def test_wrong_owner_overrides_exact_business_identifiers(self):
        result = self.by_key[MODULE.candidate_key_for("SYN-C-ONE", "SYN-C-TWO")]
        self.assertEqual("ownership_conflict", result["classification"])
        self.assertIn("owner_account_id", result["conflicting_fields"])
        self.assertIn("google_place_id", result["matched_fields"])

    def test_similar_name_businesses_remain_separate(self):
        result = self.by_key[MODULE.candidate_key_for("SYN-B-ONE", "SYN-B-TWO")]
        self.assertEqual("separate_businesses", result["classification"])
        self.assertIn("normalized_name", result["matched_fields"])
        self.assertEqual("keep_separate_and_block_automatic_reconciliation", result["next_action"])

    def test_shopping_source_cannot_become_partner(self):
        result = self.by_key[MODULE.candidate_key_for("SYN-D-PARTNER", "SYN-D-SOURCE")]
        self.assertEqual("non_partner_source", result["classification"])
        self.assertEqual(
            {
                result["left_record_id"]: result["left_record_kind"],
                result["right_record_id"]: result["right_record_kind"],
            },
            {
                "SYN-D-PARTNER": "partner_candidate",
                "SYN-D-SOURCE": "shopping_source",
            },
        )
        self.assertFalse(result["claim_allowed"])
        self.assertFalse(result["official_partner_allowed"])

    def test_partial_name_and_address_evidence_is_likely_only(self):
        result = self.by_key[MODULE.candidate_key_for("SYN-E-ONE", "SYN-E-TWO")]
        self.assertEqual("likely_match", result["classification"])
        self.assertIsNone(result["canonical_partner_id"])

    def test_reference_manifest_preserves_every_family_count_and_scout_lineage(self):
        records = {record["id"]: record for record in self.dataset["records"]}
        for result in self.report["pairs"]:
            for record_id in (result["left_record_id"], result["right_record_id"]):
                manifest = result["reference_preservation_manifest"][record_id]
                self.assertEqual({"family_counts", "scout_links"}, set(manifest))
                self.assertEqual(set(MODULE.CHILD_REFERENCE_FAMILIES), set(manifest["family_counts"]))
                self.assertEqual(
                    records[record_id]["child_reference_counts"],
                    manifest["family_counts"],
                )
                expected_links = sorted(
                    records[record_id]["scout_link_lineage"],
                    key=lambda link: link["scout_lead_id"],
                )
                self.assertEqual(len(expected_links), len(manifest["scout_links"]))
                for expected_link, actual_link in zip(expected_links, manifest["scout_links"], strict=True):
                    bound_link = {**expected_link, "original_partner_record_id": record_id}
                    canonical = json.dumps(bound_link, sort_keys=True, separators=(",", ":")).encode("utf-8")
                    self.assertEqual(expected_link, {key: actual_link[key] for key in MODULE.SCOUT_LINK_KEYS})
                    self.assertEqual(record_id, actual_link["original_partner_record_id"])
                    self.assertEqual(hashlib.sha256(canonical).hexdigest(), actual_link["lineage_sha256"])

    def test_report_is_byte_stable_and_sorted(self):
        first = json.dumps(MODULE.build_report(self.dataset), indent=2, sort_keys=True) + "\n"
        second = json.dumps(MODULE.build_report(copy.deepcopy(self.dataset)), indent=2, sort_keys=True) + "\n"
        self.assertEqual(first, second)
        keys = [item["candidate_key"] for item in self.report["pairs"]]
        self.assertEqual(keys, sorted(keys))

    def test_report_is_bound_to_exact_reporter_source_revision(self):
        expected = "sha256:" + hashlib.sha256(SCRIPT_PATH.read_bytes()).hexdigest()
        self.assertEqual(expected, self.report["generator_revision"])
        self.assertRegex(self.report["generator_revision"], r"^sha256:[0-9a-f]{64}$")

    def test_report_contains_no_raw_contact_identifiers(self):
        serialized = json.dumps(self.report, sort_keys=True)
        for record in self.dataset["records"]:
            for field in ("phone", "email", "website", "instagram", "google_place_id", "address"):
                value = str(record.get(field, ""))
                if value:
                    self.assertNotIn(value, serialized)

    def test_non_synthetic_and_real_looking_inputs_are_rejected(self):
        non_synthetic = copy.deepcopy(self.dataset)
        non_synthetic["synthetic"] = False
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(non_synthetic)

        mislabeled = copy.deepcopy(self.dataset)
        mislabeled["data_classification"] = "real"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(mislabeled)

        mutation_enabled = copy.deepcopy(self.dataset)
        mutation_enabled["mutation_mode"] = "enabled"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(mutation_enabled)

        real_email = copy.deepcopy(self.dataset)
        real_email["records"][0]["email"] = "person@example.com"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(real_email)

        real_domain = copy.deepcopy(self.dataset)
        real_domain["records"][0]["website"] = "https://example.com"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(real_domain)

        real_phone = copy.deepcopy(self.dataset)
        real_phone["records"][0]["phone"] = "+1 813-555-9999"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(real_phone)

        hostname_query_bypass = copy.deepcopy(self.dataset)
        hostname_query_bypass["records"][0]["website"] = "https://example.com?marker=.test"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(hostname_query_bypass)

        for malformed_url in (
            "https://evil.com\\good.test",
            "https://evil.com%5cgood.test",
            "https://[bad.test",
            "https://citrus-kitchen.test/person@example.com",
        ):
            malformed_domain = copy.deepcopy(self.dataset)
            malformed_domain["records"][0]["website"] = malformed_url
            with self.subTest(malformed_url=malformed_url), self.assertRaises(MODULE.InputRejected):
                MODULE.build_report(malformed_domain)

        for digit_bearing_path in (
            "https://fixture.test/8135559999",
            "https://fixture.test/813-555-9999",
            "https://fixture.test/account/813_555_9999",
        ):
            unsafe_path = copy.deepcopy(self.dataset)
            unsafe_path["records"][0]["website"] = digit_bearing_path
            with self.subTest(digit_bearing_path=digit_bearing_path), self.assertRaises(MODULE.InputRejected):
                MODULE.build_report(unsafe_path)

        for malformed_email in (
            "person@example.com@synthetic.test",
            "@synthetic.test",
            "a b@synthetic.test",
        ):
            invalid_email = copy.deepcopy(self.dataset)
            invalid_email["records"][0]["email"] = malformed_email
            with self.subTest(malformed_email=malformed_email), self.assertRaises(MODULE.InputRejected):
                MODULE.build_report(invalid_email)

    def test_duplicate_ids_and_incomplete_reference_inventory_are_rejected(self):
        duplicate = copy.deepcopy(self.dataset)
        duplicate["records"][1]["id"] = duplicate["records"][0]["id"]
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(duplicate)

        missing_family = copy.deepcopy(self.dataset)
        del missing_family["records"][0]["child_reference_counts"]["media"]
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(missing_family)

    def test_scout_lineage_is_strict_counted_and_uniquely_linked(self):
        count_mismatch = copy.deepcopy(self.dataset)
        count_mismatch["records"][0]["child_reference_counts"]["scout_links"] = 2
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(count_mismatch)

        undeclared_provenance = copy.deepcopy(self.dataset)
        undeclared_provenance["records"][0]["scout_link_lineage"][0]["email"] = "person@example.com"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(undeclared_provenance)

        unsafe_source_detail = copy.deepcopy(self.dataset)
        unsafe_source_detail["records"][0]["scout_link_lineage"][0]["source_detail"] = "person@example.com"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(unsafe_source_detail)

        invalid_timestamp = copy.deepcopy(self.dataset)
        invalid_timestamp["records"][0]["scout_link_lineage"][0]["updated_at"] = "2099-01-32T00:00:00Z"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(invalid_timestamp)

        duplicate_link = copy.deepcopy(self.dataset)
        duplicate_link["records"][2]["scout_link_lineage"][0]["scout_lead_id"] = (
            duplicate_link["records"][0]["scout_link_lineage"][0]["scout_lead_id"]
        )
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(duplicate_link)

    def test_scout_timestamps_use_reserved_synthetic_window_and_order(self):
        inclusive_boundaries = copy.deepcopy(self.dataset)
        boundary_link = inclusive_boundaries["records"][0]["scout_link_lineage"][0]
        boundary_link["created_at"] = "2099-01-01T00:00:00Z"
        boundary_link["updated_at"] = "2099-01-31T23:59:59Z"
        self.assertIsInstance(MODULE.build_report(inclusive_boundaries), dict)

        for out_of_window in (
            "2026-08-19T12:34:56Z",
            "2098-12-31T23:59:59Z",
            "2099-02-01T00:00:00Z",
        ):
            invalid = copy.deepcopy(self.dataset)
            link = invalid["records"][0]["scout_link_lineage"][0]
            link["created_at"] = out_of_window
            link["updated_at"] = out_of_window
            with self.subTest(out_of_window=out_of_window), self.assertRaises(MODULE.InputRejected):
                MODULE.build_report(invalid)

        reversed_times = copy.deepcopy(self.dataset)
        reversed_link = reversed_times["records"][0]["scout_link_lineage"][0]
        reversed_link["created_at"] = "2099-01-31T23:59:59Z"
        reversed_link["updated_at"] = "2099-01-01T00:00:00Z"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(reversed_times)

    def test_pii_shaped_record_ids_are_rejected_before_report_emission(self):
        for record_id in ("SYN-8135559999", "SYN-813-555-9999"):
            invalid = copy.deepcopy(self.dataset)
            invalid["records"][0]["id"] = record_id
            with self.subTest(record_id=record_id), self.assertRaises(MODULE.InputRejected):
                MODULE.build_report(invalid)

    def test_unknown_root_record_and_expected_pair_fields_are_rejected(self):
        unknown_root = copy.deepcopy(self.dataset)
        unknown_root["undeclared"] = True
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(unknown_root)

        unknown_record = copy.deepcopy(self.dataset)
        unknown_record["records"][0]["undeclared"] = True
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(unknown_record)

        unknown_expected = copy.deepcopy(self.dataset)
        unknown_expected["expected_pairs"][0]["undeclared"] = True
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(unknown_expected)

    def test_expected_pairs_are_validated_for_target_class_and_uniqueness(self):
        unknown_target = copy.deepcopy(self.dataset)
        unknown_target["expected_pairs"][0]["candidate_key"] = "SYN-PAIR|1:X|1:Y"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(unknown_target)

        invalid_class = copy.deepcopy(self.dataset)
        invalid_class["expected_pairs"][0]["classification"] = "auto_merge"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(invalid_class)

        duplicate = copy.deepcopy(self.dataset)
        duplicate["expected_pairs"].append(copy.deepcopy(duplicate["expected_pairs"][0]))
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(duplicate)

        unhashable_class = copy.deepcopy(self.dataset)
        unhashable_class["expected_pairs"][0]["classification"] = {}
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(unhashable_class)

        unhashable_kind = copy.deepcopy(self.dataset)
        unhashable_kind["records"][0]["record_kind"] = []
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(unhashable_kind)

        nested_scalar = copy.deepcopy(self.dataset)
        nested_scalar["records"][0]["address"] = {
            "marker": "Example",
            "real_email": "person@example.com",
        }
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(nested_scalar)

        hidden_phone_pii = copy.deepcopy(self.dataset)
        hidden_phone_pii["records"][0]["phone"] = "person@example.com +1 813-555-0101"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(hidden_phone_pii)

        hidden_address_pii = copy.deepcopy(self.dataset)
        hidden_address_pii["records"][0]["address"] = "101 Example Avenue person@example.com, Tampa, FL"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(hidden_address_pii)

        hidden_name_pii = copy.deepcopy(self.dataset)
        hidden_name_pii["records"][0]["name"] = "Synthetic Citrus person@example.com"
        with self.assertRaises(MODULE.InputRejected):
            MODULE.build_report(hidden_name_pii)

    def test_expected_pairs_are_an_enforced_oracle_in_library_and_cli(self):
        contradicted = copy.deepcopy(self.dataset)
        contradicted["expected_pairs"][0]["classification"] = "likely_match"
        self._assert_library_and_cli_reject_without_report(contradicted)

    def test_oracle_rejects_a_deleted_pair_in_library_and_cli(self):
        incomplete = copy.deepcopy(self.dataset)
        del incomplete["expected_pairs"][0]
        self._assert_library_and_cli_reject_without_report(incomplete)

    def test_oracle_rejects_an_unknown_extra_pair_in_library_and_cli(self):
        extra = copy.deepcopy(self.dataset)
        extra["expected_pairs"].append(
            {
                "candidate_key": "SYN-PAIR|13:SYN-UNKNOWN-A|13:SYN-UNKNOWN-B",
                "classification": "insufficient_evidence",
            }
        )
        self._assert_library_and_cli_reject_without_report(extra)

    def test_new_record_requires_every_new_pair_expectation_in_library_and_cli(self):
        incomplete = copy.deepcopy(self.dataset)
        new_record = copy.deepcopy(incomplete["records"][8])
        new_record["id"] = "SYN-F-ONE"
        new_record["name"] = "Synthetic Future Pantry"
        new_record["address"] = "601 Example Future Way, Tampa, FL"
        new_record["owner_account_id"] = "SYN-OWNER-FUTURE"
        new_record["child_reference_counts"] = {
            family: 0 for family in MODULE.CHILD_REFERENCE_FAMILIES
        }
        new_record["scout_link_lineage"] = []
        incomplete["records"].append(new_record)
        incomplete["expected_pairs"].append(
            {
                "candidate_key": MODULE.candidate_key_for("SYN-D-SOURCE", "SYN-F-ONE"),
                "classification": "non_partner_source",
            }
        )
        self._assert_library_and_cli_reject_without_report(incomplete)

    def test_classify_pair_revalidates_records_at_the_entry_point(self):
        left = copy.deepcopy(self.dataset["records"][0])
        right = copy.deepcopy(self.dataset["records"][1])
        left["synthetic"] = False
        with self.assertRaises(MODULE.InputRejected):
            MODULE.classify_pair(left, right)

        left = copy.deepcopy(self.dataset["records"][0])
        left["undeclared"] = True
        with self.assertRaises(MODULE.InputRejected):
            MODULE.classify_pair(left, right)

    def test_email_is_strong_only_with_provenance_on_both_records(self):
        left = copy.deepcopy(self.dataset["records"][8])
        right = copy.deepcopy(self.dataset["records"][9])
        for record in (left, right):
            record["website"] = "https://sunrise-pantry.test"
            record["email"] = "owner@sunrise-pantry.test"
            record["email_provenance"] = "unverified"

        unverified = MODULE.classify_pair(left, right)
        self.assertEqual("likely_match", unverified["classification"])
        self.assertIn("email_unverified", unverified["matched_fields"])
        self.assertNotIn("email", unverified["matched_fields"])

        left["email_provenance"] = "owner_confirmed"
        right["email_provenance"] = "authorized_business_contact"
        verified = MODULE.classify_pair(left, right)
        self.assertEqual("strong_identifier_match", verified["classification"])
        self.assertIn("email", verified["matched_fields"])

    def test_candidate_key_is_order_independent_and_delimiter_collision_safe(self):
        first = MODULE.candidate_key_for("SYN-A--B", "SYN-C")
        reverse = MODULE.candidate_key_for("SYN-C", "SYN-A--B")
        ambiguous_under_old_join = MODULE.candidate_key_for("SYN-A", "SYN-B--C")
        self.assertEqual(first, reverse)
        self.assertNotEqual(first, ambiguous_under_old_join)

    def test_name_address_branch_preserves_matching_identifier_evidence(self):
        left = copy.deepcopy(self.dataset["records"][8])
        right = copy.deepcopy(self.dataset["records"][9])
        left["website"] = "https://sunrise-pantry.test"
        right["website"] = "https://www.sunrise-pantry.test/menu"
        result = MODULE.classify_pair(left, right)
        self.assertEqual("likely_match", result["classification"])
        self.assertIn("domain", result["matched_fields"])
        self.assertIn("normalized_name", result["matched_fields"])
        self.assertIn("normalized_address", result["matched_fields"])

    def test_name_address_only_owner_conflict_has_an_accurate_reason(self):
        left = copy.deepcopy(self.dataset["records"][8])
        right = copy.deepcopy(self.dataset["records"][9])
        right["owner_account_id"] = "SYN-OWNER-SUNRISE-B"
        result = MODULE.classify_pair(left, right)
        self.assertEqual("ownership_conflict", result["classification"])
        self.assertIn("Normalized name and address", result["reason"])
        self.assertNotIn("strong identifier matches", result["reason"])
        self.assertIn("normalized_name", result["matched_fields"])
        self.assertIn("normalized_address", result["matched_fields"])

    def test_unverified_email_cannot_hide_a_conflicting_owner(self):
        left = copy.deepcopy(self.dataset["records"][8])
        right = copy.deepcopy(self.dataset["records"][9])
        left["name"] = "Synthetic Alpha"
        right["name"] = "Synthetic Omega"
        left["address"] = "101 Example Alpha Way, Tampa, FL"
        right["address"] = "202 Example Omega Way, Tampa, FL"
        left["email"] = "shared@identity.test"
        right["email"] = "shared@identity.test"
        left["email_provenance"] = "unverified"
        right["email_provenance"] = "unverified"
        right["owner_account_id"] = "SYN-OWNER-OMEGA"

        result = MODULE.classify_pair(left, right)
        self.assertEqual("ownership_conflict", result["classification"])
        self.assertIn("email_unverified", result["matched_fields"])
        self.assertIn("owner_account_id", result["conflicting_fields"])
        self.assertIn("unverified email", result["reason"])

    def test_rejection_does_not_echo_an_unvalidated_record_id(self):
        invalid = copy.deepcopy(self.dataset)
        invalid["records"][0]["id"] = "person@example.com"
        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "invalid.json"
            input_path.write_text(json.dumps(invalid), encoding="utf-8")
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                exit_code = MODULE.main(["--input", str(input_path)])
            self.assertNotEqual(0, exit_code)
            self.assertNotIn("person@example.com", stderr.getvalue())

    def test_cli_rejects_duplicate_json_keys_before_schema_validation(self):
        raw = FIXTURE_PATH.read_text(encoding="utf-8")
        duplicate = raw.replace(
            '"email": "hello@citrus-kitchen.test",',
            '"email": "person@example.com",\n      "email": "hello@citrus-kitchen.test",',
            1,
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "duplicate.json"
            output_path = Path(temp_dir) / "report.json"
            input_path.write_text(duplicate, encoding="utf-8")
            with redirect_stderr(io.StringIO()):
                exit_code = MODULE.main(["--input", str(input_path), "--output", str(output_path)])
            self.assertNotEqual(0, exit_code)
            self.assertFalse(output_path.exists())

    def test_exact_name_and_address_do_not_override_multiple_strong_conflicts(self):
        left = copy.deepcopy(self.dataset["records"][0])
        right = copy.deepcopy(self.dataset["records"][0])
        right["id"] = "SYN-A-CONFLICT"
        right["child_reference_counts"]["scout_links"] = 0
        right["scout_link_lineage"] = []
        right["google_place_id"] = "SYN-PLACE-OTHER"
        right["website"] = "https://other-kitchen.test"
        right["phone"] = "813-555-0110"
        right["email"] = "owner@other-kitchen.test"
        right["email_provenance"] = "owner_confirmed"
        right["instagram"] = "synthetic_other_kitchen"

        result = MODULE.classify_pair(left, right)
        self.assertEqual("separate_businesses", result["classification"])
        for field in ("google_place_id", "domain", "phone", "email", "instagram"):
            self.assertIn(field, result["conflicting_fields"])

    def test_separate_businesses_preserves_real_matching_evidence(self):
        left = copy.deepcopy(self.dataset["records"][2])
        right = copy.deepcopy(self.dataset["records"][3])
        right["phone"] = left["phone"]
        right["owner_account_id"] = left["owner_account_id"]

        result = MODULE.classify_pair(left, right)
        self.assertEqual("separate_businesses", result["classification"])
        self.assertIn("phone", result["matched_fields"])
        self.assertIn("normalized_name", result["matched_fields"])
        for field in ("google_place_id", "domain", "email", "instagram", "normalized_address"):
            self.assertIn(field, result["conflicting_fields"])

    def test_conflicting_place_ids_override_composite_secondary_match(self):
        dataset = copy.deepcopy(self.dataset)
        left = dataset["records"][0]
        right = dataset["records"][1]
        right["google_place_id"] = "SYN-PLACE-CITRUS-CONFLICT"
        result = MODULE.classify_pair(left, right)
        self.assertEqual("ownership_conflict", result["classification"])
        self.assertIn("identity_contradiction", result["conflicting_fields"])

    def test_place_match_cannot_override_three_secondary_conflicts(self):
        left = copy.deepcopy(self.dataset["records"][0])
        right = copy.deepcopy(self.dataset["records"][0])
        right["id"] = "SYN-A-CONFLICT"
        right["child_reference_counts"]["scout_links"] = 0
        right["scout_link_lineage"] = []
        right["website"] = "https://other-kitchen.test"
        right["phone"] = "813-555-0110"
        right["email"] = "owner@other-kitchen.test"
        right["instagram"] = "synthetic_other_kitchen"

        result = MODULE.classify_pair(left, right)
        self.assertEqual("ownership_conflict", result["classification"])
        self.assertIn("google_place_id", result["matched_fields"])
        self.assertIn("identity_contradiction", result["conflicting_fields"])

        left["address"] = ""
        right["address"] = ""
        missing_address = MODULE.classify_pair(left, right)
        self.assertEqual("ownership_conflict", missing_address["classification"])
        self.assertIn("identity_contradiction", missing_address["conflicting_fields"])

    def test_composite_strong_match_preserves_qualifying_context(self):
        similar_left = copy.deepcopy(self.dataset["records"][0])
        similar_right = copy.deepcopy(self.dataset["records"][1])
        similar_left["google_place_id"] = ""
        similar_right["google_place_id"] = ""
        similar = MODULE.classify_pair(similar_left, similar_right)
        self.assertEqual("strong_identifier_match", similar["classification"])
        self.assertIn("normalized_name", similar["matched_fields"])

        address_left = copy.deepcopy(self.dataset["records"][8])
        address_right = copy.deepcopy(self.dataset["records"][9])
        address_left["name"] = "Synthetic Alpha Kitchen"
        address_right["name"] = "Synthetic Omega Fitness"
        for record in (address_left, address_right):
            record["website"] = "https://shared-context.test"
            record["phone"] = "813-555-0111"
        address = MODULE.classify_pair(address_left, address_right)
        self.assertEqual("strong_identifier_match", address["classification"])
        self.assertIn("normalized_address", address["matched_fields"])

    def test_shared_synthetic_marker_does_not_inflate_name_similarity(self):
        left = copy.deepcopy(self.dataset["records"][8])
        right = copy.deepcopy(self.dataset["records"][9])
        left["name"] = "Synthetic A"
        right["name"] = "Synthetic B"
        left["address"] = "101 Example Alpha Way, Tampa, FL"
        right["address"] = "202 Example Bravo Way, Tampa, FL"
        for record in (left, right):
            record["website"] = "https://shared-marker.test"
            record["phone"] = "813-555-0111"

        result = MODULE.classify_pair(left, right)
        self.assertEqual("likely_match", result["classification"])
        self.assertNotIn("normalized_name", result["matched_fields"])

    def test_synthetic_name_payload_rejects_empty_or_repeated_fixture_markers(self):
        for left_name, right_name in (
            ("Synthetic --", "Synthetic .."),
            ("Synthetic Synthetic A", "Synthetic Synthetic B"),
        ):
            dataset = copy.deepcopy(self.dataset)
            for record_id, name, address in (
                ("SYN-X-ONE", left_name, "601 Example Alpha Way, Tampa, FL"),
                ("SYN-X-TWO", right_name, "602 Example Bravo Way, Tampa, FL"),
            ):
                record = copy.deepcopy(self.dataset["records"][8])
                record["id"] = record_id
                record["name"] = name
                record["address"] = address
                record["website"] = "https://shared-marker.test"
                record["phone"] = "813-555-0111"
                record["owner_account_id"] = "SYN-OWNER-MARKER"
                record["child_reference_counts"] = {
                    family: 0 for family in MODULE.CHILD_REFERENCE_FAMILIES
                }
                record["scout_link_lineage"] = []
                dataset["records"].append(record)

            with self.subTest(left_name=left_name, right_name=right_name), self.assertRaises(
                MODULE.InputRejected
            ):
                # The new records are intentionally absent from expected_pairs. This
                # proves validation rejects the bad payload before a false strong
                # classification can be emitted, rather than relying on the oracle.
                MODULE.build_report(dataset)

    def test_pii_shaped_digit_run_is_rejected_from_synthetic_name_payload(self):
        dataset = copy.deepcopy(self.dataset)
        record = copy.deepcopy(self.dataset["records"][8])
        record["id"] = "SYN-X-PII"
        record["name"] = "Synthetic 8135559999"
        record["address"] = "603 Example Charlie Way, Tampa, FL"
        record["child_reference_counts"] = {
            family: 0 for family in MODULE.CHILD_REFERENCE_FAMILIES
        }
        record["scout_link_lineage"] = []
        dataset["records"].append(record)

        with self.assertRaises(MODULE.InputRejected):
            # This record is not covered by expected_pairs, so rejection is the
            # synthetic-input boundary itself rather than an oracle mismatch.
            MODULE.build_report(dataset)

    def test_invalid_cli_input_does_not_create_output(self):
        invalid = copy.deepcopy(self.dataset)
        invalid["data_classification"] = "real"
        invalid["synthetic"] = False
        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "invalid.json"
            output_path = Path(temp_dir) / "report.json"
            input_path.write_text(json.dumps(invalid), encoding="utf-8")
            with redirect_stderr(io.StringIO()):
                exit_code = MODULE.main(["--input", str(input_path), "--output", str(output_path)])
            self.assertNotEqual(0, exit_code)
            self.assertFalse(output_path.exists())

    def test_reporter_has_no_database_network_or_subprocess_import(self):
        tree = ast.parse(SCRIPT_PATH.read_text(encoding="utf-8"))
        imports = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imports.update(alias.name.split(".", 1)[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imports.add(node.module.split(".", 1)[0])
        forbidden = {"requests", "httpx", "urllib3", "socket", "subprocess", "psycopg", "psycopg2", "sqlalchemy", "supabase"}
        self.assertFalse(imports & forbidden)

    def test_catalog_sql_is_static_read_only_metadata(self):
        sql = SQL_PATH.read_text(encoding="utf-8")
        self.assertRegex(sql, r"(?is)\bBEGIN\s+TRANSACTION\s+READ\s+ONLY\b")
        self.assertRegex(sql, r"(?is)\bROLLBACK\s*;")
        self.assertNotIn("pg_get_functiondef", sql.lower())
        self.assertRegex(sql, r"(?is)pg_catalog\.pg_get_indexdef\s*\(\s*ind\.indexrelid\s*,\s*0\s*,\s*true\s*\)")
        self.assertRegex(sql, r"(?is)pg_catalog\.pg_get_expr\s*\(\s*ind\.indexprs\s*,\s*ind\.indrelid")
        self.assertRegex(sql, r"(?is)pg_catalog\.pg_get_expr\s*\(\s*ind\.indpred\s*,\s*ind\.indrelid")
        self.assertNotRegex(sql, r"(?is)\b(?:from|join)\s+public\.")

        constraint_inventory = sql.split("-- Constraints containing", 1)[1].split("-- Index metadata", 1)[0]
        self.assertIn("array_agg(att.attname ORDER BY key.ord)", constraint_inventory)
        self.assertRegex(constraint_inventory, r"(?is)\bAND\s+EXISTS\s*\(")
        self.assertRegex(constraint_inventory, r"(?is)identity_att\.attname\s+IN\s*\(")
        self.assertNotRegex(constraint_inventory, r"(?is)\bAND\s+att\.attname\s+IN\s*\(")
        self.assertIn("referenced_ns.nspname AS referenced_schema", constraint_inventory)
        self.assertIn("referenced_rel.relname AS referenced_table", constraint_inventory)
        self.assertRegex(
            constraint_inventory,
            r"(?is)referenced_rel\.oid\s*=\s*con\.confrelid",
        )
        self.assertRegex(
            constraint_inventory,
            r"(?is)unnest\s*\(\s*con\.confkey\s*\)\s+WITH\s+ORDINALITY\s+AS\s+referenced_key",
        )
        self.assertRegex(
            constraint_inventory,
            r"(?is)referenced_key\.ord\s*=\s*key\.ord",
        )
        self.assertRegex(
            constraint_inventory,
            r"(?is)array_agg\s*\(\s*referenced_att\.attname\s+ORDER\s+BY\s+referenced_key\.ord\s*\)"
            r"\s*FILTER\s*\(\s*WHERE\s+con\.contype\s*=\s*'f'\s*\)\s+AS\s+referenced_columns",
        )
        self.assertIn("con.confupdtype", constraint_inventory)
        self.assertIn("con.confdeltype", constraint_inventory)
        self.assertIn("END AS on_update", constraint_inventory)
        self.assertIn("END AS on_delete", constraint_inventory)

        without_comments = re.sub(r"--[^\n]*", "", sql)
        without_strings = re.sub(r"'(?:''|[^'])*'", "''", without_comments)
        self.assertNotRegex(
            without_strings,
            r"(?is)\b(?:insert|update|delete|merge|truncate|alter|create|drop|grant|revoke|copy|call|do)\b",
        )


if __name__ == "__main__":
    unittest.main()
