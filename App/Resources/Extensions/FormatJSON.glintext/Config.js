// Format JSON — pretty-print or minify JSON. Invalid JSON fails (Glint shows ✗ and logs the parse error).

function parse(text) {
  try {
    return JSON.parse(text);
  } catch (e) {
    throw new Error('Not valid JSON: ' + e.message);
  }
}

function sortKeys(value) {
  if (Array.isArray(value)) { return value.map(sortKeys); }
  if (value !== null && typeof value === 'object') {
    var out = {};
    Object.keys(value).sort().forEach(function (k) { out[k] = sortKeys(value[k]); });
    return out;
  }
  return value;
}

module.exports = {
  identifier: 'dev.saibarath.glint.format-json',
  name: 'Format JSON',
  description: 'Pretty-print or minify selected JSON. Invalid JSON shows a failure.',
  icon: 'symbol:curlybraces',
  requirements: ['text'],
  after: 'paste-result',
  options: [
    { identifier: 'indent', label: 'Indentation', type: 'multiple', values: ['2', '4', 'tab'],
      valueLabels: ['2 spaces', '4 spaces', 'Tab'], defaultValue: '2' },
    { identifier: 'sortKeys', label: 'Sort object keys', type: 'boolean', defaultValue: false },
  ],
  actions: [
    {
      title: 'Format JSON', icon: 'symbol:curlybraces',
      code: function (input, options) {
        var value = parse(input.text);
        if (options.sortKeys) { value = sortKeys(value); }
        var indent = options.indent === 'tab' ? '\t' : Number(options.indent || 2);
        return JSON.stringify(value, null, indent);
      },
    },
    {
      title: 'Minify JSON', icon: 'symbol:arrow.down.right.and.arrow.up.left',
      code: function (input, options) {
        var value = parse(input.text);
        if (options.sortKeys) { value = sortKeys(value); }
        return JSON.stringify(value);
      },
    },
  ],
};
