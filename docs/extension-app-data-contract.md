# Firefox Extension -> Receiver App Data Contract

This document defines the local structured data format shared between the Firefox extension and the future receiver-only ATC Schedule Manager app.

The receiver app must not access FAA/WMT systems. It receives already captured and parsed schedule data from the extension.

## Schema version 1

```json
{
  "schemaVersion": 1,
  "capturedAt": "2026-09-11T15:30:00.000Z",
  "selectedPayPeriod": "09/06/2026 - 09/19/2026",
  "entries": [
    {
      "date": "2026-09-11",
      "raw": "1400",
      "shiftType": "regular",
      "startMinutes": 840,
      "overtimeBeforeMinutes": 0,
      "overtimeAfterMinutes": 0,
      "flexType": "none",
      "isSupervisor": false,
      "isCic": false
    }
  ]
}
```

## Allowed shift types

- `regular`
- `overtime`
- `annualLeave`
- `sickLeave`
- `holidayLeave`
- `dayOff`

## Display rules

The Firefox schedule viewer and receiver app should interpret the same normalized records consistently:

- `annualLeave` displays as `OFF` in the primary schedule view.
- `dayOff` displays as `OFF`.
- `holidayLeave` displays as `HL`.
- `sickLeave` displays as `SL`.
- `overtime` displays distinctly from a regular shift and can receive its own user-selected color.
- `startMinutes` is minutes after midnight and may be null for leave/day-off records.
- `overtimeBeforeMinutes` and `overtimeAfterMinutes` preserve Xtra/Xt...ra timing.
- `flexType`, `isSupervisor`, and `isCic` preserve WMT shift modifiers without requiring the receiver app to parse WMT syntax.

## Transport requirements

The handoff from extension to app must be local and user initiated.

Preferred transport candidates for Android:

1. Android share intent using a JSON file or structured text payload.
2. App link/deep link for a small transfer token or compact payload.
3. Local file import as a fallback.

Large schedule datasets should use a file/share handoff rather than embedding the entire schedule in a URL.

No FAA credentials, WMT cookies, authentication tokens, page HTML, or MyAccess information may be included in the receiver payload.

The receiver app should validate `schemaVersion`, reject malformed records, and show the user a preview/count before replacing existing stored schedule data.
