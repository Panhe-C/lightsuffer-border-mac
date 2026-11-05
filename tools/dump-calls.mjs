// tools/dump-calls.mjs - the JavaScript side of the parity interface.
//
// It runs the original painter (tools/border.js, the untouched wx-spektrafilm
// source) on a recording context (tools/recording-context.mjs) and prints the
// same JSON as `frame-cli calls`:
//
//   { "layout": { ... }, "calls": [ ... ] }
//
// USAGE:
//   node tools/dump-calls.mjs [--calls] --style S --width W --height H
//                             [--text T] [--mono|--no-mono]
//                             [--frame-number N] [--squeeze 0.8]
//
// The arguments are the ones of `frame-cli calls` (the leading "calls" is
// accepted and ignored). The JavaScript painter always squeezes the 120 edge
// print by 0.8 (PRINT_SQUEEZE in border.js), so --squeeze is only accepted
// for symmetry.

import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

import { recordingContext } from './recording-context.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));

/**
 * Loads the untouched CommonJS reference (tools/border.js).
 *
 * tools/package.json declares "type": "module", so the .js file is parsed as
 * an ES module: its UMD wrapper then puts the factory on the global object.
 * The CommonJS path is kept as a fallback.
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

const Border = await loadBorder();

function parseArguments(argv) {
  const options = {
    style: 'none',
    width: null,
    height: null,
    text: '',
    monochrome: undefined,
    frameNumber: undefined,
    squeeze: 0.8,
  };
  const value = (name, index) => {
    if (index + 1 >= argv.length) {
      throw new Error(`${name} needs a value`);
    }
    return argv[index + 1];
  };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (index === 0 && flag === 'calls') continue;
    switch (flag) {
      case '--style':
        options.style = value(flag, index);
        index += 1;
        break;
      case '--width':
        options.width = Number(value(flag, index));
        index += 1;
        break;
      case '--height':
        options.height = Number(value(flag, index));
        index += 1;
        break;
      case '--text':
        options.text = value(flag, index);
        index += 1;
        break;
      case '--mono':
        options.monochrome = true;
        break;
      case '--no-mono':
        options.monochrome = false;
        break;
      case '--frame-number':
        options.frameNumber = Number(value(flag, index));
        index += 1;
        break;
      case '--squeeze':
        options.squeeze = Number(value(flag, index));
        index += 1;
        break;
      default:
        throw new Error(`unknown argument ${flag}`);
    }
  }
  if (options.width === null || options.height === null) {
    throw new Error('--width and --height are required');
  }
  return options;
}

/// JSON.stringify with sorted keys, so that the output looks like the one of
/// the Swift CLI (JSONSerialization with .sortedKeys).
export function stableStringify(value, indent = 2) {
  const sort = (input) => {
    if (Array.isArray(input)) return input.map(sort);
    if (input && typeof input === 'object') {
      const out = {};
      for (const key of Object.keys(input).sort()) out[key] = sort(input[key]);
      return out;
    }
    return input;
  };
  return JSON.stringify(sort(value), null, indent);
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.squeeze !== 0.8) {
    process.stderr.write('dump-calls: the JavaScript painter always uses the squeeze 0.8, ignoring --squeeze\n');
  }
  const layout = Border.computeLayout(options.style, options.width, options.height);
  const context = recordingContext();
  const paintOptions = { stockName: options.text };
  if (options.frameNumber !== undefined) paintOptions.frameNumber = options.frameNumber;
  if (options.monochrome !== undefined) paintOptions.monochrome = options.monochrome;
  Border.drawBorder(context, layout, paintOptions);
  const output = { layout, calls: context.calls };
  process.stdout.write(`${stableStringify(output)}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`dump-calls: ${error.message}\n`);
    process.exit(2);
  }
}
