import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "online.heha.swipe",
  appName: "HEHA Swipe",
  webDir: "dist",
  bundledWebRuntime: false,
  server: {
    androidScheme: "https",
  },
};

export default config;
