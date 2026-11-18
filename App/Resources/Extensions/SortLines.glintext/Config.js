// Sort Lines — sorts the selected lines in natural order (so "item 2" comes before "item 10").
// Hold ⌥ to sort in descending order. Options: remove duplicates, ignore case.

module.exports = {
  identifier: 'dev.saibarath.glint.sort-lines',
  name: 'Sort Lines',
  description: 'Sort the selected lines A→Z (hold ⌥ for Z→A), optionally removing duplicates.',
  icon: 'symbol:arrow.up.arrow.down',
  options: [
    { identifier: 'unique', label: 'Remove duplicate lines', type: 'boolean', defaultValue: false },
    { identifier: 'ignoreCase', label: 'Ignore case', type: 'boolean', defaultValue: true },
  ],
  actions: [
    {
      title: 'Sort Lines',
      requirements: ['text'],
      after: 'paste-result',
      code: function (input, options, context) {
        var lines = input.text.split(/\r?\n/);
        var sensitivity = options.ignoreCase === false ? 'variant' : 'base';
        var compare = function (a, b) {
          return a.localeCompare(b, undefined, { numeric: true, sensitivity: sensitivity }) ||
                 (a < b ? -1 : a > b ? 1 : 0);
        };
        lines.sort(compare);
        if (glint.modifiers.option) { lines.reverse(); }
        if (options.unique) {
          var seen = {};
          lines = lines.filter(function (l) {
            var key = options.ignoreCase === false ? l : l.toLowerCase();
            if (seen.hasOwnProperty(key)) { return false; }
            seen[key] = true;
            return true;
          });
        }
        return lines.join('\n');
      },
    },
  ],
};
