# GateWire Flutter SDK

The official Flutter plugin for the **[GateWire SMS Infrastructure](https://gatewire.raystate.com)**.

Easily integrate SMS notifications, OTPs, and alerts into your Flutter Android & iOS applications using our decentralized mesh network.

## Features

* 🚀 **Cross-Platform:** Works on Android, iOS, Web, and Desktop.
* 🇩🇿 **Local Optimized:** Designed for reliable delivery to Mobilis, Djezzy, and Ooredoo.
* 🛡️ **Type Safe:** Full typed models for responses and errors.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  gatewire: ^1.0.0
```

## Usage
### 1. Initialization

```dart
import 'package:gatewire/gatewire.dart';

final gatewire = GateWireClient(apiKey: 'sk_live_YOUR_KEY_HERE');
```

### 2. Sending an OTP

```dart
try {
  final response = await gatewire.dispatch(
    phone: '+213555123456', 
    message: 'Your code is: 1234'
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
  templateKey: 'login_otp', // Configured in Dashboard
  priority: true
);
```

### 4. Checking Balance

```dart
final balance = await gatewire.getBalance();
print('Remaining: ${balance.balance} DZD');
```

## License
The GateWire flutter package is open-sourced software licensed under the MIT license.