// Emits block-style YAML. Strings that YAML would read as something else (numbers, booleans, null, values
// with ": " or a leading symbol) are written as JSON strings, which are valid double-quoted YAML.

var reserved = /^(true|false|yes|no|on|off|y|n|null|~)$/i;

function needsQuotes(s) {
  return s === '' || reserved.test(s) || /^[\s]|[\s]$/.test(s) || /^[-+]?(\.?\d|\.inf|\.nan)/i.test(s) ||
    /^[-?:,\[\]{}#&*!|>'"%@`]/.test(s) || /:(\s|$)|\s#/.test(s) || /[\u0000-\u001f\u007f]/.test(s);
}

function scalar(v) {
  if (v === null) { return 'null'; }
  if (typeof v === 'string') { return needsQuotes(v) ? JSON.stringify(v) : v; }
  if (Array.isArray(v)) { return '[]'; }
  if (typeof v === 'object') { return '{}'; }
  return String(v);
}

function isBlock(v) {
  return v !== null && typeof v === 'object' && (Array.isArray(v) ? v.length > 0 : Object.keys(v).length > 0);
}

function block(value, pad) {
  var out = [];
  if (Array.isArray(value)) {
    value.forEach(function (item) {
      if (isBlock(item)) {
        var inner = block(item, pad + '  ');
        out.push(pad + '- ' + inner[0].slice(pad.length + 2));
        out.push.apply(out, inner.slice(1));
      } else {
        out.push(pad + '- ' + scalar(item));
      }
    });
  } else {
    Object.keys(value).forEach(function (key) {
      var v = value[key];
      var k = needsQuotes(key) ? JSON.stringify(key) : key;
      if (isBlock(v)) {
        out.push(pad + k + ':');
        out.push.apply(out, block(v, pad + '  '));
      } else {
        out.push(pad + k + ': ' + scalar(v));
      }
    });
  }
  return out;
}

var data;
try {
  data = JSON.parse(glint.input.text);
} catch (e) {
  throw new Error('Not valid JSON: ' + e.message);
}
return isBlock(data) ? block(data, '').join('\n') : scalar(data);
