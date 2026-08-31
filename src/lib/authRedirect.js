export const DEFAULT_PUBLIC_APP_URL = "https://hehaswipe.app";

export function canonicalPublicAppUrl(configuredUrl) {
  const candidate = typeof configuredUrl === "string" ? configuredUrl.trim() : "";

  try {
    const parsed = new URL(candidate || DEFAULT_PUBLIC_APP_URL);
    if (parsed.protocol !== "https:" || !parsed.hostname || parsed.username || parsed.password) {
      return DEFAULT_PUBLIC_APP_URL;
    }
    return parsed.origin;
  } catch {
    return DEFAULT_PUBLIC_APP_URL;
  }
}
