# Duplicate Compatibility Map

| Identifier/name | Evidence | Classification | Decision required |
|---|---|---|---|
| Ledger snapshot `analytics_triggers_for_partner_counters`: `20260602213920`, `20260602220224` | Two committed snapshot rows **[RP]**; current live status and SQL bodies **[U]** | Duplicate name, distinct versions; SQL equivalence unknown | Recover both bodies through authorized access and classify equivalent, corrective or superseded |
| Repo `20260626120000` forward + rollback | **[RP]** distinct hashes/content | Opposing behavior under one identifier | Remove rollback from executable canonical chain; archive with checksum |
| Repo `20260705000600` PM tasks + task routing | **[RP]** distinct hashes/content | Same function/trigger, different security posture | Canonicalize the final secured definition |
| Repo `20260705000900` view + queue worker | **[RP]** distinct unrelated SQL | Two migrations sharing one ID | Preserve both behaviors under unique canonical sections/versions |
| Repo `20260705001400` visibility + CTA restriction | **[RP]** distinct unrelated SQL | Two migrations sharing one ID | Preserve both behaviors under unique canonical sections/versions |
| Historical `20260705_scout_partner_pipeline.sql` | **[U]** no immutable commit/blob reference or checksum is included in PR A | Nonstandard short version and superseded aggregate claim is unverified | Add an exact commit/blob reference and checksum before classifying; never restore blindly |

## Architecture handling rules

1. Historical duplicate evidence is retained.
2. Executable rollback files do not belong in the future canonical chain.
3. Same-timestamp files require unique canonical treatment.
4. Ledger-only duplicate names remain unresolved until their SQL bodies are classified.
5. No duplicate may be silently treated as equivalent by filename or name alone.
