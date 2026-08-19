from __future__ import annotations

import ast
import copy
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
        self.assertEqual("keep_separate_and_block_automatic_reconciliation", result["next_action"])

    def test_shopping_source_cannot_become_partner(self):
        result = self.by_key[MODULE.candidate_key_for("SYN-D-PARTNER", "SYN-D-SOURCE")]
        self.assertEqual("non_partner_source", result["classification"])
        self.assertFalse(result["claim_allowed"])
        self.assertFalse(result["official_partner_allowed"])

    def test_partial_name_and_address_evidence_is_likely_only(self):
        result = self.by_key[MODULE.candidate_key_for("SYN-E-ONE", "SYN-E-TWO")]
        self.assertEqual("likely_match", result["classification"])
        self.assertIsNone(result["canonical_partner_id"])

    def test_reference_manifest_preserves_every_family_and_count(self):
        records = {record["id"]: record for record in self.dataset["records"]}
        for result in self.report["pairs"]:
            self.assertEqual(set(MODULE.CHILD_REFERENCE_FAMILIES), set(result["reference_preservation_manifest"][result["left_record_id"]]))
            self.assertEqual(set(MODULE.CHILD_REFERENCE_FAMILIES), set(result["reference_preservation_manifest"][result["right_record_id"]]))
            for record_id in (result["left_record_id"], result["right_record_id"]):
                self.assertEqual(
                    records[record_id]["child_reference_counts"],
                    result["reference_preservation_manifest"][record_id],
                )

    def test_report_is_byte_stable_and_sorted(self):
        first = json.dumps(MODULE.build_report(self.dataset), indent=2, sort_keys=True) + "\n"
        second = json.dumps(MODULE.build_report(copy.deepcopy(self.dataset)), indent=2, sort_keys=True) + "\n"
        self.assertEqual(first, second)
        keys = [item["candidate_key"] for item in self.report["pairs"]]
        self.assertEqual(keys, sorted(keys))

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
        ):
            malformed_domain = copy.deepcopy(self.dataset)
            malformed_domain["records"][0]["website"] = malformed_url
            with self.subTest(malformed_url=malformed_url), self.assertRaises(MODULE.InputRejected):
                MODULE.build_report(malformed_domain)

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
        left["address"] = "101 Example Alpha Way"
        right["address"] = "202 Example Omega Way"
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

    def test_exact_name_and_address_do_not_override_multiple_strong_conflicts(self):
        left = copy.deepcopy(self.dataset["records"][0])
        right = copy.deepcopy(self.dataset["records"][0])
        right["id"] = "SYN-A-CONFLICT"
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

    def test_conflicting_place_ids_override_composite_secondary_match(self):
        dataset = copy.deepcopy(self.dataset)
        left = dataset["records"][0]
        right = dataset["records"][1]
        right["google_place_id"] = "SYN-PLACE-CITRUS-CONFLICT"
        result = MODULE.classify_pair(left, right)
        self.assertEqual("ownership_conflict", result["classification"])
        self.assertIn("identity_contradiction", result["conflicting_fields"])

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
        self.assertNotRegex(sql, r"(?is)\b(?:from|join)\s+public\.")

        without_comments = re.sub(r"--[^\n]*", "", sql)
        without_strings = re.sub(r"'(?:''|[^'])*'", "''", without_comments)
        self.assertNotRegex(
            without_strings,
            r"(?is)\b(?:insert|update|delete|merge|truncate|alter|create|drop|grant|revoke|copy|call|do)\b",
        )


if __name__ == "__main__":
    unittest.main()
