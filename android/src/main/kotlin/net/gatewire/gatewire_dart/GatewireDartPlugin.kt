package net.gatewire.gatewire_dart

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * GatewireDartPlugin — minimal Android entry point.
 *
 * This plugin class exists solely so that gatewire_dart participates in
 * Flutter's plugin registration and its AndroidManifest.xml is included in
 * the consuming app's manifest merger. The manifest contributes the
 * `android:foregroundServiceType="shortService"` fix for ussd_launcher's
 * UssdOverlayService, preventing the Android 14+ (API 34+) crash:
 *   MissingForegroundServiceTypeException: Starting FGS without a type
 *
 * All SDK functionality is implemented in pure Dart — there are no method
 * channels or native calls in this plugin.
 */
class GatewireDartPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
