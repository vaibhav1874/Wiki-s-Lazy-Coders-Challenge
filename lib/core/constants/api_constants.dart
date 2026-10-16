class ApiConstants {
  // MediaWiki Action API for Wikimedia Commons
  static const String commonsApiUrl = 'https://commons.wikimedia.org/w/api.php';

  // Wikimedia OAuth 2.0 endpoints
  static const String oauthAuthorizeUrl =
      'https://commons.wikimedia.org/w/rest.php/oauth2/authorize';
  static const String oauthTokenUrl =
      'https://commons.wikimedia.org/w/rest.php/oauth2/access_token';
  static const String oauthProfileUrl =
      'https://commons.wikimedia.org/w/rest.php/oauth2/resource/profile';

  // Mobile custom scheme redirect URI
  static const String defaultRedirectUri = 'wikilazycoders://oauth';

  // MediaWiki User-Agent requirement (Policy: https://meta.wikimedia.org/wiki/User-Agent_policy)
  static const String userAgent =
      'WikiLazyCodersWebmCamera/1.0 (https://github.com/vaibhav1874/Wiki-s-Lazy-Coders-Challenge; contact: vaibhav.dev@wikimedia.org)';

  // Secure storage keys
  static const String keyAccessToken = 'wm_oauth_access_token';
  static const String keyRefreshToken = 'wm_oauth_refresh_token';
  static const String keyTokenExpiry = 'wm_oauth_token_expiry';
  static const String keyUsername = 'wm_oauth_username';
  static const String keyClientId = 'wm_oauth_client_id';

  // Default demo / public OAuth Client ID (configurable via Settings)
  static const String defaultClientId = 'wikilazycoders_app_client';
}
