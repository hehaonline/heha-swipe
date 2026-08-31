const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ASSIGNMENT_ROLES = new Set(["operator", "authorized_signer"]);
const PRIVATE_PROFILE_STATUSES = new Set([
  "draft",
  "submitted",
  "pending",
  "missing_info",
  "approved",
  "live",
  "paused",
]);

function requiredUuid(value, field) {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new Error(`Invalid ${field}.`);
  }
  return value;
}

export function normalizePartnerOnboardingAssignments(value, actorId) {
  if (!value || typeof value !== "object" || Array.isArray(value)
      || value.projection_version !== "heha-partner-assignments-v1"
      || requiredUuid(value.authorized_actor_id, "authorized_actor_id") !== actorId
      || !Array.isArray(value.assignments)
      || value.assignments.length > 100) {
    throw new Error("Invalid partner assignment projection.");
  }

  const seen = new Set();
  const assignments = value.assignments.map((assignment) => {
    if (!assignment || typeof assignment !== "object" || Array.isArray(assignment)) {
      throw new Error("Invalid partner assignment.");
    }
    const partnerId = requiredUuid(assignment.partner_id, "assignment.partner_id");
    if (!ASSIGNMENT_ROLES.has(assignment.role)
        || typeof assignment.display_name !== "string"
        || !assignment.display_name.trim()
        || assignment.display_name.length > 500
        || !PRIVATE_PROFILE_STATUSES.has(assignment.private_profile_status)) {
      throw new Error("Invalid partner assignment fields.");
    }
    const uniqueKey = `${partnerId}:${assignment.role}`;
    if (seen.has(uniqueKey)) throw new Error("Duplicate partner assignment.");
    seen.add(uniqueKey);
    return {
      partner_id: partnerId,
      role: assignment.role,
      display_name: assignment.display_name.trim(),
      private_profile_status: assignment.private_profile_status,
    };
  });

  const sorted = [...assignments].sort((left, right) => (
    left.partner_id.localeCompare(right.partner_id) || left.role.localeCompare(right.role)
  ));
  if (assignments.some((assignment, index) => (
    assignment.partner_id !== sorted[index].partner_id || assignment.role !== sorted[index].role
  ))) {
    throw new Error("Partner assignments are not deterministically ordered.");
  }

  return {
    projection_version: "heha-partner-assignments-v1",
    authorized_actor_id: actorId,
    assignments,
  };
}

export function groupPartnerOnboardingAssignments(assignments) {
  const partners = new Map();
  for (const assignment of assignments) {
    const existing = partners.get(assignment.partner_id);
    if (existing) {
      if (existing.display_name !== assignment.display_name
          || existing.private_profile_status !== assignment.private_profile_status) {
        throw new Error("Partner assignment rows disagree.");
      }
      existing.roles.push(assignment.role);
      continue;
    }
    partners.set(assignment.partner_id, {
      partner_id: assignment.partner_id,
      display_name: assignment.display_name,
      private_profile_status: assignment.private_profile_status,
      roles: [assignment.role],
    });
  }
  return [...partners.values()];
}
