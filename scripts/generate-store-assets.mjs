import { deflateSync, inflateSync } from "node:zlib";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const ORANGE = [247, 120, 35, 255];
const GREEN = [17, 79, 53, 255];
const CREAM = [250, 246, 237, 255];
const TRANSPARENT = [0, 0, 0, 0];

const GLYPHS = {
  A: ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
  C: ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
  D: ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
  E: ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
  H: ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
  I: ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
  L: ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
  O: ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
  P: ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
  R: ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
  S: ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
  T: ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
  V: ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
  W: ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
  Y: ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
};

function canvas(width, height, color = TRANSPARENT) {
  const pixels = Buffer.alloc(width * height * 4);
  for (let offset = 0; offset < pixels.length; offset += 4) {
    pixels.set(color, offset);
  }
  return { width, height, pixels };
}

function fillRect(image, x, y, width, height, color) {
  const left = Math.max(0, Math.round(x));
  const top = Math.max(0, Math.round(y));
  const right = Math.min(image.width, Math.round(x + width));
  const bottom = Math.min(image.height, Math.round(y + height));
  for (let py = top; py < bottom; py += 1) {
    for (let px = left; px < right; px += 1) {
      image.pixels.set(color, (py * image.width + px) * 4);
    }
  }
}

function fillCircle(image, cx, cy, radius, color) {
  const r2 = radius * radius;
  for (let y = Math.max(0, Math.floor(cy - radius)); y < Math.min(image.height, Math.ceil(cy + radius)); y += 1) {
    for (let x = Math.max(0, Math.floor(cx - radius)); x < Math.min(image.width, Math.ceil(cx + radius)); x += 1) {
      const dx = x + 0.5 - cx;
      const dy = y + 0.5 - cy;
      if (dx * dx + dy * dy <= r2) image.pixels.set(color, (y * image.width + x) * 4);
    }
  }
}

function drawH(image, x, y, size, color) {
  const stroke = Math.max(1, Math.round(size * 0.18));
  fillRect(image, x, y, stroke, size, color);
  fillRect(image, x + size - stroke, y, stroke, size, color);
  fillRect(image, x, y + size * 0.41, size, stroke, color);
}

function drawText(image, text, x, y, scale, color) {
  let cursor = x;
  for (const character of text) {
    if (character === " ") {
      cursor += scale * 4;
      continue;
    }
    const glyph = GLYPHS[character];
    if (!glyph) continue;
    glyph.forEach((row, rowIndex) => {
      [...row].forEach((pixel, columnIndex) => {
        if (pixel === "1") fillRect(image, cursor + columnIndex * scale, y + rowIndex * scale, scale, scale, color);
      });
    });
    cursor += scale * 6;
  }
}

function icon(size, { maskable = false, foreground = false } = {}) {
  const image = canvas(size, size, foreground ? TRANSPARENT : ORANGE);
  const center = size / 2;
  const disc = size * (maskable || foreground ? 0.29 : 0.34);
  fillCircle(image, center, center, disc, foreground ? GREEN : CREAM);
  const hSize = size * (maskable || foreground ? 0.30 : 0.36);
  drawH(image, center - hSize / 2, center - hSize / 2, hSize, foreground ? CREAM : GREEN);
  return image;
}

function featureGraphic() {
  const image = canvas(1024, 500, ORANGE);
  fillCircle(image, 200, 250, 135, CREAM);
  drawH(image, 128, 178, 144, GREEN);
  drawText(image, "HEHA", 400, 135, 18, GREEN);
  drawText(image, "SWIPE", 400, 300, 12, CREAM);
  return image;
}

