// Headline Case: title case that follows a style guide, as a JavaScript-module extension.
//
//  - Chicago / MLA: articles, coordinating conjunctions and every preposition stay lowercase
//    ("A Walk through the Woods").
//  - AP / APA: only articles, conjunctions and prepositions of three letters or fewer stay lowercase
//    ("A Walk Through the Woods").
//
// Both styles capitalise the first and last word and the first word after a colon or dash, capitalise each
// part of a hyphenated compound, and leave words with capitals inside them (iPhone, NASA, macOS) alone.

var articles = ['a', 'an', 'the'];
var conjunctions = ['and', 'but', 'for', 'nor', 'or', 'so', 'yet'];
var prepositions = ['about', 'above', 'across', 'after', 'against', 'along', 'amid', 'among', 'around', 'as', 'at',
  'before', 'behind', 'below', 'beneath', 'beside', 'besides', 'between', 'beyond', 'by', 'despite', 'down', 'during',
  'except', 'for', 'from', 'in', 'inside', 'into', 'like', 'near', 'of', 'off', 'on', 'onto', 'out', 'outside', 'over',
  'past', 'per', 'since', 'than', 'through', 'throughout', 'till', 'to', 'toward', 'towards', 'under', 'underneath',
  'until', 'up', 'upon', 'via', 'with', 'within', 'without'];

function isMinor(word, style) {
  if (articles.indexOf(word) >= 0) { return true; }
  if (style === 'chicago') {
    return (conjunctions.indexOf(word) >= 0 && word !== 'so' && word !== 'yet') || prepositions.indexOf(word) >= 0;
  }
  return word.length <= 3 && (conjunctions.indexOf(word) >= 0 || prepositions.indexOf(word) >= 0);
}

function capitalize(word) {
  // Leave words that already have a capital after the first letter: iPhone, NASA, McDonald.
  if (/^.+\p{Lu}/u.test(word.replace(/^[^\p{L}]+/u, ''))) { return word; }
  return word.toLowerCase().replace(/\p{L}/u, function (c) { return c.toUpperCase(); });
}

function headline(line, style) {
  var tokens = line.split(/(\s+)/);
  var wordIndexes = [];
  tokens.forEach(function (t, i) { if (/\S/.test(t)) { wordIndexes.push(i); } });
  var first = wordIndexes[0], last = wordIndexes[wordIndexes.length - 1];
  var afterBreak = false;
  return tokens.map(function (token, i) {
    if (!/\S/.test(token)) { return token; }
    var forced = i === first || i === last || afterBreak;
    afterBreak = /[:—–]$/.test(token) || token === '-';
    return token.split('-').map(function (part, j) {
      var bare = part.toLowerCase().replace(/[^\p{L}']/gu, '');
      var keepUpper = forced && j === 0;
      if (!keepUpper && isMinor(bare, style) && !/^.+\p{Lu}/u.test(part)) { return part.toLowerCase(); }
      return capitalize(part);
    }).join('-');
  }).join('');
}

module.exports = {
  identifier: 'io.github.saibarathr.glint.gallery.headline-case',
  name: 'Headline Case',
  description: 'Title-case a headline by the Chicago / MLA or AP / APA rules for which small words stay lowercase.',
  icon: 'text:Hc',
  author: 'Glint gallery',
  after: 'paste-result',
  options: [
    {
      identifier: 'style', label: 'Style guide', type: 'multiple', values: ['chicago', 'ap'],
      valueLabels: ['Chicago / MLA', 'AP / APA'], defaultValue: 'chicago',
      description: 'Chicago lowercases every preposition; AP lowercases only those of three letters or fewer.',
    },
  ],
  actions: [
    {
      title: 'Headline Case',
      icon: 'text:Hc',
      code: function (input, options) {
        var style = options.style === 'ap' ? 'ap' : 'chicago';
        return input.text.split('\n').map(function (line) { return headline(line, style); }).join('\n');
      },
    },
  ],
};
