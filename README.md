# GateWire Flutter SDK

The official Flutter plugin for the **[GateWire SMS Infrastructure](https://gatewire.net)**.

Easily integrate SMS notifications, OTPs, and alerts into your Flutter Android & iOS applications using our decentralized mesh network.

## Features

* 🚀 **Cross-Platform:** Works on Android, iOS, Web, and Desktop.
* 🇩🇿 **Local Optimized:** Designed for reliable delivery to Mobilis, Djezzy, and Ooredoo.
* 🛡️ **Type Safe:** Full typed models for responses and errors.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  gatewire: ^1.0.11
```

## Usage
### 1. Initialization

```dart
import 'package:gatewire_dart/gatewire_dart.dart';

final gatewire = GateWireClient(apiKey: 'sk_live_YOUR_KEY_HERE');
```

### 2. Sending an OTP

```dart
try {
  final response = await gatewire.dispatch(
    phone: '+213555123456', 
  );
  
  print('SMS Sent! Ref ID: ${response.referenceId}');
  
} on GateWireException catch (e) {
  print('Failed: ${e.message}');
}
```

### 3. Using Templates (Recommended)
Templates allow you to skip the standard queue (Priority Route).

```dart
final response = await gatewire.dispatch(
  phone: '+213555123456',
  templateKey: 'login_otp', // Example configured in client dashboard
);
```

### 4. Verify a CODE

```dart
try {
  final response = await gatewire.verifyOtp(
    referenceId: 'REFERENCE_ID_KEY',
    code: 'VERFICATION_CODE' 
  );
  
  print('Verification response : ${response.message}, ${response.status}');
  
} on GateWireException catch (e) {
  print('Failed: ${e.message}');
}
```

## Platform-aware verification (recommended)

Use `verifyPhone()` when you want a single call that automatically picks the best method for the platform — no `if (Platform.isAndroid)` in your app code.

```dart
final result = await gatewire.verifyPhone(
  phoneNumber: '+213770123456',
  onSessionCreated: (s) {
    // Android only — fires before the USSD dialog appears.
    print('Dialing ${s.ussdCode} via ${s.operatorName}...');
  },
);

if (result.method == VerificationMethod.pnv) {
  // Android — phone verified immediately via USSD.
  print('Verified: ${result.verified}');
} else {
  // iOS / other — OTP SMS was sent; ask the user for the code.
  final code = await promptUserForCode();
  final otpResult = await gatewire.verifyOtp(
    referenceId: result.referenceId!,
    code: code,
  );
  print('OTP verified: ${otpResult.status}');
}
```

| Platform | Method used | `result.verified` | `result.referenceId` |
|----------|-------------|-------------------|----------------------|
| Android  | PNV (USSD)  | `true` / `false`  | `null`               |
| iOS / other | OTP (SMS) | `null` (pending) | OTP session ID      |

## Phone Number Verification (PNV)

PNV verifies that a user owns their phone number by dialing a USSD code directly on the device — no SMS is sent and no code needs to be typed.

> **Android only.** USSD is a carrier-level feature. Calling `dialAndVerify` on iOS, web, or desktop will throw a `GateWireException` immediately.

### Prerequisites — Accessibility Service

`ussd_launcher` reads the carrier's USSD response dialog using Android's **Accessibility Service**. Without it the USSD code can be dialed but the response string cannot be captured, so verification will fail.

#### Step 1 — Declare the service in your app's Android manifest

Your app will **not appear** in the system Accessibility list until it explicitly registers an `AccessibilityService`. This is required — Android will not list apps that haven't declared one.

**Create** `android/app/src/main/res/xml/accessibility_service_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:description="@string/accessibility_service_description"
    android:accessibilityEventTypes="typeWindowStateChanged|typeWindowContentChanged"
    android:accessibilityFlags="flagReportViewIds|flagRequestFilterKeyEvents"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:notificationTimeout="100"
    android:canRetrieveWindowContent="true"
    android:canPerformGestures="true" />
```

**Add inside `<application>` in** `android/app/src/main/AndroidManifest.xml`:

```xml
<service
    android:name="com.kavina.ussd_launcher.UssdAccessibilityService"
    android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
    android:exported="false">
    <intent-filter>
        <action android:name="android.accessibilityservice.AccessibilityService" />
    </intent-filter>
    <meta-data
        android:name="android.accessibilityservice"
        android:resource="@xml/accessibility_service_config" />
</service>
```

**Add inside `<manifest>`:**

```xml
<uses-permission android:name="android.permission.CALL_PHONE" />
```

**Add to** `android/app/src/main/res/values/strings.xml` (create if missing):

```xml
<resources>
    <string name="app_name">YourAppName</string>
    <string name="accessibility_service_description">
        Required to capture USSD responses for phone number verification.
    </string>
</resources>
```

Then do a clean rebuild:

```bash
flutter clean && flutter run
```

#### Step 2 — Check and guide the user at runtime

The Accessibility Service cannot be requested programmatically like a normal permission. Use `UssdLauncher.isAccessibilityEnabled()` to check, then open the system settings screen if needed.

The recommended pattern uses `WidgetsBindingObserver` to detect when the user returns from Settings and re-checks automatically — no polling required:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ussd_launcher/ussd_launcher.dart';

class _MyScreenState extends State<MyScreen> with WidgetsBindingObserver {
  Completer<void>? _accessibilityCompleter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Auto-unblocks the PNV flow when the user returns from Settings
  /// with the service now enabled.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final c = _accessibilityCompleter;
    if (c == null || c.isCompleted) return;
    UssdLauncher.isAccessibilityEnabled().then((enabled) {
      if (enabled && !c.isCompleted) c.complete();
    });
  }

  /// Returns true when ready to dial, false if the user cancelled.
  Future<bool> _ensureAccessibility() async {
    if (await UssdLauncher.isAccessibilityEnabled()) return true;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.accessibility_new, size: 36),
        title: const Text('Accessibility required'),
        content: const Text(
          'To verify your number via USSD, enable the Accessibility '
          'Service once.\n\n'
          'Settings → Accessibility → Installed apps → '
          '<Your App> → toggle ON\n\n'
          'Return here after enabling — verification starts automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (proceed != true) return false;

    _accessibilityCompleter = Completer<void>();
    await UssdLauncher.openAccessibilitySettings();

    // Wait for the user to enable the service and return to the app.
    await _accessibilityCompleter!.future;
    _accessibilityCompleter = null;

    return UssdLauncher.isAccessibilityEnabled();
  }
}
```

> **Important:** Enabling an Accessibility Service causes Android to restart the app process. During development (`flutter run`) this drops the debug connection — this is expected. In a production APK the restart is invisible to the user. Enable the service once **before** starting a `flutter run` session to avoid the reconnect step.

> **Samsung One UI (Android 13+):** the path is
> **Settings → Accessibility → Installed apps → Your App → toggle on**

#### Showing a "Do not touch" banner during the USSD session

Android USSD dialogs are system-level windows that appear above all app content and **cannot be hidden or blocked** by the app. The recommended UX is to show a compact banner pinned to the top of the screen before dialing — it remains visible above the app layer while the USSD dialog appears in the centre/bottom.

The SDK ships a ready-made `UssdSessionBanner` widget — no custom widget needed:

```dart
import 'package:gatewire_dart/gatewire_dart.dart';

OverlayEntry? _ussdBanner;

void _showBanner(String ussdCode) {
  _ussdBanner = OverlayEntry(
    builder: (_) => UssdSessionBanner(ussdCode: ussdCode),
  );
  Overlay.of(context).insert(_ussdBanner!);
}

void _hideBanner() {
  _ussdBanner?.remove();
  _ussdBanner = null;
}
```

Always remove it in a `finally` block:

```dart
_showBanner(session.ussdCode);
try {
  await UssdLauncher.multisessionUssd(...);
  // wait for SESSION_COMPLETED ...
} finally {
  _hideBanner();
  UssdLauncher.removeUssdMessageListener();
}
```

`UssdSessionBanner` renders a dark animated card at the top of the screen with a pulsing shield icon and a progress bar while the USSD session runs.

> **Do NOT pass `overlayMessage`** to `multisessionUssd()`. The plugin's native overlay starts a foreground service that crashes on Android 14+ (API 34+) because `UssdOverlayService` lacks a required `foregroundServiceType` declaration. Use `UssdSessionBanner` instead.

**Devices where Accessibility Service may be blocked:**

| Scenario | Behaviour |
|---|---|
| Manifest not configured / first install | App absent from Accessibility list — rebuild required |
| User declines to enable it | USSD response not captured → fall back to OTP |
| Enterprise MDM / managed device | Accessibility Services may be disabled system-wide |
| Some OEM ROMs (e.g. MIUI, HyperOS) | May restrict third-party Accessibility Services |

In all cases the recommended approach is to detect the failure and **silently fall back to OTP** rather than blocking the user.

### One-call flow (Android only)

```dart
try {
  final result = await gatewire.pnv.dialAndVerify(
    phoneNumber: '+213770123456',
    onSessionCreated: (session) {
      // Called before the USSD dialog appears.
      // Use session.ussdCode to show a "Dialing *555#…" indicator.
      print('Dialing ${session.ussdCode} via ${session.operatorName}...');
    },
  );

  if (result.verified) {
    print('Phone verified! ${result.message}');
  } else {
    print('Verification failed: ${result.message}');
  }
} on GateWireException catch (e) {
  // e.code == 'service_disabled' when PNV is not enabled for your account.
  print('PNV error: ${e.message} (status: ${e.statusCode}, code: ${e.code})');
}
```

### Manual two-step flow

```dart
// Step 1 — create a session and get the USSD code.
final session = await gatewire.pnv.initiate(phoneNumber: '+213770123456');
print('Dial ${session.ussdCode} — expires at ${session.expiresAt}');

// … dial session.ussdCode yourself and capture the carrier response string …

// Step 2 — submit the raw USSD response for verification.
final result = await gatewire.pnv.verify(
  referenceId: session.referenceId,
  ussdResponse: rawUssdResponseString,
);
print('Verified: ${result.verified}');
```

## Service Discovery

Check which services are enabled for your API key before showing verification UI.
Results are cached for 5 minutes automatically.

```dart
final catalog = await gatewire.services.fetchCatalog();

if (catalog.otp.enabled) {
  // Show OTP option — works on all platforms.
  print('OTP: ${catalog.otp.pricePerRequestCents} ${catalog.otp.currency} / request');
}

if (catalog.isPnvAvailableOnThisDevice) {
  // Show PNV option — only true when backend-enabled AND running on Android.
  print('PNV: ${catalog.pnv.pricePerRequestCents} ${catalog.pnv.currency} / request');
}
```

`isPnvAvailableOnThisDevice` combines both checks (`pnv.enabled && Platform.isAndroid`) so you never need to write that condition yourself.

To force a refresh (e.g. after the user enables a service in your settings UI):

```dart
gatewire.services.invalidateCache();
final fresh = await gatewire.services.fetchCatalog();
```

### Service-disabled errors

If a service is disabled and you call it anyway, a `GateWireException` is thrown with `code == 'service_disabled'`:

```dart
try {
  await gatewire.dispatch(phone: '+213555123456');
} on GateWireException catch (e) {
  if (e.code == 'service_disabled') {
    print('OTP is not enabled. Visit your dashboard to activate it.');
  }
}
```

## License
The GateWire flutter package is open-sourced software licensed under the MIT license.