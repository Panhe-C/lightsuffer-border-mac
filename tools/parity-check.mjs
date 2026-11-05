// tools/parity-check.mjs - compares the Swift port with the JavaScript original.
//
// For every style, every picture size and every set of options it runs
//
//   * the Swift CLI:      frame-cli calls --style S --width W --height H ...
//   * the JS reference:   node tools/dump-calls.mjs --style S --width W --height H ...
//
// and compares the layout JSON and the whole call log, number by number, with
// a tolerance of 1e-6 (relative and absolute).
//
// USAGE:
//   node tools/parity-check.mjs [path/to/frame-cli]
//
// The frame-cli path defaults to .build/debug/frame-cli (or `swift run
// frame-cli` when the binary has not been built yet). The report is written to
// out/parity-report.json; the exit code is 1 when something does not match.

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

import { devicePoints } from './recording-context.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');

const TOLERANCE = 1e-6;

const SIZES = [
  [3000, 2000],
  [2000, 3000],
  [2000, 2000],
  [1920, 1080],
  [64, 48],
  [4000, 1200],
  [1200, 4000],
];

const OPTIONS = [
  { name: 'stock', text: 'Kodak Portra 400' },
  { name: 'no-text', text: '' },
  { name: 'auto-mono', text: 'Ilford HP5 Plus' },
  { name: 'forced-mono', text: 'KODAK PORTRA 400', mono: true },
];

const STYLES = [
  'none', 'thin-white', 'polaroid', 'black', 'film35', 'film120',
  'edge-black-thin', 'edge-black', 'edge-white-thin', 'edge-white',
];

/// The frame-cli binary of the package, if it has been built.
function defaultCli() {
  const candidates = [
    ['.build', 'debug', 'frame-cli'],
    ['.build', 'release', 'frame-cli'],
    ['.build', 'x86_64-unknown-linux-gnu', 'debug', 'frame-cli'],
    ['.build', 'aarch64-unknown-linux-gnu', 'debug', 'frame-cli'],
    ['.build', 'arm64-apple-macosx', 'debug', 'frame-cli'],
    ['.build', 'x86_64-apple-macosx', 'debug', 'frame-cli'],
    ['.build', 'apple', 'Products', 'Debug', 'frame-cli'],
  ];
  for (const parts of candidates) {
    const binary = path.join(root, ...parts);
    if (existsSync(binary)) return binary;
  }
  return null;
}

function runSwift(cli, args) {
  const command = cli || 'swift';
  const argv = cli ? args : ['run', 'frame-cli', ...args];
  const stdout = execFileSync(command, argv, {
    cwd: root,
    encoding: 'utf8',
    maxBuffer: 256 * 1024 * 1024,
  });
  return JSON.parse(stdout);
}

function runJs(args) {
  // The JS twin has no sub command: `frame-cli calls ...` is `dump-calls ...`.
  const argv = args[0] === 'calls' ? args.slice(1) : args;
  const stdout = execFileSync(process.execPath, [path.join(here, 'dump-calls.mjs'), ...argv], {
    cwd: root,
    encoding: 'utf8',
    maxBuffer: 256 * 1024 * 1024,
  });
  return JSON.parse(stdout);
}

/**
 * Deep comparison with a tolerance for the numbers.
 * @returns {string[]} the differences (empty when the values match)
 */
export function compareValues(swift, js, label = 'value', differences = []) {
  if (typeof swift === 'number' && typeof js === 'number') {
    const allowed = TOLERANCE * Math.max(1, Math.abs(swift), Math.abs(js));
    if (Math.abs(swift - js) > allowed) {
      differences.push(`${label}: ${swift} != ${js}`);
    }
    return differences;
  }
  if (Array.isArray(swift) || Array.isArray(js)) {
    if (!Array.isArray(swift) || !Array.isArray(js)) {
      differences.push(`${label}: ${JSON.stringify(swift)} != ${JSON.stringify(js)}`);
      return differences;
    }
    if (swift.length !== js.length) {
      differences.push(`${label}: ${swift.length} elements != ${js.length} elements`);
    }
    const count = Math.min(swift.length, js.length);
    for (let index = 0; index < count; index += 1) {
      compareValues(swift[index], js[index], `${label}[${index}]`, differences);
    }
    return differences;
  }
  if (swift && js && typeof swift === 'object' && typeof js === 'object') {
    const keys = new Set([...Object.keys(swift), ...Object.keys(js)]);
    for (const key of [...keys].sort()) {
      const left = swift[key];
      const right = js[key];
      if (left === undefined && right === undefined) continue;
      if (left === undefined || right === undefined) {
        // A missing key and an explicit null mean the same thing.
        if (left === null && right === undefined) continue;
        if (right === null && left === undefined) continue;
        differences.push(`${label}.${key}: ${JSON.stringify(left)} != ${JSON.stringify(right)}`);
        continue;
      }
      compareValues(left, right, `${label}.${key}`, differences);
    }
    return differences;
  }
  if (swift !== js) {
    differences.push(`${label}: ${JSON.stringify(swift)} != ${JSON.stringify(js)}`);
  }
  return differences;
}

