import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'ai_recommender.dart';
import 'movie_lookup_page.dart';
import 'region_resolver.dart';
import 'tmdb_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Movie & TV Recommender',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const _RootTabs(),
    );
  }
}

class _RootTabs extends StatelessWidget {
  const _RootTabs({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('TV & Movie finder'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.search), text: 'Find a movie'),
              Tab(icon: Icon(Icons.auto_awesome), text: 'Recommend'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [MovieLookupPage(), RecommendationPage()],
        ),
      ),
    );
  }
}

class RecommendationPage extends StatefulWidget {
  const RecommendationPage({super.key});

  @override
  State<RecommendationPage> createState() => _RecommendationPageState();
}

class _RecommendationPageState extends State<RecommendationPage> {
  final _queryController = TextEditingController();
  final _regionResolver = RegionResolver();

  late final AiRecommender _recommender = AiRecommender(
    apiKey: _requireGeminiApiKey(),
    logResponses: true,
    logRequests: true,
  );

  late final TmdbClient _tmdbClient = TmdbClient(apiKey: _requireTmdbApiKey());

  bool _useLocation = false;
  String? _resolvedRegion;
  String? _regionSource;
  final Map<String, WatchProvidersResult> _watchProvidersByTitle = {};

  static String _requireGeminiApiKey() {
    final keyFromEnvFile = dotenv.env['GEMINI_API_KEY'];
    const keyFromDefine = String.fromEnvironment('GEMINI_API_KEY');
    final key = keyFromDefine.isNotEmpty ? keyFromDefine : keyFromEnvFile;
    if (key == null || key.isEmpty) {
      throw StateError(
        'Missing GEMINI_API_KEY. Add it to .env or run with '
        '--dart-define=GEMINI_API_KEY=YOUR_KEY',
      );
    }
    return key;
  }

  static String _requireTmdbApiKey() {
    final keyFromEnvFile = dotenv.env['TMDB_API_KEY'];
    const keyFromDefine = String.fromEnvironment('TMDB_API_KEY');
    final key = keyFromDefine.isNotEmpty ? keyFromDefine : keyFromEnvFile;
    if (key == null || key.isEmpty) {
      throw StateError(
        'Missing TMDB_API_KEY. Add it to .env or run with '
        '--dart-define=TMDB_API_KEY=YOUR_KEY',
      );
    }
    return key;
  }

  bool _isLoading = false;
  String? _errorMessage;
  List<Recommendation> _recommendations = const [];

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _resolveRegion() async {
    try {
      final result = await _regionResolver.resolve(useLocation: _useLocation);
      setState(() {
        _resolvedRegion = result.countryCode;
        _regionSource = result.source;
        _errorMessage = null;
      });
    } catch (error) {
      // Fallback to locale if anything goes wrong.
      final fallback = RegionResolutionResult(
        countryCode: 'US',
        source: 'locale',
      );
      setState(() {
        _resolvedRegion = fallback.countryCode;
        _regionSource = fallback.source;
        _errorMessage = null;
      });
    }
  }

  Future<void> _fetchRecommendations() async {
    if (_resolvedRegion == null) {
      await _resolveRegion();
    }

    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _errorMessage = 'Tell me what you want to watch.';
        _recommendations = const [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _watchProvidersByTitle.clear();
    });

    try {
      final results = await _recommender.getRecommendations(query: query);
      setState(() {
        _recommendations = results;
      });

      if (_resolvedRegion != null) {
        for (final recommendation in results) {
          final providers = await _tmdbClient.getWatchProviders(
            title: recommendation.title,
            region: _resolvedRegion!,
            type: recommendation.type,
          );
          if (providers != null) {
            setState(() {
              _watchProvidersByTitle[recommendation.title] = providers;
            });
          }
        }
      }
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
        _recommendations = const [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String? _tmdbImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/w92$path';
  }

  String? _tmdbPosterUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/w185$path';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Describe what you feel like watching.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _fetchRecommendations(),
              decoration: const InputDecoration(
                labelText: 'Your vibe or genre',
                hintText: 'e.g. cozy mystery with smart detectives',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _useLocation,
              onChanged: (value) {
                setState(() {
                  _useLocation = value;
                  _resolvedRegion = null;
                  _regionSource = null;
                });
              },
              title: const Text('Use current location for region'),
              subtitle: const Text(
                'Falls back to locale if permission denied.',
              ),
            ),
            if (_resolvedRegion != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Region: $_resolvedRegion (${_regionSource ?? 'locale'})',
                  style: theme.textTheme.labelMedium,
                ),
              ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _fetchRecommendations,
                icon: const Icon(Icons.auto_awesome),
                label: Text(_isLoading ? 'Thinking...' : 'Get recommendations'),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildResults(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_recommendations.isEmpty) {
      return Center(
        child: Text(
          'No recommendations yet. Try a new prompt.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      itemCount: _recommendations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final recommendation = _recommendations[index];
        final providers = _watchProvidersByTitle[recommendation.title];
        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_tmdbPosterUrl(providers?.posterPath) != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          _tmdbPosterUrl(providers?.posterPath)!,
                          width: 92,
                          height: 138,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: 92,
                        height: 138,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.movie,
                          size: 32,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recommendation.title,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            recommendation.type.toUpperCase(),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          if (providers?.rating != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star,
                                  size: 18,
                                  color: theme.colorScheme.secondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${providers!.rating!.toStringAsFixed(1)}/10',
                                  style: theme.textTheme.labelMedium,
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            recommendation.reason,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (providers != null && providers.providers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Where to watch (${providers.region}):',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: providers.providers.map((provider) {
                      final imageUrl = _tmdbImageUrl(provider.logoPath);
                      return Chip(
                        avatar: imageUrl != null
                            ? CircleAvatar(
                                backgroundImage: NetworkImage(imageUrl),
                                backgroundColor: Colors.transparent,
                              )
                            : null,
                        label: Text(provider.displayName),
                      );
                    }).toList(),
                  ),
                ] else if (providers != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Not available to watch with subscription or for free.',
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
