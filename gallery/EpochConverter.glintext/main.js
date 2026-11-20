// Epoch Converter: the static keys live in Config.json, and this module supplies the actions.

function pad(n, width) { return String(Math.abs(n)).padStart(width || 2, '0'); }

function isoUTC(date) {
  var s = date.toISOString();
  return s.endsWith('.000Z') ? s.replace('.000Z', 'Z') : s;
}

// 2023-11-14T23:13:20+01:00, in the Mac's time zone.
function isoLocal(date) {
  var offset = -date.getTimezoneOffset();
  var zone = offset === 0 ? 'Z' : (offset > 0 ? '+' : '-') + pad(Math.floor(Math.abs(offset) / 60)) + ':' + pad(Math.abs(offset) % 60);
  var ms = date.getMilliseconds();
  return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) + 'T' + pad(date.getHours()) + ':' +
    pad(date.getMinutes()) + ':' + pad(date.getSeconds()) + (ms ? '.' + pad(ms, 3) : '') + zone;
}

module.exports = {
  actions: [
    {
      title: 'To Date',
      icon: 'symbol:calendar',
      // 9–10 digits are seconds (1973–2286), 12–13 digits milliseconds.
      regex: '^\\s*-?(\\d{9,10}|\\d{12,13})(\\.\\d+)?\\s*$',
      code: function (input) {
        var n = Number(input.text.trim());
        var date = new Date(Math.abs(n) >= 1e11 ? n : n * 1000);
        if (isNaN(date.getTime())) { throw new Error('Not a timestamp: ' + input.text); }
        return glint.modifiers.option ? isoLocal(date) : isoUTC(date);
      },
    },
    {
      title: 'To Timestamp',
      icon: 'symbol:number',
      // ISO 8601 dates: 2023-11-14, 2023-11-14 22:13, 2023-11-14T22:13:20.5Z, …+05:30, … UTC
      regex: '^\\s*\\d{4}-\\d{2}-\\d{2}(?:[T ]\\d{2}:\\d{2}(?::\\d{2}(?:\\.\\d+)?)?)?\\s*(?:Z|UTC|GMT|[+-]\\d{2}:?\\d{2})?\\s*$',
      code: function (input) {
        var s = input.text.trim()
          .replace(/\s*(UTC|GMT)$/, 'Z')                    // "… UTC" -> "…Z"
          .replace(/^(\d{4}-\d{2}-\d{2}) (\d)/, '$1T$2')    // date and time separated by a space
          .replace(/\s+(?=[Z+-][\d:]*$)/, '')                 // no space before the zone
          .replace(/([+-]\d{2})(\d{2})$/, '$1:$2');          // +0530 -> +05:30
        var ms = Date.parse(s); // date-only values are UTC; a time without a zone is local time
        if (isNaN(ms)) { throw new Error('Not a date: ' + input.text); }
        return String(glint.modifiers.option ? ms : Math.floor(ms / 1000));
      },
    },
  ],
};