/**
 * Is any painted point inside the photo? The photo must never be touched.
 */
export function pointsInsidePhoto(layout, calls) {
  const points = devicePoints(calls);
  const inside = [];
  points.forEach((callPoints, index) => {
    for (const [x, y] of callPoints) {
      if (x > layout.left + 0.5 && x < layout.left + layout.photoW - 0.5 &&
        y > layout.top + 0.5 && y < layout.top + layout.photoH - 0.5) {
        inside.push({ call: index, x, y });
      }
    }
  });
  return inside;
}

function main() {
  const cli = process.argv[2] && process.argv[2] !== '-' ? process.argv[2] : defaultCli();
  if (!cli) {
    process.stderr.write(
      'parity-check: no frame-cli binary found, falling back to "swift run frame-cli" ' +
      '(build it first with "swift build" to make this faster)\n'
    );
  }
  const cliName = cli || 'swift run frame-cli';
  process.stdout.write(`parity-check: Swift = ${cliName}\n`);
  process.stdout.write(`parity-check: JS    = tools/dump-calls.mjs (tools/border.js)\n`);

  const results = [];
  let failures = 0;
  let checks = 0;

  for (const style of STYLES) {
    for (const [width, height] of SIZES) {
      for (const options of OPTIONS) {
        const args = ['calls', '--style', style, '--width', String(width), '--height', String(height)];
        if (options.text !== undefined) args.push('--text', options.text);
        if (options.mono !== undefined) args.push(options.mono ? '--mono' : '--no-mono');

        const label = `${style} ${width}x${height} [${options.name}]`;
        checks += 1;
        let swift;
        let js;
        try {
          swift = runSwift(cli, args);
          js = runJs(args);
        } catch (error) {
          failures += 1;
          results.push({ style, width, height, options: options.name, ok: false, differences: [`crash: ${error.message}`] });
          process.stdout.write(`FAIL ${label}: ${error.message}\n`);
          continue;
        }

        const differences = compareValues(swift.layout, js.layout, 'layout');
        compareValues(swift.calls, js.calls, 'calls', differences);

        // The photo is never painted: neither implementation may put a point
        // inside the picture.
        const swiftInside = pointsInsidePhoto(swift.layout, swift.calls);
        const jsInside = pointsInsidePhoto(js.layout, js.calls);
        if (swiftInside.length) {
          differences.push(`swift paints inside the photo: ${JSON.stringify(swiftInside.slice(0, 3))}`);
        }
        if (jsInside.length) {
          differences.push(`js paints inside the photo: ${JSON.stringify(jsInside.slice(0, 3))}`);
        }

        const ok = differences.length === 0;
        if (!ok) failures += 1;
        results.push({
          style,
          width,
          height,
          options: options.name,
          text: options.text,
          mono: options.mono === undefined ? null : options.mono,
          calls: swift.calls.length,
          jsCalls: js.calls.length,
          ok,
          differences,
        });
        if (!ok) {
          process.stdout.write(`FAIL ${label}\n`);
          for (const difference of differences.slice(0, 10)) {
            process.stdout.write(`     ${difference}\n`);
          }
        }
      }
    }
  }

  const report = {
    tool: 'parity-check',
    swift: cliName,
    js: 'tools/border.js',
    tolerance: TOLERANCE,
    sizes: SIZES.map(([w, h]) => `${w}x${h}`),
    options: OPTIONS,
    checks,
    failures,
    results,
  };

  const outDir = path.join(root, 'out');
  mkdirSync(outDir, { recursive: true });
  const reportPath = path.join(outDir, 'parity-report.json');
  writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);

  process.stdout.write(
    `parity-check: ${checks - failures}/${checks} combinations match ` +
    `(report: ${path.relative(root, reportPath)})\n`
  );
  if (failures) {
    process.stdout.write(`parity-check: FAIL (${failures} mismatches)\n`);
    process.exit(1);
  }
  process.stdout.write('parity-check: PASS\n');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
