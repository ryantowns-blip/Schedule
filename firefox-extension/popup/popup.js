const captureButton = document.getElementById('capture');
const clearButton = document.getElementById('clear');
const statusEl = document.getElementById('status');
const summaryEl = document.getElementById('summary');
const previewEl = document.getElementById('preview');
const emptyStateEl = document.getElementById('empty-state');
const rowsEl = document.getElementById('rows');
const payPeriodEl = document.getElementById('pay-period');
const countEl = document.getElementById('count');
const updatedEl = document.getElementById('updated');

function labelType(type) {
  return ({
    regular: 'Shift',
    overtime: 'Overtime',
    annualLeave: 'OFF',
    sickLeave: 'SL',
    holidayLeave: 'HL',
    dayOff: 'OFF',
  })[type] || type;
}

function localIsoDate() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function formatDate(iso) {
  const [year, month, day] = iso.split('-').map(Number);
  const date = new Date(year, month - 1, day);
  return new Intl.DateTimeFormat(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  }).format(date);
}

function formatUpdated(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(date);
}

function formatShiftDetails(item) {
  if (item.shiftType === 'dayOff') return 'Day off';
  if (item.shiftType === 'annualLeave') return 'Annual leave';
  if (item.shiftType === 'sickLeave') return 'Sick leave';
  if (item.shiftType === 'holidayLeave') return 'Holiday leave';

  const details = [];
  if (item.shiftType === 'overtime') details.push('OT');
  if (item.isSupervisor) details.push('Supervisor');
  if (item.isCic) details.push('CIC');
  if (item.flexType === 'late') details.push('Late flex');
  if (item.flexType === 'quarter') details.push('Q flex');
  if (item.overtimeBeforeMinutes) details.push(`${item.overtimeBeforeMinutes / 60}h OT before`);
  if (item.overtimeAfterMinutes) details.push(`${item.overtimeAfterMinutes / 60}h OT after`);
  return details.join(' • ') || 'Regular shift';
}

function renderRows(items) {
  rowsEl.textContent = '';
  const today = localIsoDate();

  for (const item of items) {
    const row = document.createElement('div');
    row.className = 'row';
    if (item.date === today) row.classList.add('today');

    const dateBlock = document.createElement('div');
    dateBlock.className = 'date-block';
    const date = document.createElement('strong');
    date.textContent = formatDate(item.date);
    const todayMark = document.createElement('span');
    todayMark.className = 'today-mark';
    todayMark.textContent = item.date === today ? 'TODAY' : '';
    dateBlock.append(todayMark, date);

    const shiftBlock = document.createElement('div');
    shiftBlock.className = 'shift-block';
    const primary = document.createElement('strong');
    primary.textContent = labelType(item.shiftType);
    const detail = document.createElement('span');
    detail.textContent = formatShiftDetails(item);
    shiftBlock.append(primary, detail);

    const timeBlock = document.createElement('div');
    timeBlock.className = 'time-block';
    const time = document.createElement('strong');
    time.textContent = item.startMinutes == null ? '—' : window.WmtParser.formatMinutes(item.startMinutes);
    const raw = document.createElement('span');
    raw.textContent = item.raw;
    timeBlock.append(time, raw);

    row.append(dateBlock, shiftBlock, timeBlock);
    rowsEl.appendChild(row);
  }
}

function renderSavedSchedule(saved, { announce = false } = {}) {
  const items = saved?.entries || [];
  if (!items.length) {
    summaryEl.hidden = true;
    previewEl.hidden = true;
    emptyStateEl.hidden = false;
    return;
  }

  payPeriodEl.textContent = saved.selectedPayPeriod || 'Saved schedule';
  countEl.textContent = String(items.length);
  updatedEl.textContent = formatUpdated(saved.capturedAt);
  renderRows(items);

  summaryEl.hidden = false;
  previewEl.hidden = false;
  emptyStateEl.hidden = true;

  if (announce) {
    statusEl.className = 'status good';
    statusEl.textContent = `Schedule updated locally with ${items.length} entries.`;
  }
}

async function loadSavedSchedule() {
  const stored = await browser.storage.local.get('lastWmtCapture');
  const saved = stored.lastWmtCapture;
  renderSavedSchedule(saved);
  if (saved?.entries?.length) {
    statusEl.className = 'status';
    statusEl.textContent = 'Showing your last locally saved schedule. Open WMT only when you want to refresh it.';
  }
}

captureButton.addEventListener('click', async () => {
  captureButton.disabled = true;
  statusEl.className = 'status';
  statusEl.textContent = 'Reading the current tab…';

  try {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    const tab = tabs[0];
    if (!tab?.id) throw new Error('No active browser tab found.');

    const results = await browser.tabs.executeScript(tab.id, { file: '/capture.js' });
    const capture = results?.[0];
    if (!capture) throw new Error('Firefox did not return page data.');

    if (capture.pageKind !== 'schedule') {
      statusEl.className = 'status warn';
      statusEl.textContent = capture.pageKind === 'wmt-home'
        ? 'WMT is open, but this is not the Individual Schedule page yet.'
        : 'This does not look like the WMT Individual Schedule page.';
      return;
    }

    const items = window.WmtParser.extract(capture.html);
    if (!items.length) {
      statusEl.className = 'status warn';
      statusEl.textContent = 'WMT schedule page detected, but no dated shift entries were parsed.';
      return;
    }

    const saved = {
      schemaVersion: 1,
      capturedAt: capture.capturedAt,
      selectedPayPeriod: capture.selectedPayPeriod,
      sourceUrl: capture.url,
      entries: items,
    };

    await browser.storage.local.set({ lastWmtCapture: saved });
    renderSavedSchedule(saved, { announce: true });
  } catch (error) {
    statusEl.className = 'status error';
    statusEl.textContent = `Capture failed: ${error?.message || error}`;
  } finally {
    captureButton.disabled = false;
  }
});

clearButton.addEventListener('click', async () => {
  await browser.storage.local.remove('lastWmtCapture');
  renderSavedSchedule(null);
  statusEl.className = 'status';
  statusEl.textContent = 'Saved schedule cleared from Firefox local storage.';
});

loadSavedSchedule().catch((error) => {
  statusEl.className = 'status error';
  statusEl.textContent = `Could not load saved schedule: ${error?.message || error}`;
});
