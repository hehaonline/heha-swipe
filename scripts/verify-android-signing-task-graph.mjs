import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const androidDirectory = fileURLToPath(new URL("../android/", import.meta.url));
const signingNames = [
  "HEHA_ANDROID_KEYSTORE_PATH",
  "HEHA_ANDROID_KEYSTORE_PASSWORD",
  "HEHA_ANDROID_KEY_ALIAS",
  "HEHA_ANDROID_KEY_PASSWORD",
];
const unsignedEnvironment = { ...process.env };
for (const name of signingNames) delete unsignedEnvironment[name];

function runGradle(task) {
  return spawnSync(
    process.platform === "win32" ? "gradlew.bat" : "./gradlew",
    [task, "--dry-run", "--no-daemon", "--console=plain"],
    {
      cwd: androidDirectory,
      encoding: "utf8",
      env: unsignedEnvironment,
    },
  );
}

for (const task of ["assemble", "build"]) {
  const result = runGradle(task);
  const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
  if (result.status === 0 || !output.includes("Refusing unsigned HEHA Swipe release")) {
    process.stderr.write(output);
    throw new Error(`${task} did not fail closed on its resolved release task graph`);
  }
}

const debugResult = runGradle("assembleDebug");
if (debugResult.status !== 0) {
  process.stderr.write(`${debugResult.stdout ?? ""}\n${debugResult.stderr ?? ""}`);
  throw new Error("assembleDebug must remain available without release signing credentials");
}

console.log("Android release signing task-graph gate is fail-closed; debug remains usable.");
