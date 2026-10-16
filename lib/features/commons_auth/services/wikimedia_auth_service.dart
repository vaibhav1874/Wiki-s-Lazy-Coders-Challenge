import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:wiki_lazy_coders/core/constants/api_constants.dart';
import 'package:wiki_lazy_coders/core/errors/failures.dart';
import 'package:wiki_lazy_coders/features/commons_auth/models/auth_state.dart';

class WikimediaAuthService {
  static const MethodChannel _authChannel = MethodChannel(
    'org.wikimedia.wikilazycoders/auth',
  );

  final FlutterSecureStorage _storage;
  final http.Client _httpClient;

  WikimediaAuthService({FlutterSecureStorage? storage, http.Client? httpClient})
    : _storage = storage ?? const FlutterSecureStorage(),
      _httpClient = httpClient ?? http.Client();

  String? _lastCodeVerifier;

  /// Loads stored access token, refreshing if expired.
  Future<OAuthTokens?> getValidTokens() async {
    final tokenJson = await _storage.read(key: ApiConstants.keyAccessToken);
    if (tokenJson == null) return null;

    try {
      final map = jsonDecode(tokenJson) as Map<String, dynamic>;
      final tokens = OAuthTokens(
        accessToken: map['access_token']?.toString() ?? '',
        refreshToken: map['refresh_token']?.toString(),
        expiresAt:
            DateTime.tryParse(map['expires_at']?.toString() ?? '') ??
            DateTime.now().add(const Duration(hours: 1)),
        tokenType: map['token_type']?.toString() ?? 'Bearer',
      );

      if (tokens.isExpired && tokens.refreshToken != null) {
        return await refreshToken(tokens.refreshToken!);
      }
      return tokens;
    } catch (_) {
      return null;
    }
  }