function splash(width, height) {
  const image = canvas(width, height, CREAM);
  const unit = Math.min(width, height);
  const centerX = width / 2;
  const markY = height / 2 - unit * 0.1;
  const discRadius = unit * 0.2;
  const hSize = unit * 0.22;
  const wordScale = Math.max(2, Math.round(unit / 64));
  const subheadScale = Math.max(2, Math.round(unit / 91));

  fillCircle(image, centerX, markY, discRadius, ORANGE);
  drawH(image, centerX - hSize / 2, markY - hSize / 2, hSize, CREAM);
  drawText(image, "HEHA", centerX - wordScale * 11.5, markY + unit * 0.25, wordScale, GREEN);
  drawText(image, "SWIPE", centerX - subheadScale * 14.5, markY + unit * 0.38, subheadScale, ORANGE);
  return image;
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const value of buffer) {
    crc ^= value;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const typeBuffer = Buffer.from(type, "ascii");
  const result = Buffer.alloc(12 + data.length);
  result.writeUInt32BE(data.length, 0);
  typeBuffer.copy(result, 4);
  data.copy(result, 8);
  result.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])), 8 + data.length);
  return result;
}

function png(image, { rgb = false } = {}) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const header = Buffer.alloc(13);
  header.writeUInt32BE(image.width, 0);
  header.writeUInt32BE(image.height, 4);
  header[8] = 8;
  header[9] = rgb ? 2 : 6;
  const channels = rgb ? 3 : 4;
  const raw = Buffer.alloc((image.width * channels + 1) * image.height);
  for (let y = 0; y < image.height; y += 1) {
    const rowOffset = y * (image.width * channels + 1);
    raw[rowOffset] = 0;
    if (rgb) {
      for (let x = 0; x < image.width; x += 1) {
        const sourceOffset = (y * image.width + x) * 4;
        if (image.pixels[sourceOffset + 3] !== 255) {
          throw new Error("RGB PNG output cannot contain transparent pixels");
        }
        const destinationOffset = rowOffset + 1 + x * 3;
        raw[destinationOffset] = image.pixels[sourceOffset];
        raw[destinationOffset + 1] = image.pixels[sourceOffset + 1];
        raw[destinationOffset + 2] = image.pixels[sourceOffset + 2];
      }
    } else {
      image.pixels.copy(raw, rowOffset + 1, y * image.width * 4, (y + 1) * image.width * 4);
    }
  }
  return Buffer.concat([
    signature,
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function canonicalPngBytes(bytes) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (!Buffer.isBuffer(bytes) || bytes.length < signature.length || !bytes.subarray(0, 8).equals(signature)) {
    return null;
  }

  let offset = 8;
  let header = null;
  const imageData = [];
  let sawEnd = false;

  while (offset + 12 <= bytes.length) {
    const length = bytes.readUInt32BE(offset);
    const end = offset + 12 + length;
    if (end > bytes.length) return null;

    const type = bytes.toString("ascii", offset + 4, offset + 8);
    const data = bytes.subarray(offset + 8, offset + 8 + length);
    const expectedCrc = bytes.readUInt32BE(offset + 8 + length);
    const actualCrc = crc32(Buffer.concat([Buffer.from(type, "ascii"), data]));
    if (expectedCrc !== actualCrc || !["IHDR", "IDAT", "IEND"].includes(type)) return null;
    if (type === "IHDR") {
      if (header || offset !== 8) return null;
      header = data;
    }
    if (type === "IDAT") imageData.push(data);
    offset = end;
    if (type === "IEND") {
      sawEnd = true;
      break;
    }
  }

  if (!header || header.length !== 13 || imageData.length === 0 || !sawEnd || offset !== bytes.length) {
    return null;
  }

  try {
    return Buffer.concat([header, inflateSync(Buffer.concat(imageData))]);
  } catch {
    return null;
  }
}

export function equivalentAssetBytes(actual, expected) {
  if (actual.equals(expected)) return true;
  const actualPng = canonicalPngBytes(actual);
  const expectedPng = canonicalPngBytes(expected);
  return Boolean(actualPng && expectedPng && actualPng.equals(expectedPng));
}

function canonicalAssetBytes(bytes) {
  return canonicalPngBytes(bytes) || bytes;
}

export function buildAssetOutputs() {
  const outputs = new Map([
    ["public/icons/icon-192.png", png(icon(192))],
    ["public/icons/icon-512.png", png(icon(512))],
    ["public/icons/icon-maskable-192.png", png(icon(192, { maskable: true }))],
    ["public/icons/icon-maskable-512.png", png(icon(512, { maskable: true }))],
    ["public/icons/apple-touch-icon.png", png(icon(180), { rgb: true })],
    ["store-assets/apple/app-icon-1024.png", png(icon(1024), { rgb: true })],
    ["store-assets/google-play/icon-512.png", png(icon(512))],
    ["store-assets/google-play/feature-graphic-1024x500.png", png(featureGraphic(), { rgb: true })],
    ["ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png", png(icon(1024), { rgb: true })],
  ]);

  const androidSizes = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
  const androidForegroundSizes = { mdpi: 108, hdpi: 162, xhdpi: 216, xxhdpi: 324, xxxhdpi: 432 };
  for (const [density, size] of Object.entries(androidSizes)) {
    const folder = `android/app/src/main/res/mipmap-${density}`;
    outputs.set(`${folder}/ic_launcher.png`, png(icon(size)));
    outputs.set(`${folder}/ic_launcher_round.png`, png(icon(size)));
    outputs.set(
      `${folder}/ic_launcher_foreground.png`,
      png(icon(androidForegroundSizes[density], { foreground: true }))
    );
  }

  const androidSplashSizes = {
    "drawable/splash.png": [480, 320],
    "drawable-land-mdpi/splash.png": [480, 320],
    "drawable-land-hdpi/splash.png": [800, 480],
    "drawable-land-xhdpi/splash.png": [1280, 720],
    "drawable-land-xxhdpi/splash.png": [1600, 960],
    "drawable-land-xxxhdpi/splash.png": [1920, 1280],
    "drawable-port-mdpi/splash.png": [320, 480],
    "drawable-port-hdpi/splash.png": [480, 800],
    "drawable-port-xhdpi/splash.png": [720, 1280],
    "drawable-port-xxhdpi/splash.png": [960, 1600],
    "drawable-port-xxxhdpi/splash.png": [1280, 1920],
  };
  for (const [relativePath, [width, height]] of Object.entries(androidSplashSizes)) {
    outputs.set(`android/app/src/main/res/${relativePath}`, png(splash(width, height), { rgb: true }));
  }

  for (const filename of [
    "splash-2732x2732.png",
    "splash-2732x2732-1.png",
    "splash-2732x2732-2.png",
  ]) {
    outputs.set(
      `ios/App/App/Assets.xcassets/Splash.imageset/${filename}`,
      png(splash(2732, 2732), { rgb: true })
    );
  }
  return outputs;
}

async function main() {
  const check = process.argv.includes("--check");
  const outputs = buildAssetOutputs();
  const mismatches = [];
  for (const [relativePath, expected] of outputs) {
    const destination = resolve(root, relativePath);
    let actual;
    try {
      actual = await readFile(destination);
    } catch {
      if (check) {
        mismatches.push(`${relativePath} (missing)`);
      }
    }

    if (actual && equivalentAssetBytes(actual, expected)) continue;
    if (check) {
      if (actual) mismatches.push(relativePath);
    } else {
      await mkdir(dirname(destination), { recursive: true });
      await writeFile(destination, expected);
    }
  }

  if (mismatches.length) {
    throw new Error(`Store assets are stale or non-deterministic:\n${mismatches.join("\n")}`);
  }

  const digest = createHash("sha256")
    .update(Buffer.concat([...outputs.values()].map(canonicalAssetBytes)))
    .digest("hex");
  console.log(`${check ? "Verified" : "Generated"} deterministic store assets: ${digest}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
