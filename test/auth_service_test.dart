import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wiki_lazy_coders/core/constants/api_constants.dart';
import 'package:wiki_lazy_coders/features/commons_auth/models/auth_state.dart';
import 'package:wiki_lazy_coders/features/commons_auth/services/wikimedia_auth_service.dart';

// In-memory mock storage
class MockSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #read) {
      final key = invocation.namedArguments[const Symbol('key')] as String;
      return Future.value(_data[key]);
    }
    if (invocation.memberName == #write) {
      final key = invocation.namedArguments[const Symbol('key')] as String;
      final value = invocation.namedArguments[const Symbol('value')] as String?;
      if (value != null) {
        _data[key] = value;
      }
      return Future.value();
    }
    if (invocation.memberName == #delete) {
      final key = invocation.namedArguments[const Symbol('key')] as String;
      _data.remove(key);
      return Future.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSecureStorage mockStorage;

  setUp(() {
    mockStorage = MockSecureStorage();
  });

  group('OAuthTokens Model Tests', () {
    test('isExpired detects validity correctly', () {
      final activeTokens = OAuthTokens(
        accessToken: 'active-123',
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
      );
      expect(activeTokens.isExpired, isFalse);

      final expiredTokens = OAuthTokens(
        accessToken: 'expired-123',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(expiredTokens.isExpired, isTrue);
    });
  });

  group('WikimediaAuthService PKCE & OAuth Flow Tests', () {
    test('buildAuthorizationUri creates valid PKCE auth request with S256 challenge', () async {
      final service = WikimediaAuthService(storage: mockStorage);

      final authUri = await service.buildAuthorizationUri();

      expect(authUri.scheme, 'https');
      expect(authUri.host, 'commons.wikimedia.org');
      expect(authUri.path, '/w/rest.php/oauth2/authorize');

      final params = authUri.queryParameters;
      expect(params['response_type'], 'code');
      expect(params['client_id'], ApiConstants.defaultClientId);
      expect(params['redirect_uri'], ApiConstants.defaultRedirectUri);
      expect(params['code_challenge_method'], 'S256');
      expect(params['code_challenge'], isNotEmpty);

      // Verify PKCE verifier was stored securely
      final storedVerifier = await mockStorage.read(key: 'wm_pkce_verifier');
      expect(storedVerifier, isNotNull);
      expect(storedVerifier!.length, greaterThan(40));
    });

    test('handleAuthorizationCode exchanges code for tokens and fetches user profile', () async {
      await mockStorage.write(
        key: 'wm_pkce_verifier',
        value: 'test_pkce_code_verifier_1234567890',
      );

      final mockClient = MockClient((request) async {
        if (request.url.toString() == ApiConstants.oauthTokenUrl) {
          expect(request.method, 'POST');
          expect(request.bodyFields['grant_type'], 'authorization_code');
          expect(request.bodyFields['code'], 'mock_auth_code_xyz');
          expect(
            request.bodyFields['code_verifier'],
            'test_pkce_code_verifier_1234567890',
          );

          return http.Response(
            jsonEncode({
              'access_token': 'new_mock_access_token',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'refresh_token': 'new_mock_refresh_token',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/w/api.php') {
          expect(
            request.headers['Authorization'],
            'Bearer new_mock_access_token',
          );
          return http.Response(
            jsonEncode({
              'query': {
                'userinfo': {
                  'id': 12345,
                  'name': 'TestWikimediaUser',
                  'editcount': 42,
                  'groups': ['user', 'autoconfirmed'],
                }
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not Found: ${request.url}', 404);
      });

      final service = WikimediaAuthService(
        storage: mockStorage,
        httpClient: mockClient,
      );
      final tokens = await service.handleAuthorizationCode(
        'mock_auth_code_xyz',
      );

      expect(tokens.accessToken, 'new_mock_access_token');
      expect(tokens.refreshToken, 'new_mock_refresh_token');

      // Verify tokens and user were securely persisted
      final storedTokens = await service.getValidTokens();
      expect(storedTokens, isNotNull);
      expect(storedTokens!.accessToken, 'new_mock_access_token');

      final user = await service.getStoredUser();
      expect(user, isNotNull);
      expect(user!.name, 'TestWikimediaUser');
      expect(user.editCount, 42);
    });

    test('refreshToken updates access token when expired', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.bodyFields['grant_type'], 'refresh_token');
        expect(request.bodyFields['refresh_token'], 'existing_refresh_token');

        return http.Response(
          jsonEncode({
            'access_token': 'refreshed_access_token_abc',
            'token_type': 'Bearer',
            'expires_in': 7200,
            'refresh_token': 'next_refresh_token_xyz',
          }),
          200,
        );
      });

      final service = WikimediaAuthService(
        storage: mockStorage,
        httpClient: mockClient,
      );
      final newTokens = await service.refreshToken('existing_refresh_token');

      expect(newTokens.accessToken, 'refreshed_access_token_abc');
      expect(newTokens.refreshToken, 'next_refresh_token_xyz');
    });

    test('logout clears stored tokens and user details', () async {
      await mockStorage.write(
        key: ApiConstants.keyAccessToken,
        value: 'token_val',
      );
      await mockStorage.write(key: ApiConstants.keyUsername, value: 'user_val');

      final service = WikimediaAuthService(storage: mockStorage);
      await service.signOut();

      final tokens = await service.getValidTokens();
      final user = await service.getStoredUser();

      expect(tokens, isNull);
      expect(user, isNull);
    });
  });
}
