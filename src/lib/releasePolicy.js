import { Capacitor } from "@capacitor/core";

export const STORE_RELEASE_CHANNEL = "store";
const buildEnvironment = import.meta.env || {};

export function createReleasePolicy({ releaseChannel = "web", isNative = false } = {}) {
  const storeBuild = releaseChannel === STORE_RELEASE_CHANNEL || isNative === true;

  return Object.freeze({
    storeBuild,
    passwordAuth: true,
    socialAuth: !storeBuild,
    passwordlessAuth: !storeBuild,
    geolocation: !storeBuild,
    payments: !storeBuild,
    outboundWebhooks: !storeBuild,
    contactRequests: !storeBuild,
    instagram: !storeBuild,
    partnerSelfService: !storeBuild,
    internalAdmin: !storeBuild,
    superSwipe: !storeBuild,
    profileReset: !storeBuild,
  });
}

export const releasePolicy = createReleasePolicy({
  releaseChannel: buildEnvironment.VITE_RELEASE_CHANNEL || "web",
  isNative: Capacitor.isNativePlatform(),
});
