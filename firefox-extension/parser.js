(() => {
  const shiftPattern = /^(?:X|SL|HL|A<[^>]+>|[LSCQ$]*(?:Xtra)?\d{3,4}[LSCQ$]*(?:Xtra)?|Xt\d{3,4}ra)$/i;

  function parseDate(value) {
    const text = (value || '').trim();
    let m = /^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/.exec(text);
    if (m) {
      let year = Number(m[3]);
      if (year < 100) year += 2000;
      return `${year.toString().padStart(4, '0')}-${m[1].padStart(2, '0')}-${m[2].padStart(2, '0')}`;
    }
    m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(text);
    if (m) return `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}`;
    return null;
  }

  function normalizeToken(raw) {
    let token = (raw || '').trim()
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
    const annual = /A<[^>]+>/i.exec(token);
    if (annual) return annual[0];
    return token.replace(/^[^A-Za-z0-9$]+|[^A-Za-z0-9$]+$/g, '');
  }

  function parseShift(raw) {
    const token = normalizeToken(raw);
    if (!token || !shiftPattern.test(token)) return null;
    const normalized = token.toUpperCase();

    if (normalized === 'X') return { raw: token, shiftType: 'dayOff', startMinutes: null, overtimeBeforeMinutes: 0, overtimeAfterMinutes: 0 };
    if (normalized === 'SL') return { raw: token, shiftType: 'sickLeave', startMinutes: null, overtimeBeforeMinutes: 0, overtimeAfterMinutes: 0 };
    if (normalized === 'HL') return { raw: token, shiftType: 'holidayLeave', startMinutes: null, overtimeBeforeMinutes: 0, overtimeAfterMinutes: 0 };

    const annual = /^A<([^>]+)>$/i.exec(normalized);
    if (annual) {
      const t = /(\d{3,4})/.exec(annual[1]);
      if (!t) return null;
      const digits = t[1].padStart(4, '0');
      const hour = Number(digits.slice(0, 2));
      const minute = Number(digits.slice(2, 4));
      if (hour > 23 || minute > 59) return null;
      return { raw: token, shiftType: 'annualLeave', startMinutes: hour * 60 + minute, overtimeBeforeMinutes: 0, overtimeAfterMinutes: 0 };
    }

    const t = /(\d{3,4})/.exec(normalized);
    if (!t) return null;
    const digits = t[1].padStart(4, '0');
    const hour = Number(digits.slice(0, 2));
    const minute = Number(digits.slice(2, 4));
    if (hour > 23 || minute > 59) return null;

    const lower = token.toLowerCase().replaceAll(' ', '');
    const xtraBefore = lower.startsWith('xtra');
    const xtraAfter = lower.endsWith('xtra');
    const splitXtra = lower.startsWith('xt') && lower.endsWith('ra') && !xtraBefore;
    let overtimeBeforeMinutes = 0;
    let overtimeAfterMinutes = 0;
    if (splitXtra) {
      overtimeBeforeMinutes = 60;
      overtimeAfterMinutes = 60;
    } else {
      if (xtraBefore) overtimeBeforeMinutes = 120;
      if (xtraAfter) overtimeAfterMinutes = 120;
    }

    return {
      raw: token,
      shiftType: normalized.includes('$') ? 'overtime' : 'regular',
      startMinutes: hour * 60 + minute,
      overtimeBeforeMinutes,
      overtimeAfterMinutes,
      flexType: normalized.includes('L') ? 'late' : normalized.includes('Q') ? 'quarter' : 'none',
      isSupervisor: normalized.includes('S'),
      isCic: normalized.includes('C'),
    };
  }

  function findShift(text) {
    const decoded = (text || '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
    const annual = /A<[^>]+>/i.exec(decoded);
    if (annual) {
      const parsed = parseShift(annual[0]);
      if (parsed) return parsed;
    }
    for (const token of decoded.split(/\s+/)) {
      const parsed = parseShift(token);
      if (parsed) return parsed;
    }
    return null;
  }

  function extract(html) {
    if (!html) return [];
    const protectedHtml = html.replace(/A<([A-Za-z0-9$]+)>/gi, 'A&lt;$1&gt;');
    const doc = new DOMParser().parseFromString(protectedHtml, 'text/html');
    const results = [];

    for (const cell of doc.querySelectorAll('td,th')) {
      const text = (cell.textContent || '').replace(/\s+/g, ' ').trim()
        .replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&amp;', '&');
      const dateMatch = /\b(\d{1,2}\/\d{1,2}\/\d{2,4})\b/.exec(text);
      if (!dateMatch) continue;
      const date = parseDate(dateMatch[1]);
      const shift = findShift(text.slice(dateMatch.index + dateMatch[0].length).trim());
      if (date && shift) results.push({ date, ...shift });
    }

    if (!results.length) {
      const text = (doc.body?.textContent || '').replace(/\s+/g, ' ').trim();
      const pair = /\b(\d{1,2}\/\d{1,2}\/\d{2,4})\b\s+([^\s]+)/g;
      for (const match of text.matchAll(pair)) {
        const date = parseDate(match[1]);
        const shift = parseShift(match[2]);
        if (date && shift) results.push({ date, ...shift });
      }
    }

    const byDay = new Map();
    for (const item of results) byDay.set(item.date, item);
    return [...byDay.values()].sort((a, b) => a.date.localeCompare(b.date));
  }

  function formatMinutes(minutes) {
    if (minutes == null) return '—';
    const h = Math.floor(minutes / 60) % 24;
    const m = minutes % 60;
    return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}`;
  }

  window.WmtParser = { extract, parseShift, formatMinutes };
})();
