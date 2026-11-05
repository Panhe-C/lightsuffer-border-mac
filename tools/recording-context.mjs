// tools/recording-context.mjs - the JS twin of the Swift `RecordingCanvas`
// (Sources/FrameCore/RecordingCanvas.swift).
//
// It draws nothing and logs every call of the Canvas 2D subset that the
// border painter uses, in exactly the same vocabulary, so that the Swift port
// and the JavaScript original can be compared call by call
// (see tools/parity-check.mjs).
//
// The log is an array of arrays, one per call:
//
//   ['save'], ['restore'], ['beginPath'], ['closePath'], ['fill']
//   ['translate', x, y], ['rotate', angle], ['scale', x, y]
//   ['fillStyle', '#rrggbb'], ['strokeStyle', '...'], ['lineWidth', w]
//   ['textAlign', 'left' | 'right'], ['font', size]
//   ['fillRect', x, y, w, h], ['strokeRect', x, y, w, h]
//   ['moveTo', x, y], ['lineTo', x, y], ['arcTo', x1, y1, x2, y2, r]
//   ['fillText', text, x, y]
//
// `textBaseline` is ignored (the painter always uses 'middle'), exactly like
// in Swift. `measureText` is a deterministic stub: the width is the number of
// UTF-16 units times the font size times 0.6, so that the font fitting does
// not depend on the installed fonts.

const PX_FONT = /(\d+(?:\.\d+)?)px/;

/**
 * A recording 2D context.
 * @returns {{calls: Array<Array<any>>}}
 */
export function recordingContext() {
  const calls = [];
  const stack = [];
  let fontSize = 10;
  let silent = false;

  const state = {
    fillStyle: '#000000',
    strokeStyle: '#000000',
    lineWidth: 1,
    textAlign: 'left',
  };

  const api = {
    calls,

    get font() {
      return `bold ${fontSize}px sans-serif`;
    },
    set font(value) {
      const match = PX_FONT.exec(String(value));
      fontSize = match ? Number(match[1]) : 10;
      if (!silent) calls.push(['font', fontSize]);
    },

    // `textBaseline` is ignored: the painter always draws with a middle baseline.
    textBaseline: 'alphabetic',

    save() {
      stack.push({ ...state, fontSize });
      calls.push(['save']);
    },
    restore() {
      const saved = stack.pop();
      if (saved) {
        silent = true;
        try {
          state.fillStyle = saved.fillStyle;
          state.strokeStyle = saved.strokeStyle;
          state.lineWidth = saved.lineWidth;
          state.textAlign = saved.textAlign;
          fontSize = saved.fontSize;
        } finally {
          silent = false;
        }
      }
      calls.push(['restore']);
    },
    translate(x, y) {
      calls.push(['translate', x, y]);
    },
    rotate(angle) {
      calls.push(['rotate', angle]);
    },
    scale(x, y) {
      calls.push(['scale', x, y]);
    },
    fillRect(x, y, width, height) {
      calls.push(['fillRect', x, y, width, height]);
    },
    strokeRect(x, y, width, height) {
      calls.push(['strokeRect', x, y, width, height]);
    },
    beginPath() {
      calls.push(['beginPath']);
    },
    moveTo(x, y) {
      calls.push(['moveTo', x, y]);
    },
    lineTo(x, y) {
      calls.push(['lineTo', x, y]);
    },
    arcTo(x1, y1, x2, y2, radius) {
      calls.push(['arcTo', x1, y1, x2, y2, radius]);
    },
    closePath() {
      calls.push(['closePath']);
    },
    fill() {
      calls.push(['fill']);
    },
    fillText(text, x, y) {
      calls.push(['fillText', text, x, y]);
    },
    measureText(text) {
      return { width: String(text).length * fontSize * 0.6 };
    },
  };

  // The style properties are logged when they are set; a restore puts the
  // previous state back silently, like a real canvas.
  for (const name of Object.keys(state)) {
    Object.defineProperty(api, name, {
      enumerable: true,
      get() {
        return state[name];
      },
      set(next) {
        state[name] = next;
        if (!silent) calls.push([name, next]);
      },
    });
  }

  return api;
}

/**
 * Replays a recorded call log and returns the points every call touches, in
 * device space (the transform stack applied). The Swift twin of this function
 * is `CallLog.devicePoints` (Sources/FrameCore/CallLog.swift).
 *
 * @param {Array<Array<any>>} calls
 * @returns {Array<Array<Array<number>>>}
 */
export function devicePoints(calls) {
  let matrix = [1, 0, 0, 1, 0, 0];
  const stack = [];
  let path = [];
  const result = [];

  const multiply = (a, b) => [
    a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1],
    a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
    a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5],
  ];
  const apply = (x, y) => [
    matrix[0] * x + matrix[2] * y + matrix[4], matrix[1] * x + matrix[3] * y + matrix[5],
  ];
  const number = (call, index) => (typeof call[index] === 'number' ? call[index] : 0);

  for (const call of calls) {
    const op = call[0];
    switch (op) {
      case 'save':
        stack.push(matrix.slice());
        result.push([]);
        break;
      case 'restore':
        if (stack.length) matrix = stack.pop();
        result.push([]);
        break;
      case 'translate':
        matrix = multiply(matrix, [1, 0, 0, 1, number(call, 1), number(call, 2)]);
        result.push([]);
        break;
      case 'rotate':
        matrix = multiply(matrix, [Math.cos(number(call, 1)), Math.sin(number(call, 1)),
          -Math.sin(number(call, 1)), Math.cos(number(call, 1)), 0, 0]);
        result.push([]);
        break;
      case 'scale':
        matrix = multiply(matrix, [number(call, 1), 0, 0, number(call, 2), 0, 0]);
        result.push([]);
        break;
      case 'fillRect':
      case 'strokeRect': {
        const x = number(call, 1);
        const y = number(call, 2);
        result.push([apply(x, y), apply(x + number(call, 3), y + number(call, 4))]);
        break;
      }
      case 'moveTo':
      case 'lineTo': {
        const point = apply(number(call, 1), number(call, 2));
        path.push(point);
        result.push([point]);
        break;
      }
      case 'arcTo': {
        const first = apply(number(call, 1), number(call, 2));
        const second = apply(number(call, 3), number(call, 4));
        path.push(first, second);
        result.push([first, second]);
        break;
      }
      case 'beginPath':
        path = [];
        result.push([]);
        break;
      case 'closePath':
        result.push([]);
        break;
      case 'fill':
        result.push(path.slice());
        break;
      case 'fillText':
        result.push([apply(number(call, 2), number(call, 3))]);
        break;
      default:
        result.push([]);
        break;
    }
  }
  return result;
}

export default recordingContext;
