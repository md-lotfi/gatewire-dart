import 'package:flutter/material.dart';

/// A compact top-anchored banner displayed as a Flutter [OverlayEntry] while
/// a USSD session is in progress.
///
/// Android USSD dialogs are system-level windows that appear above all app
/// content and cannot be hidden. The recommended UX is to show this banner
/// **pinned to the top of the screen** before dialing — it remains visible
/// above the app layer while the USSD dialog appears below it.
///
/// ## Usage
///
/// ```dart
/// OverlayEntry? _ussdBanner;
///
/// void _showBanner(String ussdCode) {
///   _ussdBanner = OverlayEntry(
///     builder: (_) => UssdSessionBanner(ussdCode: ussdCode),
///   );
///   Overlay.of(context).insert(_ussdBanner!);
/// }
///
/// void _hideBanner() {
///   _ussdBanner?.remove();
///   _ussdBanner = null;
/// }
///
/// // Always remove in a finally block:
/// _showBanner(session.ussdCode);
/// try {
///   await UssdLauncher.multisessionUssd(...);
///   // wait for SESSION_COMPLETED …
/// } finally {
///   _hideBanner();
///   UssdLauncher.removeUssdMessageListener();
/// }
/// ```
///
/// > **Do NOT pass `overlayMessage`** to `multisessionUssd()`. The plugin's
/// > native overlay starts a foreground service that crashes on Android 14+
/// > (API 34+) because `UssdOverlayService` lacks a required
/// > `foregroundServiceType` declaration. Use this widget instead.
class UssdSessionBanner extends StatefulWidget {
  /// Creates a USSD session banner.
  ///
  /// [ussdCode] is displayed in the subtitle (e.g. `*113*1*1#`).
  const UssdSessionBanner({super.key, required this.ussdCode});

  /// The USSD code being dialed, shown in the subtitle text.
  final String ussdCode;

  @override
  State<UssdSessionBanner> createState() => _UssdSessionBannerState();
}

class _UssdSessionBannerState extends State<UssdSessionBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.fromLTRB(32, 24, 32, 0),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C2E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF3D5AFE).withValues(alpha: 0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3D5AFE).withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) => Icon(
                        Icons.shield_outlined,
                        size: 32,
                        color: Color.lerp(
                          const Color(0xFF3D5AFE),
                          const Color(0xFF00E5FF),
                          _pulse.value,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Verifying your number',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Dialing ${widget.ussdCode} — please do not touch the screen.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const LinearProgressIndicator(
                  backgroundColor: Color(0xFF2A2A3E),
                  valueColor: AlwaysStoppedAnimation(Color(0xFF3D5AFE)),
                ),
                const SizedBox(height: 16),
                Text(
                  'This will complete automatically',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