  /// Loads stored Wikimedia user profile.
  Future<WikimediaUser?> getStoredUser() async {
    final userJson = await _storage.read(key: ApiConstants.keyUsername);
    if (userJson == null) return null;
    try {
      final map = jsonDecode(userJson) as Map<String, dynamic>;
      return WikimediaUser.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  /// Gets current Client ID (configurable in app settings).
  Future<String> getClientId() async {
    final id = await _storage.read(key: ApiConstants.keyClientId);
    return id ?? ApiConstants.defaultClientId;
  }

  /// Updates configured Client ID.
  Future<void> setClientId(String clientId) async {
    await _storage.write(key: ApiConstants.keyClientId, value: clientId.trim());
  }

  /// Generates a cryptographic PKCE code_verifier (64 chars base64url).
  String _generateCodeVerifier() {
    final random = Random.secure();
    final values = List<int>.generate(48, (_) => random.nextInt(256));
    return base64UrlEncode(values)
        .replaceAll('=', '')
        .replaceAll('+', '-')
        .replaceAll('/', '_');
  }

  /// Generates PKCE code_challenge = base64url(SHA256(code_verifier)).
  String _generateCodeChallenge(String verifier) {
    final bytes = ascii.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes)
        .replaceAll('=', '')
        .replaceAll('+', '-')
        .replaceAll('/', '_');
  }

  /// Builds the full Wikimedia OAuth 2.0 PKCE Authorization URL.
  Future<Uri> buildAuthorizationUri() async {
    final clientId = await getClientId();
    final verifier = _generateCodeVerifier();
    _lastCodeVerifier = verifier;
    await _storage.write(key: 'wm_pkce_verifier', value: verifier);

    final challenge = _generateCodeChallenge(verifier);

    final params = {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': ApiConstants.defaultRedirectUri,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    };

    return Uri.parse(ApiConstants.oauthAuthorizeUrl)
        .replace(queryParameters: params);
  }

  /// Launches the device browser to authenticate with Wikimedia Commons.
  Future<void> startOAuthFlow() async {
    final uri = await buildAuthorizationUri();
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
    } catch (e) {
      // Direct attempt
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (inner) {
        throw WikimediaAuthFailure(
          'Could not launch browser: $inner. Please enter your Access Token or Authorization Code directly.',
        );
      }
    }
  }

  /// Directly saves a pre-generated or owner-only access token.
  Future<OAuthTokens> saveDirectAccessToken(String token) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw const WikimediaAuthFailure('Access token cannot be empty.');
    }
    final tokens = OAuthTokens(
      accessToken: cleanToken,
      refreshToken: null,
      expiresAt: DateTime.now().add(const Duration(days: 365)),
      tokenType: 'Bearer',
    );
    await _storage.write(
      key: ApiConstants.keyAccessToken,
      value: jsonEncode(tokens.toMap()),
    );
    await fetchAndSaveUserProfile(cleanToken);
    return tokens;
  }

  /// Handles redirect callback containing authorization code.
  Future<OAuthTokens> handleAuthorizationCode(String code) async {
    final clientId = await getClientId();
    var verifier = _lastCodeVerifier;
    verifier ??= await _storage.read(key: 'wm_pkce_verifier');

    if (verifier == null) {
      throw const WikimediaAuthFailure(
        'Missing PKCE code verifier. Please restart authentication.',
      );
    }

    final response = await _httpClient.post(
      Uri.parse(ApiConstants.oauthTokenUrl),
      headers: {
        'User-Agent': ApiConstants.userAgent,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'code': code.trim(),
        'redirect_uri': ApiConstants.defaultRedirectUri,
        'code_verifier': verifier,
      },
    );

    if (response.statusCode != 200) {
      final errBody = response.body;
      throw WikimediaAuthFailure(
        'Token exchange failed (${response.statusCode}): $errBody',
        code: 'TOKEN_EXCHANGE_ERROR',
      );
    }

    final tokenMap = jsonDecode(response.body) as Map<String, dynamic>;
    final tokens = OAuthTokens.fromMap(tokenMap);

    // Save tokens securely
    await _storage.write(
      key: ApiConstants.keyAccessToken,
      value: jsonEncode(tokens.toMap()),
    );

    // Fetch and save user profile
    await fetchAndSaveUserProfile(tokens.accessToken);

    return tokens;
  }

  /// Refreshes expired access token.
  Future<OAuthTokens> refreshToken(String refreshToken) async {
    final clientId = await getClientId();
    final response = await _httpClient.post(
      Uri.parse(ApiConstants.oauthTokenUrl),
      headers: {
        'User-Agent': ApiConstants.userAgent,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
      },
    );

    if (response.statusCode != 200) {
      throw WikimediaAuthFailure(
        'Failed to refresh token (${response.statusCode}): ${response.body}',
      );
    }

    final tokenMap = jsonDecode(response.body) as Map<String, dynamic>;
    final tokens = OAuthTokens.fromMap(tokenMap);
    await _storage.write(
      key: ApiConstants.keyAccessToken,
      value: jsonEncode(tokens.toMap()),
    );
    return tokens;
  }

  /// Queries user profile from MediaWiki Action API or OAuth profile endpoint.
  Future<WikimediaUser> fetchAndSaveUserProfile(String accessToken) async {
    try {
      final profileResponse = await _httpClient.get(
        Uri.parse(ApiConstants.oauthProfileUrl),
        headers: {
          'User-Agent': ApiConstants.userAgent,
          'Authorization': 'Bearer $accessToken',
        },
      );
      if (profileResponse.statusCode == 200) {
        final data = jsonDecode(profileResponse.body) as Map<String, dynamic>;
        final user = WikimediaUser(
          id: data['sub'] is int
              ? data['sub'] as int
              : int.tryParse(data['sub']?.toString() ?? '0') ?? 0,
          name: data['username']?.toString() ?? data['sub']?.toString() ?? 'Wikimedia User',
          editCount: data['editcount'] as int? ?? 0,
          groups: (data['groups'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        );
        await _storage.write(
          key: ApiConstants.keyUsername,
          value: jsonEncode(user.toMap()),
        );
        return user;
      }
    } catch (_) {}

    final uri = Uri.parse(ApiConstants.commonsApiUrl).replace(
      queryParameters: {
        'action': 'query',
        'meta': 'userinfo',
        'uiprop': 'groups|editcount',
        'format': 'json',
      },
    );

    final response = await _httpClient.get(
      uri,
      headers: {
        'User-Agent': ApiConstants.userAgent,
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode != 200) {
      throw WikimediaAuthFailure(
        'Failed to fetch user profile: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final userInfo = data['query']?['userinfo'] as Map<String, dynamic>?;
    if (userInfo == null) {
      throw const WikimediaAuthFailure(
        'Invalid user info response from Wikimedia API.',
      );
    }

    final user = WikimediaUser.fromMap(userInfo);
    await _storage.write(
      key: ApiConstants.keyUsername,
      value: jsonEncode(user.toMap()),
    );
    return user;
  }

  /// Checks if any pending OAuth callback was received via deep link on Android intent.
  Future<String?> checkPendingAuthUri() async {
    try {
      final uri = await _authChannel.invokeMethod<String>('getInitialAuthUri');
      return uri;
    } catch (_) {
      return null;
    }
  }

  /// Clears stored credentials and signs out.
  Future<void> signOut() async {
    await _storage.delete(key: ApiConstants.keyAccessToken);
    await _storage.delete(key: ApiConstants.keyUsername);
    await _storage.delete(key: 'wm_pkce_verifier');
  }
}
