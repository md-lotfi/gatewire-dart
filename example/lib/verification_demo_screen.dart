import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gatewire_dart/gatewire_dart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ussd_launcher/ussd_launcher.dart';

import 'ussd_tester_screen.dart';

// Replace with your API key from https://gatewire.net
const _apiKey = '115|Adnbx94nJ3X7WPdp944DeeKHYmMxfeu5Vlmi6oKs9160c83f';

final _gatewire = GateWireClient(apiKey: _apiKey);

/// Primary example screen — demonstrates the full phone verification flow
/// using the GateWire SDK.
///
/// On **Android**, PNV is performed step-by-step with full debug logging.
/// On **iOS / other platforms**, falls back to OTP via SMS.
///
/// Long-press the app bar title to open the developer USSD tester.
class VerificationDemoScreen extends StatefulWidget {
  const VerificationDemoScreen({super.key});

  @override
  State<VerificationDemoScreen> createState() => _VerificationDemoScreenState();
}

class _VerificationDemoScreenState extends State<VerificationDemoScreen>
    with WidgetsBindingObserver {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _loading = false;
  String? _otpReferenceId;
  String? _otpConfirmStatus;
  String? _error;
  final List<_LogEntry> _logs = [];

  // Set when we're waiting for the user to enable accessibility and return.
  Completer<void>? _accessibilityCompleter;

  // Flutter-layer full-screen barrier shown during the USSD session.
  OverlayEntry? _ussdBarrier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UssdLauncher.removeUssdMessageListener();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// Called whenever the app returns to the foreground.
  /// If we're waiting for the user to enable the Accessibility Service,
  /// re-check and unblock the PNV flow if it's now enabled.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final completer = _accessibilityCompleter;
    if (completer == null || completer.isCompleted) return;
    UssdLauncher.isAccessibilityEnabled().then((enabled) {
      if (enabled && !completer.isCompleted) completer.complete();
    });
  }

  /// Shows a full-screen Flutter barrier over the app while the USSD session
  /// is running. This covers the Flutter layer completely and signals the user
  /// not to interact with the appearing system USSD dialogs.
  void _showUssdBarrier(String ussdCode) {
    _ussdBarrier = OverlayEntry(
      builder: (_) => UssdSessionBanner(ussdCode: ussdCode),
    );
    Overlay.of(context).insert(_ussdBarrier!);
  }

  void _hideUssdBarrier() {
    _ussdBarrier?.remove();
    _ussdBarrier = null;
  }

  /// Ensures the Accessibility Service is enabled before dialing.
  ///
  /// If not enabled, shows a blocking dialog that opens system settings.
  /// Waits (without polling) for the user to return to the app with the
  /// service enabled, then resolves. Returns false if the user cancels.
  Future<bool> _ensureAccessibility() async {
    if (await UssdLauncher.isAccessibilityEnabled()) return true;

    if (!mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.accessibility_new, size: 36),
        title: const Text('Accessibility required'),
        content: const Text(
          'To verify your phone number via USSD, the GateWire '
          'Accessibility Service must be enabled once.\n\n'
          'Tap "Open Settings", then:\n'
          '  1. Tap Installed apps\n'
          '  2. Tap gatewire_example\n'
          '  3. Toggle ON\n\n'
          'Return to this app — verification will start automatically.',
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
    _log(
      '⏳ Waiting for Accessibility Service to be enabled…',
      level: _LogLevel.warning,
    );

    // Unblocked by didChangeAppLifecycleState when the user returns.
    await _accessibilityCompleter!.future;
    _accessibilityCompleter = null;

    final enabled = await UssdLauncher.isAccessibilityEnabled();
    if (!enabled) {
      _log(
        '❌ Accessibility Service still not enabled — cancelled',
        level: _LogLevel.error,
      );
      return false;
    }
    _log(
      '✓ Accessibility Service enabled — continuing…',
      level: _LogLevel.success,
    );
    return true;
  }

  void _reset() => setState(() {
    _loading = false;
    _otpReferenceId = null;
    _otpConfirmStatus = null;
    _error = null;
    _logs.clear();
    _otpController.clear();
  });

  void _log(String text, {_LogLevel level = _LogLevel.info}) {
    setState(() => _logs.add(_LogEntry(text, level)));
    debugPrint('[GateWire Demo] $text');
  }

  Future<bool> _ensureCallPermission() async {
    final status = await Permission.phone.request();
    if (status.isGranted) return true;
    _log(
      '❌ CALL_PHONE permission denied — grant it in Settings → Apps → Permissions',
      level: _LogLevel.error,
    );
    if (status.isPermanentlyDenied) openAppSettings();
    return false;
  }

  Future<void> _verifyPhone() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    _reset();
    setState(() => _loading = true);

    try {
      _log('── Starting verification for $phone');

      // ── Step 1: Initiate PNV session ─────────────────────────────────────
      _log('→ POST /pnv/initiate  { phone_number: "$phone" }');
      final session = await _gatewire.pnv.initiate(phoneNumber: phone);
      _log(
        '← 201 Session created\n'
        '   reference_id : ${session.referenceId}\n'
        '   operator     : ${session.operatorName} (${session.countryCode})\n'
        '   ussd_code    : ${session.ussdCode}\n'
        '   expires_at   : ${session.expiresAt.toIso8601String()}',
        level: _LogLevel.success,
      );

      if (!await _ensureCallPermission()) {
        setState(() => _loading = false);
        return;
      }

      if (!await _ensureAccessibility()) {
        setState(() => _loading = false);
        return;
      }

      // ── Step 2: Parse USSD code → base + menu options ────────────────────
      final parsed = _parseUssdCode(session.ussdCode);
      _log(
        '── USSD parse: "${session.ussdCode}"\n'
        '   base    : ${parsed.base}\n'
        '   options : ${parsed.options}',
      );

      // ── Step 3: Register listener BEFORE dialing ─────────────────────────
      // Sentinels are control strings emitted by the plugin via over() to
      // signal session lifecycle events — they are NOT carrier USSD text.
      const sentinels = {
        'SESSION_COMPLETED',
        'ACCESSIBILITY_NOT_ENABLED',
        'ACCESSIBILITY_OR_OVERLAY_NOT_ENABLED',
        'BAD_MAPPING_STRUCTURE',
        'EMPTY_USSD_CODE',
      };
      bool isSentinel(String msg) =>
          sentinels.contains(msg) ||
          msg.startsWith('SESSION_END_ERROR:') ||
          msg.startsWith('SEND_OPTION_ERROR:') ||
          msg.startsWith('DIAL_ERROR:');

      String lastCarrierResponse = '';
      final List<String> allCarrierMessages = [];

      // Completer fires when SESSION_COMPLETED sentinel is received,
      // guaranteeing all prior responseInvoke callbacks have been delivered.
      final sessionDone = Completer<void>();

      UssdLauncher.setUssdMessageListener((msg) {
        allCarrierMessages.add(msg);
        if (isSentinel(msg)) {
          _log(
            '📡 Plugin sentinel #${allCarrierMessages.length}: "$msg"',
            level: _LogLevel.warning,
          );
          if (msg == 'SESSION_COMPLETED' && !sessionDone.isCompleted) {
            sessionDone.complete();
          } else if (!sessionDone.isCompleted) {
            // Error sentinel — also unblock
            sessionDone.completeError(msg);
          }
        } else {
          _log(
            '📨 Carrier response #${allCarrierMessages.length}:\n   $msg',
            level: _LogLevel.carrier,
          );
          lastCarrierResponse = msg; // only update on real carrier text
        }
      });

      // ── Step 4: Dial via multisessionUssd ────────────────────────────────
      _log(
        '── Dialing ${parsed.base} with options ${parsed.options} '
        '(slot 0, delay 4000/2500ms)…',
      );

      // Show Flutter-layer full-screen barrier so the user cannot interact
      // with the app while USSD dialogs are appearing and being auto-filled.
      _showUssdBarrier(session.ussdCode);

      try {
        await UssdLauncher.multisessionUssd(
          code: parsed.base,
          options: parsed.options,
          slotIndex: 0,
          initialDelayMs: 4000,
          optionDelayMs: 2500,
          // NOTE: overlayMessage is intentionally omitted. The plugin starts a
          // foreground service for its native overlay, which crashes on Android
          // 14+ (API 34+) because UssdOverlayService lacks a foregroundServiceType
          // declaration. Our Flutter _UssdBarrier already covers the app layer.
        );
        _log(
          '── multisessionUssd() future resolved — waiting for SESSION_COMPLETED…',
        );

        // Wait for SESSION_COMPLETED to ensure all responseInvoke callbacks
        // have been delivered. The plugin emits SESSION_COMPLETED AFTER the
        // future resolves due to a handler.post race — a fixed delay is not
        // reliable. Timeout after 8s in case the sentinel never arrives.
        await sessionDone.future.timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            _log(
              '⚠ SESSION_COMPLETED not received within 8s — proceeding anyway',
              level: _LogLevel.warning,
            );
          },
        );
        _log('── Session fully complete', level: _LogLevel.success);
      } on PlatformException catch (e) {
        _log(
          '❌ multisessionUssd threw: [${e.code}] ${e.message}',
          level: _LogLevel.error,
        );
        UssdLauncher.removeUssdMessageListener();
        _hideUssdBarrier();
        setState(() {
          _error = 'USSD dial failed: ${e.message}';
          _loading = false;
        });
        return;
      } finally {
        _hideUssdBarrier();
        UssdLauncher.removeUssdMessageListener();
      }

      final summary = StringBuffer('── Listener summary:\n');
      summary.writeln('   total messages : ${allCarrierMessages.length}');
      for (var i = 0; i < allCarrierMessages.length; i++) {
        final msg = allCarrierMessages[i];
        final tag = isSentinel(msg) ? '⚡sentinel' : '📨 carrier';
        summary.write(
          '   #${i + 1} [$tag] : "${msg.length > 120 ? '${msg.substring(0, 120)}…' : msg}"',
        );
        if (i < allCarrierMessages.length - 1) summary.writeln();
      }
      _log(summary.toString());

      if (lastCarrierResponse.isEmpty) {
        _log(
          '❌ No carrier response captured — cannot verify',
          level: _LogLevel.error,
        );
        setState(() {
          _error = 'No USSD response received from carrier.';
          _loading = false;
        });
        return;
      }

      // ── Step 5: Send USSD response to backend ────────────────────────────
      _log(
        '→ POST /pnv/verify\n'
        '   reference_id  : ${session.referenceId}\n'
        '   ussd_response : "$lastCarrierResponse"',
      );

      final result = await _gatewire.pnv.verify(
        referenceId: session.referenceId,
        ussdResponse: lastCarrierResponse,
      );

      _log(
        '← 200 Verify response\n'
        '   verified : ${result.verified}\n'
        '   message  : ${result.message}',
        level: result.verified ? _LogLevel.success : _LogLevel.warning,
      );

      setState(() => _loading = false);
    } on GateWireException catch (e) {
      _log(
        '❌ GateWireException\n'
        '   code       : ${e.code ?? "—"}\n'
        '   statusCode : ${e.statusCode ?? "—"}\n'
        '   message    : ${e.message}',
        level: _LogLevel.error,
      );
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e, st) {
      _log('❌ Unexpected error: $e\n$st', level: _LogLevel.error);
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    _reset();
    setState(() => _loading = true);
    _log('── Sending OTP to $phone');
    _log('→ POST /send-otp  { phone: "$phone" }');
    try {
      final dispatch = await _gatewire.dispatch(phone: phone);
      _log(
        '← OTP dispatched\n'
        '   reference_id : ${dispatch.referenceId}\n'
        '   status       : ${dispatch.status}',
        level: _LogLevel.success,
      );
      setState(() {
        _otpReferenceId = dispatch.referenceId;
        _loading = false;
      });
    } on GateWireException catch (e) {
      _log('❌ ${e.message}', level: _LogLevel.error);
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _confirmOtp() async {
    final code = _otpController.text.trim();
    if (code.isEmpty || _otpReferenceId == null) return;
    setState(() => _loading = true);
    _log(
      '→ POST /verify-otp  { reference_id: "$_otpReferenceId", code: "$code" }',
    );
    try {
      final result = await _gatewire.verifyOtp(
        referenceId: _otpReferenceId!,
        code: code,
      );
      _log(
        '← OTP verify response\n'
        '   status  : ${result.status}\n'
        '   message : ${result.message}',
        level: _LogLevel.success,
      );
      setState(() {
        _otpConfirmStatus = result.status;
        _loading = false;
      });
    } on GateWireException catch (e) {
      _log('❌ ${e.message}', level: _LogLevel.error);
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  ({String base, List<String> options}) _parseUssdCode(String code) {
    final inner = code.replaceFirst('*', '').replaceAll('#', '');
    final parts = inner.split('*');
    return (
      base: '*${parts.first}#',
      options: parts.length > 1 ? parts.sublist(1) : <String>[],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        title: GestureDetector(
          onLongPress: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UssdTesterScreen()),
          ),
          child: const Text('GateWire SDK Demo'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Text(
              'Phone Verification',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Android: PNV via USSD carrier dial.\niOS / fallback: OTP by SMS.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),

            // ── Phone input ─────────────────────────────────────────────────
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '+213770123456',
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _verifyPhone,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('PNV (USSD)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _loading ? null : _sendOtp,
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Send OTP'),
                  ),
                ),
              ],
            ),

            // ── Loading ─────────────────────────────────────────────────────
            if (_loading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],

            // ── OTP entry ───────────────────────────────────────────────────
            if (_otpReferenceId != null && _otpConfirmStatus == null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Enter the 6-digit code',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              FilledButton(
                onPressed: _loading ? null : _confirmOtp,
                child: const Text('Confirm Code'),
              ),
            ],

            // ── Error banner ────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 12),
              _StatusBanner(
                color: Colors.red.shade50,
                borderColor: Colors.red.shade200,
                icon: Icons.error_outline,
                iconColor: Colors.red,
                title: 'Error',
                body: _error!,
              ),
              TextButton(onPressed: _reset, child: const Text('Try again')),
            ],

            if (_otpConfirmStatus != null) ...[
              const SizedBox(height: 12),
              _StatusBanner(
                color: Colors.green.shade50,
                borderColor: Colors.green.shade200,
                icon: Icons.check_circle_outline,
                iconColor: Colors.green,
                title: 'OTP verified',
                body: 'Status: $_otpConfirmStatus',
              ),
              TextButton(onPressed: _reset, child: const Text('Start over')),
            ],

            // ── Debug log panel ─────────────────────────────────────────────
            if (_logs.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    'Debug log',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _reset, child: const Text('Clear')),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText.rich(
                  TextSpan(
                    children: _logs
                        .map(
                          (e) => TextSpan(
                            text: '${e.text}\n',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              height: 1.6,
                              color: e.level.color,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Log model ────────────────────────────────────────────────────────────────

enum _LogLevel { info, success, warning, error, carrier }

extension on _LogLevel {
  Color get color => switch (this) {
    _LogLevel.info => const Color(0xFFD4D4D4),
    _LogLevel.success => const Color(0xFF6ECE6E),
    _LogLevel.warning => const Color(0xFFE5C07B),
    _LogLevel.error => const Color(0xFFE06C75),
    _LogLevel.carrier => const Color(0xFF61AFEF),
  };
}

class _LogEntry {
  const _LogEntry(this.text, this.level);
  final String text;
  final _LogLevel level;
}

// ── Status banner ────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(body, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
