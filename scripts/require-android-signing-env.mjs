const required = [
  "HEHA_ANDROID_KEYSTORE_PATH",
  "HEHA_ANDROID_KEYSTORE_PASSWORD",
  "HEHA_ANDROID_KEY_ALIAS",
  "HEHA_ANDROID_KEY_PASSWORD",
];

const missing = required.filter((name) => !process.env[name]);
if (missing.length) {
  console.error(`Refusing Android release: missing ${missing.join(", ")}`);
  process.exit(1);
}

console.log("Android release signing environment is present.");
