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
    required this.title,
    this.rating,
    this.posterPath,
  });

  final String region;
  final List<WatchProvider> providers;
  final String link;
  final String title;
  final double? rating;
  final String? posterPath;
}

class SearchResult {
  const SearchResult({
    required this.id,
    required this.title,
    required this.mediaType,
    this.posterPath,
    this.rating,
    this.releaseYear,
  });

  final int id;
  final String title;
  final String mediaType;
  final String? posterPath;
  final double? rating;
  final String? releaseYear;
}

class TitleDetails {
  const TitleDetails({
    required this.id,
    required this.title,
    required this.mediaType,
    this.overview,
    this.tagline,
    this.posterPath,
    this.backdropPath,
    this.rating,
    this.releaseYear,
    this.runtimeMinutes,
    this.genres = const [],
  });

  final int id;
  final String title;
  final String mediaType;
  final String? overview;
  final String? tagline;
  final String? posterPath;
  final String? backdropPath;
  final double? rating;
  final String? releaseYear;
  final int? runtimeMinutes;
  final List<String> genres;
}

class TmdbClient {
  TmdbClient({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

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
    final results = await searchTitles(
      title: title,
      mediaType: mediaType,
      limit: 1,
    );
    if (results.isEmpty) return null;
    final match = results.first;

    return getWatchProvidersById(
      id: match.id,
      title: match.title,
      mediaType: match.mediaType,
      region: region,
      rating: match.rating,
      posterPath: match.posterPath,
    );
  }

  Future<WatchProvidersResult?> getWatchProvidersById({
    required int id,
    required String title,
    required String mediaType,
    required String region,
    double? rating,
    String? posterPath,
  }) async {
    if (apiKey.isEmpty) {
      throw Exception('Missing TMDB_API_KEY.');
    }

    final uri = Uri.parse(
      'https://api.themoviedb.org/3/$mediaType/$id/watch/providers',
    ).replace(queryParameters: {'api_key': apiKey});

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
      title: title,
      rating: rating,
      posterPath: posterPath,
    );
  }

  Future<List<SearchResult>> searchTitles({
    required String title,
    required String mediaType,
    int limit = 10,
  }) async {
    if (apiKey.isEmpty) {
      throw Exception('Missing TMDB_API_KEY.');
    }

    final uri = Uri.parse('https://api.themoviedb.org/3/search/$mediaType')
        .replace(
          queryParameters: {
            'api_key': apiKey,
            'query': title,
            'include_adult': 'false',
          },
        );

    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TMDB search failed (${response.statusCode}).');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final results = payload['results'];
    if (results is! List || results.isEmpty) {
      return const [];
    }

    final matches = <SearchResult>[];
    for (final entry in results.take(limit)) {
      if (entry is! Map<String, dynamic>) continue;

      final id = entry['id'];
      if (id is! int) continue;

      String resolvedTitle = title;
      final rawTitle = entry['title'] ?? entry['name'];
      if (rawTitle is String && rawTitle.trim().isNotEmpty) {
        resolvedTitle = rawTitle.trim();
      }

      double? rating;
      final voteAverage = entry['vote_average'];
      if (voteAverage is num) {
        rating = voteAverage.toDouble();
      }

      String? posterPath;
      final poster = entry['poster_path'];
      if (poster is String && poster.isNotEmpty) {
        posterPath = poster;
      }

      String? releaseYear;
      final releaseDate = entry['release_date'] ?? entry['first_air_date'];
      if (releaseDate is String && releaseDate.length >= 4) {
        releaseYear = releaseDate.substring(0, 4);
      }

      matches.add(
        SearchResult(
          id: id,
          title: resolvedTitle,
          mediaType: mediaType,
          posterPath: posterPath,
          rating: rating,
          releaseYear: releaseYear,
        ),
      );
    }

    return matches;
  }

  Future<TitleDetails> getTitleDetails({
    required int id,
    required String mediaType,
  }) async {
    if (apiKey.isEmpty) {
      throw Exception('Missing TMDB_API_KEY.');
    }

    final normalizedType = mediaType.toLowerCase() == 'tv' ? 'tv' : 'movie';
    final uri = Uri.parse(
      'https://api.themoviedb.org/3/$normalizedType/$id',
    ).replace(queryParameters: {'api_key': apiKey});

    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TMDB details failed (${response.statusCode}).');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;

    String resolvedTitle =
        payload['title']?.toString() ?? payload['name']?.toString() ?? '';
    if (resolvedTitle.isEmpty) {
      resolvedTitle = 'Unknown title';
    }

    double? rating;
    final voteAverage = payload['vote_average'];
    if (voteAverage is num) {
      rating = voteAverage.toDouble();
    }

    String? posterPath;
    final poster = payload['poster_path'];
    if (poster is String && poster.isNotEmpty) {
      posterPath = poster;
    }

    String? backdropPath;
    final backdrop = payload['backdrop_path'];
    if (backdrop is String && backdrop.isNotEmpty) {
      backdropPath = backdrop;
    }

    String? releaseYear;
    final releaseDate = payload['release_date'] ?? payload['first_air_date'];
    if (releaseDate is String && releaseDate.length >= 4) {
      releaseYear = releaseDate.substring(0, 4);
    }

    int? runtimeMinutes;
    if (payload['runtime'] is int) {
      runtimeMinutes = payload['runtime'] as int;
    } else if (payload['episode_run_time'] is List &&
        (payload['episode_run_time'] as List).isNotEmpty &&
        (payload['episode_run_time'] as List).first is int) {
      runtimeMinutes = (payload['episode_run_time'] as List).first as int;
    }

    final genres = <String>[];
    final genreEntries = payload['genres'];
    if (genreEntries is List) {
      for (final entry in genreEntries) {
        if (entry is Map && entry['name'] is String) {
          genres.add(entry['name'] as String);
        }
      }
    }

    final overview = payload['overview']?.toString();
    final tagline = payload['tagline']?.toString();

    return TitleDetails(
      id: id,
      title: resolvedTitle,
      mediaType: normalizedType,
      overview: overview?.isNotEmpty == true ? overview : null,
      tagline: tagline?.isNotEmpty == true ? tagline : null,
      posterPath: posterPath,
      backdropPath: backdropPath,
      rating: rating,
      releaseYear: releaseYear,
      runtimeMinutes: runtimeMinutes,
      genres: genres,
    );
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
