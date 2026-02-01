import 'dart:convert';

import 'package:http/http.dart' as http;

class WatchProvider {
  const WatchProvider({
    required this.name,
    required this.displayName,
    required this.logoPath,
    required this.type,
  });

  final String name;
  final String displayName;
  final String? logoPath;
  final String type;
}

class WatchProvidersResult {
  const WatchProvidersResult({
    required this.region,
    required this.providers,
    required this.link,
    this.rating,
    this.posterPath,
  });

  final String region;
  final List<WatchProvider> providers;
  final String link;
  final double? rating;
  final String? posterPath;
}

class TmdbClient {
  TmdbClient({
    required this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  Future<WatchProvidersResult?> getWatchProviders({
    required String title,
    required String region,
    required String type,
  }) async {
    if (apiKey.isEmpty) {
      throw Exception('Missing TMDB_API_KEY.');
    }

    final mediaType = type.toLowerCase() == 'tv' ? 'tv' : 'movie';
    final search = await _searchFirstResult(title: title, mediaType: mediaType);
    if (search == null) {
      return null;
    }

    final uri = Uri.parse(
      'https://api.themoviedb.org/3/$mediaType/${search.id}/watch/providers',
    ).replace(queryParameters: {
      'api_key': apiKey,
    });

    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TMDB request failed (${response.statusCode}).');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final results = payload['results'];
    if (results is! Map<String, dynamic>) {
      return null;
    }

    final regionData = results[region.toUpperCase()];
    if (regionData is! Map<String, dynamic>) {
      return null;
    }

    final providers = <WatchProvider>[];
    providers.addAll(_parseProviders(regionData, 'flatrate'));
    providers.addAll(_parseProviders(regionData, 'free'));

    final link = regionData['link']?.toString() ?? '';

    return WatchProvidersResult(
      region: region.toUpperCase(),
      providers: _dedupeProviders(providers),
      link: link,
      rating: search.rating,
      posterPath: search.posterPath,
    );
  }

  Future<_SearchResult?> _searchFirstResult({
    required String title,
    required String mediaType,
  }) async {
    final uri = Uri.parse('https://api.themoviedb.org/3/search/$mediaType')
        .replace(queryParameters: {
      'api_key': apiKey,
      'query': title,
      'include_adult': 'false',
    });

    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TMDB search failed (${response.statusCode}).');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final results = payload['results'];
    if (results is! List || results.isEmpty) {
      return null;
    }

    final first = results.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }

    final id = first['id'];
    if (id is! int) {
      return null;
    }

    double? rating;
    final voteAverage = first['vote_average'];
    if (voteAverage is num) {
      rating = voteAverage.toDouble();
    }

    String? posterPath;
    final poster = first['poster_path'];
    if (poster is String && poster.isNotEmpty) {
      posterPath = poster;
    }

    return _SearchResult(id: id, rating: rating, posterPath: posterPath);
  }

  List<WatchProvider> _parseProviders(
    Map<String, dynamic> regionData,
    String key,
  ) {
    final entries = regionData[key];
    if (entries is! List) {
      return const [];
    }

    return entries
        .whereType<Map<String, dynamic>>()
        .map((entry) {
          final rawName = (entry['provider_name'] ?? '').toString();
          final displayName = _normalizeProviderName(rawName);
          return WatchProvider(
            name: rawName,
            displayName: displayName,
            logoPath: entry['logo_path']?.toString(),
            type: key,
          );
        })
        .where((provider) => provider.displayName.isNotEmpty)
        .toList();
  }

  String _normalizeProviderName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('netflix')) return 'Netflix';
    if (lower.contains('paramount')) return 'Paramount+';
    if (lower.contains('disney')) return 'Disney+';
    if (lower.contains('hulu')) return 'Hulu';
    if (lower.contains('max')) return 'Max';
    if (lower.contains('peacock')) return 'Peacock';
    if (lower.contains('apple tv')) return 'Apple TV+';
    if (lower.contains('apple+')) return 'Apple TV+';
    if (lower.contains('starz')) return 'Starz';
    if (lower.contains('showtime')) return 'Showtime';
    if (lower.contains('espn')) return 'ESPN+';
    if (lower.contains('crave')) return 'Crave';
    if (lower.contains('now tv') || lower.contains('nowtv')) return 'NOW';
    if (lower.contains('canal+')) return 'Canal+';
    if (lower.contains('mubi')) return 'MUBI';
    if (lower.contains('criterion')) return 'Criterion Channel';
    if (lower.contains('youtube')) return 'YouTube';
    if (lower.contains('plex')) return 'Plex';
    if (lower.contains('tubi')) return 'Tubi';
    if (lower.contains('roku')) return 'The Roku Channel';
    if (lower.contains('freevee')) return 'Freevee';
    if (lower.contains('pluto')) return 'Pluto TV';
    if (lower.contains('fubotv') || lower.contains('fubo')) return 'fuboTV';
    if (lower.contains('sling')) return 'Sling TV';
    if (lower.contains('philo')) return 'Philo';
    if (lower.contains('bet+')) return 'BET+';
    if (lower.contains('boomerang')) return 'Boomerang';
    if (lower.contains('prime')) return 'Prime Video';
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  }

  List<WatchProvider> _dedupeProviders(List<WatchProvider> providers) {
    final seen = <String>{};
    final deduped = <WatchProvider>[];
    for (final provider in providers) {
      final key = '${provider.displayName}|${provider.type}';
      if (seen.add(key)) {
        deduped.add(provider);
      }
    }
    return deduped;
  }
}

class _SearchResult {
  const _SearchResult({required this.id, this.rating, this.posterPath});
  final int id;
  final double? rating;
  final String? posterPath;
}
