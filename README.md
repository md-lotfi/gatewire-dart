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
  gatewire: ^1.0.3
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

### 2. Verify a CODE

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

## Phone Number Verification (PNV)

PNV verifies that a user owns their phone number by dialing a USSD code directly on the device — no SMS is sent and no code needs to be typed.

> **Android only.** USSD is a carrier-level feature. Calling `dialAndVerify` on iOS, web, or desktop will throw a `GateWireException` immediately.

### One-call flow (recommended)

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
  print('PNV error: ${e.message} (code: ${e.statusCode})');
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

## License
The GateWire flutter package is open-sourced software licensed under the MIT license.