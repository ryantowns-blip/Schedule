# Firefox Android WMT Capture Prototype

This folder contains a proof-of-concept Firefox WebExtension for ATC Schedule Manager.

## Prototype goal

Prove that an employee can:

1. Open WMT Scheduler in Firefox and authenticate normally through MyAccess.
2. Navigate to the WMT **Individual Schedule** page.
3. Explicitly tap the ATC Schedule Manager extension.
4. Read only the currently rendered page and parse the visible dated shift entries locally.
5. Preview the captured schedule without sending WMT credentials or schedule data to an external service.

Calendar writes are intentionally **not** included in this first prototype. They should be added only after capture reliability is confirmed.

## Security/privacy design

- No FAA username or password fields exist in the extension.
- No automated MyAccess login.
- No background polling of WMT.
- No remote API/server calls.
- No broad host permission such as `<all_urls>`.
- Firefox `activeTab` access is granted only after the user invokes the extension on the current tab.
- Parsed capture data is saved only to Firefox local extension storage for the latest preview.

## Parser behavior currently mirrored from the app

The JavaScript parser recognizes the same major WMT values currently handled by the Flutter app, including:

- Regular shifts such as `0500`
- `L` and `Q` flex modifiers
- `S` supervisor and `C` CIC markers
- `$` overtime shifts
- `Xtra` before/after and `Xt...ra` split overtime
- `X` day off
- `SL` sick leave
- `HL` holiday leave
- Annual leave such as `A<0500>` and `A<1415L>`

## Files

- `manifest.json` — Firefox extension manifest.
- `capture.js` — runs only on the active tab after the user taps Capture; identifies the WMT page and returns its rendered HTML.
- `parser.js` — local JavaScript port of the app's WMT schedule parsing rules.
- `popup/` — simple mobile-friendly capture/preview UI.

## Android testing

For development, Firefox for Android can be connected to desktop Firefox developer tools with USB remote debugging, then the extension can be loaded temporarily for testing. A normal end-user install will ultimately require packaging/signing through Mozilla's extension distribution process.

The first real-device test should answer three questions:

1. Does Firefox Android load and operate WMT/MyAccess normally?
2. Does the extension identify the Individual Schedule page?
3. Does the parsed preview match every displayed day in the selected pay period?

If those pass, the next prototype step is to collect all available pay periods and add calendar export/sync.
