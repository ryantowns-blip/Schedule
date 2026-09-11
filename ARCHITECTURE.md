# ATC Schedule Manager Architecture

This repository intentionally preserves two app architectures in parallel.

## 1. Current WMT-capable app

The existing application line remains preserved on the existing version branches, including `v0.9.0-stabilization` and its predecessors. This version may access WMT directly through the in-app browser/login flow.

Do not remove, overwrite, or repurpose this line when developing the extension-based architecture.

## 2. Extension-fed app architecture

Development branch: `integration/extension-to-app`

The future extension-fed app must have **no direct access to FAA/WMT systems**. It must not contain:

- WMT URLs
- FAA/MyAccess credential handling
- WMT login automation
- authenticated WMT HTTP requests
- embedded WMT browser automation

Instead, the Firefox extension is the only component that reads the user's already-authenticated WMT page.

Target data flow:

`WMT in Firefox -> Firefox extension -> local structured handoff -> ATC Schedule Manager receiver app -> calendar`

The receiver app may validate, store, display, color-code, detect conflicts, and sync received schedule/leave data to user-selected calendars.

## Repository separation

- Existing Flutter app code/branches remain intact.
- Firefox prototype lives under `firefox-extension/` and on `prototype/firefox-android-extension`.
- Cross-component integration work lives on `integration/extension-to-app`.
- A dedicated receiver-app implementation should be created separately rather than deleting WMT functionality from the existing app.

This separation is intentional so both approaches remain available for testing and comparison.
