# ATC Schedule Manager Architecture

This repository currently preserves multiple product paths. They are intentionally kept separate so development on one path does not break or replace another.

## 1. ATC Schedule Manager — full WMT-connected app

Status: preserved / separate development line.

Primary branch lineage includes `v0.9.0-stabilization` and the earlier versioned branches.

Purpose:
- Connect to WMT/MyAccess.
- Read schedule and leave information directly from the FAA/WMT website.
- Display pay periods and leave.
- Sync schedule and leave entries to the user's calendar.

This app keeps the display name **ATC Schedule Manager**.

The screenshot-only Lite branch must not remove or modify this preserved implementation.

## 2. ATC Schedule Manager Lite — active screenshot-import app

Status: active development.

Branch: `v0.10.0-screenshot-import`

Display name: **ATC Schedule Manager Lite**

Android application ID: `com.ryantowns.atcschedulemanager.lite`

Purpose:
- Never log into WMT/MyAccess.
- Never connect to the FAA/WMT website.
- Accept screenshots selected from the user's phone.
- Read schedule and My Leave screenshots locally using on-device OCR.
- Parse recognized dates, shift codes, leave types, and approval status.
- Require review when OCR finds questionable or unresolved text.
- Store imported schedule/leave data locally.
- Display the same style of pay-period schedule view as the full app.
- Sync schedule and approved leave to the user's calendar.

### Lite data flow

1. User selects one or more screenshots.
2. Google ML Kit text recognition runs locally on-device.
3. Screenshot-specific parsers convert OCR text to neutral models.
4. Recognized entries are shown for review/edit/removal.
5. Unresolved schedule/leave text must be acknowledged before import.
6. Reviewed data is stored locally.
7. Calendar sync uses the reviewed local data only.

### Neutral models

Lite uses shared neutral model files such as:
- `lib/models/dated_shift.dart`
- `lib/models/parsed_shift.dart`
- `lib/models/upcoming_leave.dart`

The Lite runtime no longer depends on legacy WMT HTML extractors.

### Calendar identity

Lite-created calendar entries use **ATC Schedule Manager Lite** in their descriptions. Existing entries from older ATC Schedule Manager builds can still be recognized where necessary for duplicate/update handling.

## 3. Firefox extension / receiver architecture

Status: shelved, preserved for possible future work.

Branches:
- `prototype/firefox-android-extension`
- `integration/extension-to-app`

The concept was to have a Firefox extension capture schedule data and transfer it to an app that itself had no FAA/WMT connectivity. This path is not currently being developed because screenshot import became the preferred architecture.

## Development rules

- Keep the full WMT-connected app and Lite as separate installable apps.
- Lite must retain its distinct Android application ID so both apps can be installed side-by-side.
- Keep versioned branches/checkpoints so working builds remain recoverable.
- Do not reintroduce WebView, WMT login, or FAA website connectivity into Lite.
- OCR parsing changes should be covered by regression tests before relying on them in production builds.
- Real WMT screenshots should be used to tune OCR/layout handling as testing progresses.
