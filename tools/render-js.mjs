// tools/render-js.mjs - renders the JavaScript reference painter with
// node-canvas.
//
// For every picture in samples/ and every style it draws the photo inside the
// frame of tools/border.js (the untouched wx-spektrafilm source) and writes
// out/js/<name>_<style>.png. It is the visual reference of the Swift render
// of the macOS app.
//
// USAGE:
//   node tools/render-js.mjs [samples/...]
//
// node-canvas is an optional dependency: without it the script explains what
// is missing and stops (the parity check does not need it).

import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');

let canvasModule = null;
try {
  canvasModule = await import('canvas');
} catch (error) {
  process.stderr.write(
    'render-js: the optional dependency "canvas" is not installed.\n' +
    '           Run "npm install" in tools/ (it needs the cairo build tools) and try again.\n'
  );
  process.exit(0);
}

const Border = await loadBorder();

/**
 * Loads the untouched CommonJS reference (tools/border.js). See the note in
 * tools/dump-calls.mjs: with "type": "module" the .js file is an ES module and
 * its UMD wrapper puts the factory on the global object.
 */
async function loadBorder() {
  const modulePath = path.join(here, 'border.js');
  try {
    await import(modulePath);
  } catch (error) {
    // Not an ES module: fall back to CommonJS below.
  }
  if (globalThis.SpektrafilmBorder) return globalThis.SpektrafilmBorder;
  const require = createRequire(import.meta.url);
  const border = require(modulePath);
  return border.SpektrafilmBorder || border;
}

const STYLES = Border.STYLE_IDS;
const STOCK = 'Kodak Portra 400';

function sampleFiles() {
  const args = process.argv.slice(2);
  const folders = args.length ? args : [path.join(root, 'samples')];
  const files = [];
  for (const folder of folders) {
    if (!existsSync(folder)) continue;
    for (const name of readdirSync(folder).sort()) {
      if (!/\.(jpe?g|png)$/i.test(name)) continue;
      files.push(path.join(folder, name));
    }
  }
  return files;
}

async function main() {
  const { createCanvas, loadImage } = canvasModule;
  const files = sampleFiles();
  if (!files.length) {
    process.stdout.write('render-js: no picture in samples/, nothing to render\n');
    return;
  }
  const outDir = path.join(root, 'out', 'js');
  mkdirSync(outDir, { recursive: true });

  for (const file of files) {
    const image = await loadImage(file);
    const name = path.basename(file).replace(/\.[^.]+$/, '');
    for (const style of STYLES) {
      const layout = Border.computeLayout(style, image.width, image.height);
      const canvas = createCanvas(layout.outerW, layout.outerH);
      const ctx = canvas.getContext('2d');
      // The photo keeps its pixels: it is only placed inside the frame.
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, layout.outerW, layout.outerH);
      ctx.drawImage(image, layout.left, layout.top, layout.photoW, layout.photoH);
      Border.drawBorder(ctx, layout, { stockName: STOCK });
      const out = path.join(outDir, `${name}_${style}.png`);
      const buffer = canvas.toBuffer('image/png');
      writeFileSync(out, buffer);
      process.stdout.write(`render-js: ${path.relative(root, out)} (${layout.outerW}x${layout.outerH})\n`);
    }
  }
}

await main();
