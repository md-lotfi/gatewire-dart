## 1.0.12

- Fixed Android 14+ (API 34+) crash in `ussd_launcher`'s `UssdOverlayService` (`MissingForegroundServiceTypeException`) — patched automatically via manifest merger; no changes needed in consuming apps
- Native overlay (`overlayMessage`) now only starts when explicitly requested, preventing the crash for callers who don't use it
- Added `UssdSessionBanner` widget — ready-made top-anchored Flutter overlay for the USSD session; no extra permissions required
- Added `PnvSession.phonePattern` — server-provided regex for early-exit phone number detection in USSD responses
- `dialAndVerify()` now exits the USSD session early when any carrier response contains a phone number, saving 4–7 seconds on operators that include the number in the first response (e.g. Ooredoo Algeria)
- Added `ServicesService` with `fetchCatalog()` and `isPnvAvailableOnThisDevice` for service discovery
- Raised Flutter SDK minimum to `>=3.0.0`

## 1.0.11

Added PNV support
