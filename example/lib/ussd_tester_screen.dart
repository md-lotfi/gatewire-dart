import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ussd_launcher/ussd_launcher.dart';

/// Internal developer screen for testing raw USSD approaches on a live carrier.
///
/// Access this screen by long-pressing the title on the main demo screen.
/// Not intended as a public-facing feature — used to validate carrier
/// compatibility during SDK development.
class UssdTesterScreen extends StatefulWidget {
  const UssdTesterScreen({super.key});

  @override
  State<UssdTesterScreen> createState() => _UssdTesterScreenState();
}

class _UssdTesterScreenState extends State<UssdTesterScreen> {
  final _approach1Controller = TextEditingController(text: '*113*1*1#');
  final _approach2BaseController = TextEditingController(text: '*113#');
  final _approach2MenuController = TextEditingController(text: '1,1');
  final _simSlotController = TextEditingController(text: '-1');

  bool _loading = false;
  String _log = '';

  @override
  void initState() {
    super.initState();
    UssdLauncher.setUssdMessageListener((message) {
      _appendLog('📨 Carrier response:\n$message');
    });
  }

  @override
  void dispose() {
    UssdLauncher.removeUssdMessageListener();
    _approach1Controller.dispose();
    _approach2BaseController.dispose();
    _approach2MenuController.dispose();
    _simSlotController.dispose();
    super.dispose();
  }

  void _appendLog(String line) => setState(() => _log = '$_log\n$line');
  void _clearLog() => setState(() => _log = '');
  int get _simSlot => int.tryParse(_simSlotController.text.trim()) ?? -1;

  Future<bool> _ensureCallPermission() async {
    var status = await Permission.phone.status;
    if (status.isGranted) return true;
    status = await Permission.phone.request();
    if (status.isGranted) return true;
    _appendLog(
      '❌ Permission denied.\nGrant Phone permission in Settings → Apps → Permissions.',
    );
    if (status.isPermanentlyDenied) openAppSettings();
    return false;
  }

  Future<void> _runApproach1A() async {
    if (!await _ensureCallPermission()) return;
    final code = _approach1Controller.text.trim();
    _clearLog();
    _appendLog('▶ Approach 1-A: dialing $code ...');
    setState(() => _loading = true);
    try {
      final response = await UssdLauncher.sendUssdRequest(
        ussdCode: code,
        subscriptionId: _simSlot,
      );
      _appendLog('✅ Response:\n$response');
    } on PlatformException catch (e) {
      _appendLog('❌ PlatformException\nCode: ${e.code}\nMessage: ${e.message}');
    } catch (e) {
      _appendLog('❌ Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _runApproach1B() async {
    if (!await _ensureCallPermission()) return;
    final code = _approach1Controller.text.trim().replaceAll('#', '%23');
    _clearLog();
    _appendLog('▶ Approach 1-B: dialing $code (# encoded as %23) ...');
    setState(() => _loading = true);
    try {
      final response = await UssdLauncher.sendUssdRequest(
        ussdCode: code,
        subscriptionId: _simSlot,
      );
      _appendLog('✅ Response:\n$response');
    } on PlatformException catch (e) {
      _appendLog('❌ PlatformException\nCode: ${e.code}\nMessage: ${e.message}');
    } catch (e) {
      _appendLog('❌ Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _runApproach2() async {
    if (!await _ensureCallPermission()) return;
    final base = _approach2BaseController.text.trim();
    final options = _approach2MenuController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final slot = _simSlot == -1 ? 0 : _simSlot;
    _clearLog();
    _appendLog('▶ Approach 2 (multi-session): $base → menu $options ...');
    setState(() => _loading = true);
    try {
      await UssdLauncher.multisessionUssd(
        code: base,
        options: options,
        slotIndex: slot,
        initialDelayMs: 2000,
        optionDelayMs: 1500,
      );
      _appendLog('✅ Multi-session dispatched.\nCarrier response will appear above via listener.');
    } on PlatformException catch (e) {
      _appendLog('❌ PlatformException\nCode: ${e.code}\nMessage: ${e.message}');
    } catch (e) {
      _appendLog('❌ Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Developer — USSD Tester'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionHeader('SIM Slot'),
            const SizedBox(height: 6),
            TextField(
              controller: _simSlotController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'SIM slot index (-1 = default, 0 = SIM1, 1 = SIM2)',
              ),
            ),
            const SizedBox(height: 20),
            _SectionHeader('Approach 1 — sendUssdRequest'),
            const SizedBox(height: 6),
            TextField(
              controller: _approach1Controller,
              decoration: const InputDecoration(labelText: 'USSD code (e.g. *113*1*1#)'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _loading ? null : _runApproach1A,
                    child: const Text('1-A  Raw (#)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _loading ? null : _runApproach1B,
                    child: const Text('1-B  Encoded (%23)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionHeader('Approach 2 — multisessionUssd (menu-driven)'),
            const SizedBox(height: 6),
            TextField(
              controller: _approach2BaseController,
              decoration: const InputDecoration(labelText: 'Base code (e.g. *113#)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _approach2MenuController,
              decoration: const InputDecoration(
                labelText: 'Menu selections, comma-separated (e.g. 1,1)',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _runApproach2,
                child: const Text('Run Approach 2'),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _SectionHeader('Output'),
                const Spacer(),
                if (_log.isNotEmpty)
                  TextButton(onPressed: _clearLog, child: const Text('Clear')),
              ],
            ),
            const SizedBox(height: 6),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_log.isEmpty)
              const Text(
                'Tap a button above to dial a USSD code.',
                style: TextStyle(color: Colors.grey),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SelectableText(
                  _log.trim(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}
