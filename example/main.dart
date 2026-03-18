import 'package:gatewire_dart/gatewire_dart.dart';

void main() async {
  final client = GateWireClient(
    apiKey: '116|vt2hsV6qp7F9QQqK2kRIIiV88TGQc8iYxIToCUUfe2d872d1',
  );

  // Send an OTP
  try {
    final dispatch = await client.dispatch(phone: '+1234567890');
    print('OTP sent! Reference ID: ${dispatch.referenceId}');
    print('Status: ${dispatch.status}');

    // Verify the OTP
    final verification = await client.verifyOtp(
      referenceId: dispatch.referenceId,
      code: '123456',
    );
    print('Verification status: ${verification.status}');
    print('Message: ${verification.message}');
  } on GateWireException catch (e) {
    print('Error: ${e.message} (code: ${e.statusCode})');
  }
}
