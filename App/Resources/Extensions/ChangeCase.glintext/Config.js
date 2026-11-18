// Change Case — a Glint JavaScript-module extension.
// Every action returns the converted text; `after: paste-result` replaces the selection
// in editable text, and Glint copies the result instead when the selection can't be pasted over
// (or when ⇧ is held).

// Split one line into words, breaking on punctuation/whitespace and on camelCase humps
// ("parseHTTPResponse" -> parse, HTTP, Response).
function words(line) {
  return line
    .replace(/([\p{Ll}\p{N}])(\p{Lu})/gu, '$1 $2')
    .replace(/(\p{Lu}+)(\p{Lu}\p{Ll})/gu, '$1 $2')
    .split(/[^\p{L}\p{N}]+/u)
    .filter(function (w) { return w.length > 0; });
}

function capitalize(w) {
  return w.charAt(0).toUpperCase() + w.slice(1).toLowerCase();
}

// Apply `fn` to each line so multi-line selections keep their shape.
function perLine(text, fn) {
  return text.split('\n').map(function (line) { return line.trim() === '' ? line : fn(line); }).join('\n');
}

var minorWords = ['a', 'an', 'and', 'as', 'at', 'but', 'by', 'for', 'in', 'nor', 'of', 'on', 'or', 'per', 'the',
                  'to', 'vs', 'via'];

function titleCase(text) {
  return perLine(text, function (line) {
    var parts = line.split(/(\s+)/);
    var wordIndexes = [];
    parts.forEach(function (p, i) { if (/\S/.test(p)) { wordIndexes.push(i); } });
    var first = wordIndexes[0], last = wordIndexes[wordIndexes.length - 1];
    return parts.map(function (p, i) {
      if (!/\S/.test(p)) { return p; }
      var lower = p.toLowerCase();
      if (i !== first && i !== last && minorWords.indexOf(lower.replace(/[^a-z]/g, '')) >= 0) { return lower; }
      // Capitalise the first letter, even after leading punctuation like quotes or brackets.
      return lower.replace(/\p{L}/u, function (c) { return c.toUpperCase(); });
    }).join('');
  });
}

function sentenceCase(text) {
  var lower = text.toLowerCase();
  // Upper-case the first letter of the text and of every sentence after . ! ? or a blank line.
  lower = lower.replace(/(^\s*|[.!?]\s+|\n\s*\n\s*)(\p{Ll})/gu, function (m, pre, c) { return pre + c.toUpperCase(); });
  // The pronoun "I" and its contractions.
  return lower.replace(/\bi\b(?=$|[\s'’.,!?;:])/g, 'I');
}

module.exports = {
  identifier: 'dev.saibarath.glint.change-case',
  name: 'Change Case',
  description: 'Convert the selection to UPPERCASE, lowercase, Title Case, Sentence case, camelCase, snake_case or kebab-case.',
  icon: 'symbol:textformat',
  requirements: ['text'],
  after: 'paste-result',
  actions: [
    { title: 'UPPERCASE', icon: 'text:AB', code: function (input) { return input.text.toUpperCase(); } },
    { title: 'lowercase', icon: 'text:ab', code: function (input) { return input.text.toLowerCase(); } },
    { title: 'Title Case', icon: 'text:Aa', code: function (input) { return titleCase(input.text); } },
    { title: 'Sentence case', icon: 'text:A.', code: function (input) { return sentenceCase(input.text); } },
    {
      title: 'camelCase', icon: 'text:aB',
      code: function (input) {
        return perLine(input.text, function (line) {
          return words(line).map(function (w, i) { return i === 0 ? w.toLowerCase() : capitalize(w); }).join('');
        });
      }
    },
    {
      title: 'snake_case', icon: 'text:a_b',
      code: function (input) {
        return perLine(input.text, function (line) { return words(line).join('_').toLowerCase(); });
      }
    },
    {
      title: 'kebab-case', icon: 'text:a-b',
      code: function (input) {
        return perLine(input.text, function (line) { return words(line).join('-').toLowerCase(); });
      }
    },
  ],
};
