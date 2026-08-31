import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function text(path) {
  return readFile(new URL(`../../${path}`, import.meta.url), "utf8");
}

test("native identifiers and Android SDK/version values match release candidate", async () => {
  const [capacitor, androidApp, androidVariables] = await Promise.all([
    text("capacitor.config.ts"),
    text("android/app/build.gradle"),
    text("android/variables.gradle"),
  ]);
  assert.match(capacitor, /appId: "online\.heha\.swipe"/);
  assert.match(androidApp, /applicationId "online\.heha\.swipe"/);
  assert.match(androidApp, /versionCode 1/);
  assert.match(androidApp, /versionName "0\.1\.0"/);
  assert.match(androidVariables, /minSdkVersion = 24/);
  assert.match(androidVariables, /compileSdkVersion = 36/);
  assert.match(androidVariables, /targetSdkVersion = 36/);
});

test("iOS is iPhone-only portrait at version 0.1.0 build 1", async () => {
  const [project, info] = await Promise.all([
    text("ios/App/App.xcodeproj/project.pbxproj"),
    text("ios/App/App/Info.plist"),
  ]);
  assert.match(project, /MARKETING_VERSION = 0\.1\.0;/);
  assert.match(project, /CURRENT_PROJECT_VERSION = 1;/);
  assert.match(project, /TARGETED_DEVICE_FAMILY = 1;/);
  assert.match(project, /PRODUCT_BUNDLE_IDENTIFIER = online\.heha\.swipe;/);
  assert.match(info, /UIInterfaceOrientationPortrait/);
  assert.doesNotMatch(info, /UIInterfaceOrientationLandscape/);
  assert.doesNotMatch(info, /UISupportedInterfaceOrientations~ipad/);
});

test("Android release signing fails closed on missing secret environment", async () => {
  const gradle = await text("android/app/build.gradle");
  assert.match(gradle, /Refusing unsigned HEHA Swipe release/);
  for (const name of [
    "HEHA_ANDROID_KEYSTORE_PATH",
    "HEHA_ANDROID_KEYSTORE_PASSWORD",
    "HEHA_ANDROID_KEY_ALIAS",
    "HEHA_ANDROID_KEY_PASSWORD",
  ]) assert.match(gradle, new RegExp(name));
});

test("Android disables backups and limits FileProvider sharing to app cache", async () => {
  const [manifest, filePaths] = await Promise.all([
    text("android/app/src/main/AndroidManifest.xml"),
    text("android/app/src/main/res/xml/file_paths.xml"),
  ]);
  assert.match(manifest, /android:allowBackup="false"/);
  assert.doesNotMatch(manifest, /android:allowBackup="true"/);
  assert.match(filePaths, /<cache-path name="shared_cache" path="\."\s*\/>/);
  assert.doesNotMatch(filePaths, /<(?:external|external-cache|external-files|files|root)-path\b/);
});

test("iOS privacy manifest is bundled and truthfully declares linked app data without tracking", async () => {
  const [project, privacy] = await Promise.all([
    text("ios/App/App.xcodeproj/project.pbxproj"),
    text("ios/App/App/PrivacyInfo.xcprivacy"),
  ]);
  assert.match(project, /PrivacyInfo\.xcprivacy in Resources/);
  assert.match(project, /path = PrivacyInfo\.xcprivacy;/);
  assert.match(privacy, /<key>NSPrivacyTracking<\/key>\s*<false\/>/);
  assert.match(privacy, /<key>NSPrivacyTrackingDomains<\/key>\s*<array\/>/);
  assert.match(privacy, /<key>NSPrivacyAccessedAPITypes<\/key>\s*<array\/>/);
  for (const dataType of [
    "Name",
    "EmailAddress",
    "PhoneNumber",
    "PhysicalAddress",
    "UserID",
    "ProductInteraction",
  ]) {
    assert.match(privacy, new RegExp(`NSPrivacyCollectedDataType${dataType}`));
  }
  assert.match(privacy, /NSPrivacyCollectedDataTypePurposeAppFunctionality/);
  assert.doesNotMatch(privacy, /<key>NSPrivacyCollectedDataTypeTracking<\/key>\s*<true\/>/);
});
