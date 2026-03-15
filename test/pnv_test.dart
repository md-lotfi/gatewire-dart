import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:gatewire_dart/gatewire_dart.dart';

void main() {
  const apiKey = 'test-api-key';
  const baseUrl = 'https://gatewire.net/api/v1';

  PnvService makeService(MockClient mockClient) =>
      PnvService(mockClient, apiKey, baseUrl);

  // ---------------------------------------------------------------------------
  // PnvSession.fromJson
  // ---------------------------------------------------------------------------

  group('PnvSession.fromJson', () {
    test('parses all fields from a valid payload', () {
      final session = PnvSession.fromJson({
        'reference_id': 'ref-abc-123',
        'operator_name': 'Djezzy',
        'country_code': 'DZ',
        'ussd_code': '*555#',
        'expires_at': '2026-03-15T12:05:00.000Z',
      });

      expect(session.referenceId, equals('ref-abc-123'));
      expect(session.operatorName, equals('Djezzy'));
      expect(session.countryCode, equals('DZ'));
      expect(session.ussdCode, equals('*555#'));
      expect(
        session.expiresAt,
        equals(DateTime.parse('2026-03-15T12:05:00.000Z')),
      );
    });

    test('parses expiresAt as UTC', () {
      final session = PnvSession.fromJson({
        'reference_id': 'r',
        'operator_name': 'Op',
        'country_code': 'XX',
        'ussd_code': '*1#',
        'expires_at': '2026-03-15T10:30:00Z',
      });

      expect(session.expiresAt.isUtc, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // PnvResult.fromJson
  // ---------------------------------------------------------------------------

  group('PnvResult.fromJson', () {
    test('parses verified: true', () {
      final result = PnvResult.fromJson({
        'verified': true,
        'message': 'Phone number verified successfully.',
      });

      expect(result.verified, isTrue);
      expect(result.message, equals('Phone number verified successfully.'));
    });

    test('parses verified: false', () {
      final result = PnvResult.fromJson({
        'verified': false,
        'message': 'Phone number does not match.',
      });

      expect(result.verified, isFalse);
      expect(result.message, equals('Phone number does not match.'));
    });
  });

  // ---------------------------------------------------------------------------
  // PnvService.initiate
  // ---------------------------------------------------------------------------

  group('PnvService.initiate', () {
    test('returns PnvSession on 201', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/pnv/initiate'));
        expect(request.method, equals('POST'));
        expect(
          jsonDecode(request.body)['phone_number'],
          equals('+213770123456'),
        );

        return http.Response(
          jsonEncode({
            'reference_id': 'ref-xyz',
            'operator_name': 'Djezzy',
            'country_code': 'DZ',
            'ussd_code': '*555#',
            'expires_at': '2026-03-15T12:05:00Z',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final session = await makeService(mockClient)
          .initiate(phoneNumber: '+213770123456');

      expect(session.referenceId, equals('ref-xyz'));
      expect(session.operatorName, equals('Djezzy'));
      expect(session.ussdCode, equals('*555#'));
    });

    test('throws GateWireException with statusCode 402', () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({'message': 'Insufficient balance'}),
            402,
            headers: {'content-type': 'application/json'},
          ));

      expect(
        () => makeService(mockClient).initiate(phoneNumber: '+213770123456'),
        throwsA(
          isA<GateWireException>()
              .having((e) => e.statusCode, 'statusCode', 402)
              .having((e) => e.message, 'message', 'Insufficient balance'),
        ),
      );
    });

    test('throws GateWireException with statusCode 422', () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({'message': 'Validation failed'}),
            422,
            headers: {'content-type': 'application/json'},
          ));

      expect(
        () => makeService(mockClient).initiate(phoneNumber: 'bad'),
        throwsA(
          isA<GateWireException>()
              .having((e) => e.statusCode, 'statusCode', 422),
        ),
      );
    });

    test('throws GateWireException with statusCode 429', () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({'error': 'Too many requests'}),
            429,
            headers: {'content-type': 'application/json'},
          ));

      expect(
        () => makeService(mockClient).initiate(phoneNumber: '+213770123456'),
        throwsA(
          isA<GateWireException>()
              .having((e) => e.statusCode, 'statusCode', 429),
        ),
      );
    });

    test('throws GateWireException on network error', () async {
      final mockClient =
          MockClient((_) async => throw Exception('No internet'));

      expect(
        () => makeService(mockClient).initiate(phoneNumber: '+213770123456'),
        throwsA(
          isA<GateWireException>()
              .having((e) => e.message, 'message', contains('Network error')),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // PnvService.verify
  // ---------------------------------------------------------------------------

  group('PnvService.verify', () {
    test('returns PnvResult with verified: true on 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/pnv/verify'));
        expect(request.method, equals('POST'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['reference_id'], equals('ref-xyz'));
        expect(body['ussd_response'], equals('Your number is 0770123456.'));

        return http.Response(
          jsonEncode({
            'verified': true,
            'message': 'Phone number verified successfully.',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await makeService(mockClient).verify(
        referenceId: 'ref-xyz',
        ussdResponse: 'Your number is 0770123456.',
      );

      expect(result.verified, isTrue);
      expect(result.message, equals('Phone number verified successfully.'));
    });

    test('returns PnvResult with verified: false on 200', () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({
              'verified': false,
              'message': 'Phone number does not match.',
            }),
            200,
            headers: {'content-type': 'application/json'},
          ));

      final result = await makeService(mockClient).verify(
        referenceId: 'ref-xyz',
        ussdResponse: 'unrelated response',
      );

      expect(result.verified, isFalse);
    });

    test('throws GateWireException with statusCode 400', () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({'message': 'Session expired'}),
            400,
            headers: {'content-type': 'application/json'},
          ));

      expect(
        () => makeService(mockClient).verify(
          referenceId: 'ref-xyz',
          ussdResponse: 'x',
        ),
        throwsA(
          isA<GateWireException>()
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('throws GateWireException with statusCode 404', () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({'message': 'Session not found'}),
            404,
            headers: {'content-type': 'application/json'},
          ));

      expect(
        () => makeService(mockClient).verify(
          referenceId: 'unknown-ref',
          ussdResponse: 'x',
        ),
        throwsA(
          isA<GateWireException>()
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // GateWireClient.pnv getter
  // ---------------------------------------------------------------------------

  group('GateWireClient.pnv', () {
    test('exposes a PnvService instance', () {
      final client = GateWireClient(apiKey: 'key');
      expect(client.pnv, isA<PnvService>());
    });

    test('late final — returns same instance on repeated access', () {
      final client = GateWireClient(apiKey: 'key');
      expect(identical(client.pnv, client.pnv), isTrue);
    });
  });

  // NOTE: PnvService.dialAndVerify is not covered by unit tests because it
  // depends on Platform.isAndroid and the ussd_launcher method channel, both
  // of which require a real Android device or emulator. Test it via an
  // integration test in the example app.
}
