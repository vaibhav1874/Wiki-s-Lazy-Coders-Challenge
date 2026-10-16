enum CommonsLicense {
  ccBySa4(
    'Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0)',
    '{{self|cc-by-sa-4.0}}',
  ),
  ccBy4('Creative Commons Attribution 4.0 (CC BY 4.0)', '{{self|cc-by-4.0}}'),
  cc0('Creative Commons CC0 1.0 Universal (Public Domain)', '{{Cc-zero}}');

  final String displayName;
  final String wikitextTemplate;

  const CommonsLicense(this.displayName, this.wikitextTemplate);
}

class UploadMetadata {
  final String title;
  final String description;
  final DateTime date;
  final String author;
  final CommonsLicense license;
  final double? latitude;
  final double? longitude;
  final List<String> categories;
  final bool hasConfirmedRights;

  const UploadMetadata({
    required this.title,
    required this.description,
    required this.date,
    required this.author,
    required this.license,
    this.latitude,
    this.longitude,
    this.categories = const ['Videos'],
    required this.hasConfirmedRights,
  });

  /// Sanitizes Commons filename (ensures .webm extension and removes invalid characters).
  String get sanitizedFilename {
    var clean = title.trim();
    if (clean.toLowerCase().endsWith('.webm')) {
      clean = clean.substring(0, clean.length - 5);
    }
    // Replace invalid characters: # < > [ ] | { } / :
    clean = clean.replaceAll(RegExp(r'[#<>\[\]|{}/:\\]'), '_').trim();
    if (clean.isEmpty) {
      clean = 'WebM_Video_${date.millisecondsSinceEpoch}';
    }
    return '$clean.webm';
  }

  /// Generates the standard MediaWiki wikitext for Wikimedia Commons.
  String generateWikitext() {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    var locationWikitext = '';
    if (latitude != null && longitude != null) {
      locationWikitext = '\n{{Location|$latitude|$longitude}}';
    }

    final categoryTags = categories
        .map((c) => '[[Category:${c.trim()}]]')
        .join('\n');

    return '''
== {{int:filedesc}} ==
{{Information
|description={{en|1=${description.trim()}}}
|date=$dateStr
|source={{own}}
|author=[[User:${author.trim()}|${author.trim()}]]
|permission=
|other_versions=
}}$locationWikitext

== {{int:license-header}} ==
${license.wikitextTemplate}

$categoryTags
'''
        .trim();
  }
}
