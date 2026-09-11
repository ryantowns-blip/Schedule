const captureButton = document.getElementById('capture');
const statusEl = document.getElementById('status');
const summaryEl = document.getElementById('summary');
const previewEl = document.getElementById('preview');
const rowsEl = document.getElementById('rows');
const pageKindEl = document.getElementById('page-kind');
const payPeriodEl = document.getElementById('pay-period');
const countEl = document.getElementById('count');

function labelType(type) {
  return ({
    regular: 'Shift',
    overtime: 'Overtime',
    annualLeave: 'Annual leave',
    sickLeave: 'Sick leave',
    holidayLeave: 'Holiday leave',
    dayOff: 'OFF',
  })[type] || type;
}

function renderRows(items) {
  rowsEl.textContent = '';
  for (const item of items) {
    const row = document.createElement('div');
    row.className = 'row';

    const left = document.createElement('div');
    left.className = 'row-main';
    const date = document.createElement('strong');
    date.textContent = item.date;
    const raw = document.createElement('span');
    raw.textContent = item.raw;
    left.append(date, raw);

    const right = document.createElement('div');
    right.className = 'row-meta';
    const type = document.createElement('span');
    type.textContent = labelType(item.shiftType);
    const time = document.createElement('span');
    time.textContent = window.WmtParser.formatMinutes(item.startMinutes);
    right.append(type, time);

    row.append(left, right);
    rowsEl.appendChild(row);
  }
}

captureButton.addEventListener('click', async () => {
  captureButton.disabled = true;
  statusEl.className = 'status';
  statusEl.textContent = 'Reading the current tab…';
  summaryEl.hidden = true;
  previewEl.hidden = true;

  try {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    const tab = tabs[0];
    if (!tab?.id) throw new Error('No active browser tab found.');

    const results = await browser.tabs.executeScript(tab.id, { file: '/capture.js' });
    const capture = results?.[0];
    if (!capture) throw new Error('Firefox did not return page data.');

    pageKindEl.textContent = capture.pageKind;
    payPeriodEl.textContent = capture.selectedPayPeriod || 'Not detected';
    summaryEl.hidden = false;

    if (capture.pageKind !== 'schedule') {
      countEl.textContent = '0';
      statusEl.className = 'status warn';
      statusEl.textContent = capture.pageKind === 'wmt-home'
        ? 'WMT is open, but this is not the Individual Schedule page yet.'
        : 'This does not look like the WMT Individual Schedule page.';
      return;
    }

    const items = window.WmtParser.extract(capture.html);
    countEl.textContent = String(items.length);

    if (!items.length) {
      statusEl.className = 'status warn';
      statusEl.textContent = 'WMT schedule page detected, but no dated shift entries were parsed. This capture is useful for refining the parser.';
      return;
    }

    await browser.storage.local.set({
      lastWmtCapture: {
        capturedAt: capture.capturedAt,
        selectedPayPeriod: capture.selectedPayPeriod,
        sourceUrl: capture.url,
        entries: items,
      },
    });

    renderRows(items);
    previewEl.hidden = false;
    statusEl.className = 'status good';
    statusEl.textContent = `Captured ${items.length} schedule entries locally.`;
  } catch (error) {
    statusEl.className = 'status error';
    statusEl.textContent = `Capture failed: ${error?.message || error}`;
  } finally {
    captureButton.disabled = false;
  }
});
