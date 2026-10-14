class WikimediaUser {
  final int id;
  final String name;
  final int editCount;
  final List<String> groups;

  const WikimediaUser({
    required this.id,
    required this.name,
    this.editCount = 0,
    this.groups = const [],
  });

  factory WikimediaUser.fromMap(Map<String, dynamic> map) {
    return WikimediaUser(
      id: map['id'] as int? ?? 0,
      name: map['name']?.toString() ?? 'Wikimedia User',
      editCount: map['editcount'] as int? ?? 0,
      groups: (map['groups'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'editcount': editCount,
        'groups': groups,
      };
}

class OAuthTokens {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final String tokenType;

  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    this.tokenType = 'Bearer',
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory OAuthTokens.fromMap(Map<String, dynamic> map) {
    final expiresIn = map['expires_in'] as int? ?? 3600;
    return OAuthTokens(
      accessToken: map['access_token']?.toString() ?? '',
      refreshToken: map['refresh_token']?.toString(),
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      tokenType: map['token_type']?.toString() ?? 'Bearer',
    );
  }

  Map<String, dynamic> toMap() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
        'token_type': tokenType,
      };
}
