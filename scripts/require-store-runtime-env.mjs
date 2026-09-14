const PLACEHOLDER_PARTS = [
  "changeme",
  "example",
  "placeholder",
  "replace-me",
  "replace_me",
  "your-",
  "your_",
  "<",
  ">",
  "${",
];

function hasPlaceholder(value) {
  const normalized = value.toLowerCase();
  return PLACEHOLDER_PARTS.some((part) => normalized.includes(part));
}

function validateSupabaseUrl(rawValue) {
  const value = rawValue?.trim();
  if (!value) {
    return "is missing";
  }
  if (value !== rawValue || hasPlaceholder(value)) {
    return "is a placeholder or contains surrounding whitespace";
  }

  let url;
  try {
    url = new URL(value);
  } catch {
    return "must be a valid URL";
  }

  const hostname = url.hostname.toLowerCase();
  const unusableHost =
    !hostname.includes(".") ||
    hostname === "localhost" ||
    hostname === "127.0.0.1" ||
    hostname === "::1" ||
    hostname.endsWith(".local") ||
    hostname === "example.com" ||
    hostname.endsWith(".example");

  if (url.protocol !== "https:") {
    return "must use HTTPS";
  }
  if (url.username || url.password || unusableHost) {
    return "must identify a real public Supabase endpoint";
  }

  return null;
}

function decodeJwtPayload(value) {
  const parts = value.split(".");
  if (parts.length !== 3 || parts.some((part) => !/^[A-Za-z0-9_-]+$/.test(part))) {
    return null;
  }

  try {
    return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

function validateSupabaseAnonKey(rawValue) {
  const value = rawValue?.trim();
  if (!value) {
    return "is missing";
  }
  if (value !== rawValue || hasPlaceholder(value)) {
    return "is a placeholder or contains surrounding whitespace";
  }
  if (value.startsWith("sb_secret_")) {
    return "must not be a Supabase secret key";
  }

  const publishableKey = /^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(value);
  const jwtPayload = decodeJwtPayload(value);
  const legacyAnonKey = value.length >= 80 && jwtPayload?.role === "anon";

  if (!publishableKey && !legacyAnonKey) {
    return "must be a plausible Supabase publishable or legacy anon key";
  }

  return null;
}

const checks = [
  ["VITE_SUPABASE_URL", validateSupabaseUrl(process.env.VITE_SUPABASE_URL)],
  [
    "VITE_SUPABASE_ANON_KEY",
    validateSupabaseAnonKey(process.env.VITE_SUPABASE_ANON_KEY),
  ],
];

const failures = checks.filter(([, failure]) => failure);
if (failures.length) {
  for (const [name, failure] of failures) {
    console.error(`Refusing store release: ${name} ${failure}.`);
  }
  process.exit(1);
}

console.log("Store runtime environment is valid.");
