(() => {
  const bodyText = (document.body?.innerText || '').replace(/\s+/g, ' ').trim();
  const title = document.title || '';
  const selects = Array.from(document.querySelectorAll('select'));
  const payPeriodSelect = selects.find((select) => {
    const haystack = [
      select.name,
      select.id,
      select.getAttribute('aria-label'),
      select.previousElementSibling?.textContent,
      select.parentElement?.textContent,
    ].filter(Boolean).join(' ');
    return /pay\s*period/i.test(haystack);
  }) || selects.find((select) => /Select Pay Period/i.test(bodyText));

  const selectedPayPeriod = payPeriodSelect?.selectedOptions?.[0]?.textContent?.trim() || null;
  const hasScheduleHeading = /Individual\s+schedule/i.test(bodyText);
  const hasPayPeriodUi = /Select\s+Pay\s+Period/i.test(bodyText) || Boolean(payPeriodSelect);
  const hasWmtBrand = /WMT\s+Scheduler/i.test(bodyText) || /WMT\s+Scheduler/i.test(title);
  const hasViews = Array.from(document.querySelectorAll('a,button,input,[onclick],td,span,div'))
    .some((el) => /^views$/i.test(((el.innerText || el.value || el.textContent || '') + '').trim()));

  let pageKind = 'other';
  if (hasScheduleHeading && hasPayPeriodUi) pageKind = 'schedule';
  else if (hasWmtBrand && hasViews) pageKind = 'wmt-home';

  return {
    pageKind,
    title,
    url: location.href,
    selectedPayPeriod,
    capturedAt: new Date().toISOString(),
    html: document.documentElement?.outerHTML || '',
    text: bodyText,
  };
})();
