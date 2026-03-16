import 'package:flutter/material.dart';
import 'package:gatewire_dart/gatewire_dart.dart';

import 'ussd_tester_screen.dart';

// Replace with your API key from https://gatewire.net
const _apiKey = 'YOUR_API_KEY';

final _gatewire = GateWireClient(apiKey: _apiKey);

/// Primary example screen — demonstrates the full phone verification flow
/// using the GateWire SDK.
///
/// On **Android**, [GateWireClient.verifyPhone] performs PNV (USSD carrier
/// dial) automatically. On **iOS / other platforms**, or when USSD fails, it
/// falls back to OTP via SMS and shows a code-entry step.
///
/// Long-press the app bar title to open the developer USSD tester.
class VerificationDemoScreen extends StatefulWidget {
  const VerificationDemoScreen({super.key});

  @override
  State<VerificationDemoScreen> createState() => _VerificationDemoScreenState();
}

class _VerificationDemoScreenState extends State<VerificationDemoScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _loading = false;
  String? _dialingCode;       // shown while USSD dialing (PNV)
  PhoneVerificationResult? _verifyResult;
  String? _otpConfirmStatus;  // result after verifyOtp()
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
        _loading = false;
        _dialingCode = null;
        _verifyResult = null;
        _otpConfirmStatus = null;
        _error = null;
        _otpController.clear();
      });

  Future<void> _verifyPhone() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    _reset();
    setState(() => _loading = true);
    try {
      final result = await _gatewire.verifyPhone(
        phoneNumber: phone,
        onSessionCreated: (session) {
          // Called on Android before the USSD dialog appears.
          setState(() => _dialingCode = session.ussdCode);
        },
      );
      setState(() {
        _verifyResult = result;
        _loading = false;
        _dialingCode = null;
      });
    } on GateWireException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
        _dialingCode = null;
      });
    }
  }

  Future<void> _confirmOtp() async {
    final code = _otpController.text.trim();
    final referenceId = _verifyResult?.referenceId;
    if (code.isEmpty || referenceId == null) return;
    setState(() => _loading = true);
    try {
      final result = await _gatewire.verifyOtp(referenceId: referenceId, code: code);
      setState(() {
        _otpConfirmStatus = result.status;
        _loading = false;
      });
    } on GateWireException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
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
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Android: verified instantly via USSD (no SMS needed).\n'
              'iOS / fallback: an OTP code is sent by SMS.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
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
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _verifyPhone,
                icon: const Icon(Icons.verified_user),
                label: const Text('Verify Phone'),
              ),
            ),

            // ── Loading / dialing indicator ─────────────────────────────────
            if (_loading) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
              if (_dialingCode != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Dialing $_dialingCode…',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                  ),
                ),
              ],
            ],

            // ── Error ───────────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 20),
              _StatusCard(
                color: Colors.red.shade50,
                borderColor: Colors.red.shade200,
                icon: Icons.error_outline,
                iconColor: Colors.red,
                title: 'Error',
                body: _error!,
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _reset, child: const Text('Try again')),
            ],

            // ── PNV result ──────────────────────────────────────────────────
            if (_verifyResult != null && _verifyResult!.method == VerificationMethod.pnv) ...[
              const SizedBox(height: 20),
              _StatusCard(
                color: _verifyResult!.verified == true
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderColor: _verifyResult!.verified == true
                    ? Colors.green.shade200
                    : Colors.orange.shade200,
                icon: _verifyResult!.verified == true
                    ? Icons.check_circle_outline
                    : Icons.cancel_outlined,
                iconColor: _verifyResult!.verified == true ? Colors.green : Colors.orange,
                title: _verifyResult!.verified == true ? 'Verified' : 'Not verified',
                body: '${_verifyResult!.message}\n\nMethod: PNV (USSD)',
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _reset, child: const Text('Start over')),
            ],

            // ── OTP entry step ──────────────────────────────────────────────
            if (_verifyResult != null && _verifyResult!.method == VerificationMethod.otp) ...[
              const SizedBox(height: 20),
              _StatusCard(
                color: Colors.blue.shade50,
                borderColor: Colors.blue.shade200,
                icon: Icons.sms_outlined,
                iconColor: Colors.blue,
                title: 'OTP sent',
                body: _verifyResult!.message,
              ),
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
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _confirmOtp,
                  child: const Text('Confirm Code'),
                ),
              ),
              if (_otpConfirmStatus != null) ...[
                const SizedBox(height: 16),
                _StatusCard(
                  color: Colors.green.shade50,
                  borderColor: Colors.green.shade200,
                  icon: Icons.check_circle_outline,
                  iconColor: Colors.green,
                  title: 'OTP verified',
                  body: 'Status: $_otpConfirmStatus\nMethod: OTP (SMS)',
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _reset, child: const Text('Start over')),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
