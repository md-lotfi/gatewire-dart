import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:gatewire_dart/gatewire_dart.dart';

void main() {
  const apiKey = 'test-api-key';
  const baseUrl = 'https://gatewire.net/api/v1';

  ServicesService makeService(MockClient mockClient) =>
      ServicesService(mockClient, apiKey, baseUrl);

  // Reusable valid catalog payload matching the backend spec.
  final validCatalogPayload = {
    'services': {
      'otp': {
        'enabled': true,
        'price_per_request_cents': 50,
        'currency': 'DZD',
        'platform': 'all',
      },
      'pnv': {
        'enabled': false,
        'price_per_request_cents': 30,
        'currency': 'DZD',
        'platform': 'android',
      },
    },
  };

  // ---------------------------------------------------------------------------
  // ServiceInfo.fromJson
  // ---------------------------------------------------------------------------

  group('ServiceInfo.fromJson', () {
    test('parses standard OTP payload', () {
      final info = ServiceInfo.fromJson({
        'enabled': true,
        'price_per_request_cents': 50,
        'currency': 'DZD',
        'platform': 'all',
      });

      expect(info.enabled, isTrue);
      expect(info.pricePerRequestCents, equals(50));
      expect(info.currency, equals('DZD'));
      expect(info.platform, equals('all'));
    });

    test('parses platform: android', () {
      final info = ServiceInfo.fromJson({
        'enabled': false,
        'price_per_request_cents': 30,
        'currency': 'DZD',
        'platform': 'android',
      });

      expect(info.platform, equals('android'));
      expect(info.enabled, isFalse);
    });

    test('parses platform: all', () {
      final info = ServiceInfo.fromJson({
        'enabled': true,
        'price_per_request_cents': 10,
        'currency': 'USD',
        'platform': 'all',
      });

      expect(info.platform, equals('all'));
    });
  });

  // ---------------------------------------------------------------------------
  // ServiceCatalog.fromJson
  // ---------------------------------------------------------------------------

  group('ServiceCatalog.fromJson', () {
    test('parses both services from valid payload', () {
      final catalog = ServiceCatalog.fromJson(validCatalogPayload);

      expect(catalog.otp.enabled, isTrue);
      expect(catalog.otp.pricePerRequestCents, equals(50));
      expect(catalog.otp.currency, equals('DZD'));
      expect(catalog.otp.platform, equals('all'));

      expect(catalog.pnv.enabled, isFalse);
      expect(catalog.pnv.pricePerRequestCents, equals(30));
      expect(catalog.pnv.platform, equals('android'));
    });
  });

  // ---------------------------------------------------------------------------
  // ServiceCatalog.isPnvAvailableOnThisDevice
  // ---------------------------------------------------------------------------

  group('ServiceCatalog.isPnvAvailableOnThisDevice', () {
    final enabledPnvPayload = {
      'services': {
        'otp': {
          'enabled': true,
          'price_per_request_cents': 50,
          'currency': 'DZD',
          'platform': 'all',
        },
        'pnv': {
          'enabled': true,
          'price_per_request_cents': 30,
          'currency': 'DZD',
          'platform': 'android',
        },
      },
    };

    test('true when pnv.enabled and device is Android', () {
      final catalog = ServiceCatalog.fromJson(
        enabledPnvPayload,
        isAndroid: () => true,
      );

      expect(catalog.isPnvAvailableOnThisDevice, isTrue);
    });

    test('false when pnv.enabled but device is not Android', () {
      final catalog = ServiceCatalog.fromJson(
        enabledPnvPayload,
        isAndroid: () => false,
      );

      expect(catalog.isPnvAvailableOnThisDevice, isFalse);
    });

    test('false when pnv.enabled is false even on Android', () {
      final catalog = ServiceCatalog.fromJson(
        validCatalogPayload, // pnv.enabled = false
        isAndroid: () => true,
      );

      expect(catalog.isPnvAvailableOnThisDevice, isFalse);
    });

    test('false when pnv.enabled is false and not Android', () {
      final catalog = ServiceCatalog.fromJson(
        validCatalogPayload,
        isAndroid: () => false,
      );

      expect(catalog.isPnvAvailableOnThisDevice, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // ServicesService.fetchCatalog
  // ---------------------------------------------------------------------------

  group('ServicesService.fetchCatalog', () {
    test('returns ServiceCatalog on 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/client/services'));
        expect(request.method, equals('GET'));
        expect(
          request.headers['Authorization'],
          equals('Bearer $apiKey'),
        );

        return http.Response(
          jsonEncode(validCatalogPayload),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final catalog = await makeService(mockClient).fetchCatalog();

      expect(catalog.otp.enabled, isTrue);
      expect(catalog.pnv.enabled, isFalse);
    });

    test('caches result — second call within TTL does not hit HTTP client',
        () async {
      int callCount = 0;

      final mockClient = MockClient((_) async {
        callCount++;
        return http.Response(
          jsonEncode(validCatalogPayload),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = makeService(mockClient);
      await service.fetchCatalog();
      await service.fetchCatalog(); // should be served from cache

      expect(callCount, equals(1));
    });

    test('cache invalidation — after invalidateCache() next call hits network',
        () async {
      int callCount = 0;

      final mockClient = MockClient((_) async {
        callCount++;
        return http.Response(
          jsonEncode(validCatalogPayload),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = makeService(mockClient);
      await service.fetchCatalog();
      service.invalidateCache();
      await service.fetchCatalog(); // cache was cleared — hits network again

      expect(callCount, equals(2));
    });

    test('throws GateWireException with statusCode 401', () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({'error': 'Unauthorized'}),
            401,
            headers: {'content-type': 'application/json'},
          ));

      expect(
        () => makeService(mockClient).fetchCatalog(),
        throwsA(
          isA<GateWireException>()
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws GateWireException with statusCode 403', () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({'error': 'Forbidden'}),
            403,
            headers: {'content-type': 'application/json'},
          ));

      expect(
        () => makeService(mockClient).fetchCatalog(),
        throwsA(
          isA<GateWireException>()
              .having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('throws GateWireException with statusCode 500', () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({'error': 'Internal Server Error'}),
            500,
            headers: {'content-type': 'application/json'},
          ));

      expect(
        () => makeService(mockClient).fetchCatalog(),
        throwsA(
          isA<GateWireException>()
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('throws GateWireException on network error', () async {
      final mockClient =
          MockClient((_) async => throw Exception('No internet'));

      expect(
        () => makeService(mockClient).fetchCatalog(),
        throwsA(
          isA<GateWireException>()
              .having((e) => e.message, 'message', contains('Network error')),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // GateWireClient.services getter
  // ---------------------------------------------------------------------------

  group('GateWireClient.services', () {
    test('exposes a ServicesService instance', () {
      final client = GateWireClient(apiKey: apiKey);
      expect(client.services, isA<ServicesService>());
    });

    test('late final — returns same instance on repeated access', () {
      final client = GateWireClient(apiKey: apiKey);
      expect(identical(client.services, client.services), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // GateWireClient.dispatch — 403 service_disabled guard
  // ---------------------------------------------------------------------------

  group('GateWireClient.dispatch — service disabled', () {
    test('throws GateWireException with code service_disabled on 403',
        () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode(
                {'error': 'OTP service is not enabled for your account.'}),
            403,
            headers: {'content-type': 'application/json'},
          ));

      expect(
        () => GateWireClient(apiKey: apiKey, baseUrl: baseUrl, client: mockClient)
            .dispatch(phone: '+213555123456'),
        throwsA(
          isA<GateWireException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'service_disabled')
              .having(
                  (e) => e.message, 'message', contains('not enabled')),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // PnvService.initiate — 403 service_disabled guard
  // ---------------------------------------------------------------------------

  group('PnvService.initiate — service disabled', () {
    test('throws GateWireException with code service_disabled on 403',
        () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({
              'error':
                  'Phone Number Verification service is not enabled for your account.'
            }),
            403,
            headers: {'content-type': 'application/json'},
          ));

      expect(
        () => PnvService(mockClient, apiKey, baseUrl)
            .initiate(phoneNumber: '+213770123456'),
        throwsA(
          isA<GateWireException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'service_disabled')
              .having(
                  (e) => e.message, 'message', contains('not enabled')),
        ),
      );
    });
  });
}
