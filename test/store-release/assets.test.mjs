import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { deflateSync, inflateSync } from "node:zlib";
import {
  buildAssetOutputs,
  equivalentAssetBytes,
} from "../../scripts/generate-store-assets.mjs";

function pngMetadata(bytes) {
  assert.equal(bytes.subarray(1, 4).toString("ascii"), "PNG");
  assert.equal(bytes.subarray(12, 16).toString("ascii"), "IHDR");
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
    bitDepth: bytes[24],
    colorType: bytes[25],
  };
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const value of buffer) {
    crc ^= value;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBytes = Buffer.from(type, "ascii");
  const result = Buffer.alloc(12 + data.length);
  result.writeUInt32BE(data.length, 0);
  typeBytes.copy(result, 4);
  data.copy(result, 8);
  result.writeUInt32BE(crc32(Buffer.concat([typeBytes, data])), 8 + data.length);
  return result;
}

function recompressPng(bytes) {
  const signature = bytes.subarray(0, 8);
  const header = bytes.subarray(16, 29);
  let offset = 8;
  const imageData = [];
  while (offset + 12 <= bytes.length) {
    const length = bytes.readUInt32BE(offset);
    const type = bytes.toString("ascii", offset + 4, offset + 8);
    if (type === "IDAT") imageData.push(bytes.subarray(offset + 8, offset + 8 + length));
    offset += 12 + length;
    if (type === "IEND") break;
  }
  const raw = inflateSync(Buffer.concat(imageData));
  return Buffer.concat([
    signature,
    pngChunk("IHDR", header),
    pngChunk("IDAT", deflateSync(raw, { level: 0 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

test("asset generation is deterministic and tracked outputs are current", async () => {
  const first = buildAssetOutputs();
  const second = buildAssetOutputs();
  assert.deepEqual([...first.keys()], [...second.keys()]);
  for (const [path, firstBytes] of first) {
    const secondBytes = second.get(path);
    assert.ok(firstBytes.equals(secondBytes), path);
    const trackedBytes = await readFile(new URL(`../../${path}`, import.meta.url));
    assert.ok(equivalentAssetBytes(trackedBytes, firstBytes), `${path} is stale`);
  }
});

test("asset comparison accepts equivalent PNG pixels across zlib versions", () => {
  const original = buildAssetOutputs().get("public/icons/icon-192.png");
  const recompressed = recompressPng(original);
  assert.equal(original.equals(recompressed), false);
  assert.equal(equivalentAssetBytes(original, recompressed), true);

  const corrupted = Buffer.from(recompressed);
  corrupted[corrupted.length - 1] ^= 1;
  assert.equal(equivalentAssetBytes(original, corrupted), false);
});

test("standard and maskable icons are separate assets", () => {
  const outputs = buildAssetOutputs();
  assert.equal(
    outputs.get("public/icons/icon-512.png").equals(outputs.get("public/icons/icon-maskable-512.png")),
    false
  );
});

test("Apple app icons and the Google Play feature graphic are opaque RGB PNGs", () => {
  const outputs = buildAssetOutputs();
  const expected = new Map([
    ["store-assets/apple/app-icon-1024.png", [1024, 1024]],
    ["ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png", [1024, 1024]],
    ["store-assets/google-play/feature-graphic-1024x500.png", [1024, 500]],
  ]);

  for (const [path, [width, height]] of expected) {
    assert.deepEqual(pngMetadata(outputs.get(path)), { width, height, bitDepth: 8, colorType: 2 }, path);
  }

  assert.equal(pngMetadata(outputs.get("store-assets/google-play/icon-512.png")).colorType, 6);
});

test("Android adaptive foreground rasters use the 108dp density dimensions", () => {
  const outputs = buildAssetOutputs();
  const expectedSizes = { mdpi: 108, hdpi: 162, xhdpi: 216, xxhdpi: 324, xxxhdpi: 432 };

  for (const [density, size] of Object.entries(expectedSizes)) {
    const path = `android/app/src/main/res/mipmap-${density}/ic_launcher_foreground.png`;
    assert.deepEqual(
      pngMetadata(outputs.get(path)),
      { width: size, height: size, bitDepth: 8, colorType: 6 },
      path
    );
  }
});

test("all tracked Android and iOS splash images are HEHA-generated RGB outputs", () => {
  const outputs = buildAssetOutputs();
  const expected = new Map([
    ["android/app/src/main/res/drawable/splash.png", [480, 320]],
    ["android/app/src/main/res/drawable-land-mdpi/splash.png", [480, 320]],
    ["android/app/src/main/res/drawable-land-hdpi/splash.png", [800, 480]],
    ["android/app/src/main/res/drawable-land-xhdpi/splash.png", [1280, 720]],
    ["android/app/src/main/res/drawable-land-xxhdpi/splash.png", [1600, 960]],
    ["android/app/src/main/res/drawable-land-xxxhdpi/splash.png", [1920, 1280]],
    ["android/app/src/main/res/drawable-port-mdpi/splash.png", [320, 480]],
    ["android/app/src/main/res/drawable-port-hdpi/splash.png", [480, 800]],
    ["android/app/src/main/res/drawable-port-xhdpi/splash.png", [720, 1280]],
    ["android/app/src/main/res/drawable-port-xxhdpi/splash.png", [960, 1600]],
    ["android/app/src/main/res/drawable-port-xxxhdpi/splash.png", [1280, 1920]],
    ["ios/App/App/Assets.xcassets/Splash.imageset/splash-2732x2732.png", [2732, 2732]],
    ["ios/App/App/Assets.xcassets/Splash.imageset/splash-2732x2732-1.png", [2732, 2732]],
    ["ios/App/App/Assets.xcassets/Splash.imageset/splash-2732x2732-2.png", [2732, 2732]],
  ]);

  for (const [path, [width, height]] of expected) {
    assert.ok(outputs.has(path), `${path} is omitted from deterministic output validation`);
    assert.deepEqual(pngMetadata(outputs.get(path)), { width, height, bitDepth: 8, colorType: 2 }, path);
  }
});
