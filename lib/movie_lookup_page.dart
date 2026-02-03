import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'region_resolver.dart';
import 'tmdb_client.dart';

class MovieLookupPage extends StatefulWidget {
  const MovieLookupPage({super.key});

  @override
  State<MovieLookupPage> createState() => _MovieLookupPageState();
}

class _MovieLookupPageState extends State<MovieLookupPage> {
  final _queryController = TextEditingController();
  final _regionResolver = RegionResolver();
  late final TmdbClient _tmdbClient = TmdbClient(apiKey: _requireTmdbApiKey());

  bool _useLocation = false;
  String _type = 'movie';
  String? _resolvedRegion;
  String? _regionSource;

  bool _isSearching = false;
  String? _errorMessage;
  List<SearchResult> _matches = const [];
  SearchResult? _selected;

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
    } catch (_) {
      setState(() {
        _resolvedRegion = 'US';
        _regionSource = 'locale';
      });
    }
  }

  Future<void> _lookup() async {
    if (_resolvedRegion == null) {
      await _resolveRegion();
    }

    final title = _queryController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _errorMessage = 'Enter a title to look up.';
        _matches = const [];
        _selected = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _matches = const [];
      _selected = null;
    });

    try {
      final results = await _tmdbClient.searchTitles(
        title: title,
        mediaType: _type,
        limit: 10,
      );

      if (results.isEmpty) {
        setState(() {
          _errorMessage = 'No results found for "$title".';
          _matches = const [];
        });
      } else {
        setState(() {
          _matches = results;
        });
      }
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
        _matches = const [];
        _selected = null;
      });
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _openResultPage(SearchResult match) async {
    if (_resolvedRegion == null) {
      await _resolveRegion();
    }

    setState(() => _selected = match);

    if (!mounted) return;
    final region = _resolvedRegion ?? 'US';

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LookupResultPage(
          match: match,
          region: region,
          tmdbClient: _tmdbClient,
        ),
      ),
    );
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
              'Look up a movie or TV show to see where to watch it.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _lookup(),
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Inception',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    value: 'movie',
                    groupValue: _type,
                    onChanged: (value) => setState(() {
                      _type = value ?? 'movie';
                      _matches = const [];
                      _selected = null;
                      _errorMessage = null;
                    }),
                    title: const Text('Movie'),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    value: 'tv',
                    groupValue: _type,
                    onChanged: (value) => setState(() {
                      _type = value ?? 'tv';
                      _matches = const [];
                      _selected = null;
                      _errorMessage = null;
                    }),
                    title: const Text('TV'),
                  ),
                ),
              ],
            ),
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSearching ? null : _lookup,
                icon: const Icon(Icons.search),
                label: Text(
                  _isSearching ? 'Searching...' : 'Find where to watch',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildResult(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(ThemeData theme) {
    if (_isSearching) {
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

    if (_matches.isEmpty) {
      return Center(
        child: Text(
          'No lookup yet. Try a title.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView(
      children: [
        if (_matches.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Tap a result to see where to watch it:',
              style: theme.textTheme.labelLarge,
            ),
          ),
          ..._matches.map((match) => _buildMatchTile(match, theme)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildMatchTile(SearchResult match, ThemeData theme) {
    final isSelected = _selected?.id == match.id;
    final posterUrl = _tmdbPosterUrl(match.posterPath);

    return Card(
      elevation: isSelected ? 3 : 1,
      color: isSelected ? theme.colorScheme.surfaceVariant : null,
      child: ListTile(
        onTap: () => _openResultPage(match),
        leading: posterUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  posterUrl,
                  width: 48,
                  height: 72,
                  fit: BoxFit.cover,
                ),
              )
            : Icon(Icons.movie, color: theme.colorScheme.onSurfaceVariant),
        title: Text(match.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              match.mediaType.toUpperCase(),
              style: theme.textTheme.labelMedium,
            ),
            if (match.releaseYear != null)
              Text(
                '• ${match.releaseYear}',
                style: theme.textTheme.labelMedium,
              ),
            if (match.rating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, size: 16),
                  const SizedBox(width: 2),
                  Text(
                    match.rating!.toStringAsFixed(1),
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class LookupResultPage extends StatefulWidget {
  const LookupResultPage({
    super.key,
    required this.match,
    required this.region,
    required this.tmdbClient,
  });

  final SearchResult match;
  final String region;
  final TmdbClient tmdbClient;

  @override
  State<LookupResultPage> createState() => _LookupResultPageState();
}

class _LookupResultPageState extends State<LookupResultPage> {
  late final Future<_LookupData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_LookupData> _load() async {
    final details = await widget.tmdbClient.getTitleDetails(
      id: widget.match.id,
      mediaType: widget.match.mediaType,
    );

    final providers = await widget.tmdbClient.getWatchProvidersById(
      id: widget.match.id,
      title: details.title,
      mediaType: details.mediaType,
      region: widget.region,
      rating: details.rating ?? widget.match.rating,
      posterPath: details.posterPath ?? widget.match.posterPath,
    );

    return _LookupData(details: details, providers: providers);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.match.title)),
      body: FutureBuilder<_LookupData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load details.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final details = data.details;
          final providers = data.providers;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(details: details),
                const SizedBox(height: 12),
                _Summary(details: details),
                const SizedBox(height: 16),
                _ProviderSection(
                  title: 'Stream or free (${widget.region.toUpperCase()})',
                  providers: providers?.streamOrFree ?? const [],
                ),
                const SizedBox(height: 12),
                _ProviderSection(
                  title: 'Rent (${widget.region.toUpperCase()})',
                  providers: providers?.rent ?? const [],
                ),
                const SizedBox(height: 12),
                _ProviderSection(
                  title: 'Buy (${widget.region.toUpperCase()})',
                  providers: providers?.buy ?? const [],
                ),
                if (providers == null ||
                    (providers.streamOrFree.isEmpty &&
                        providers.rent.isEmpty &&
                        providers.buy.isEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No watch providers available in this region.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String? _tmdbImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/w92$path';
  }
}

class _LookupData {
  const _LookupData({required this.details, required this.providers});
  final TitleDetails details;
  final WatchProvidersResult? providers;
}

class _ProviderSection extends StatelessWidget {
  const _ProviderSection({
    required this.title,
    required this.providers,
  });

  final String title;
  final List<WatchProvider> providers;

  String? _tmdbImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/w92$path';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (providers.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: providers
                .map(
                  (provider) => Chip(
                    avatar: _tmdbImageUrl(provider.logoPath) != null
                        ? CircleAvatar(
                            backgroundImage: NetworkImage(
                              _tmdbImageUrl(provider.logoPath)!,
                            ),
                            backgroundColor: Colors.transparent,
                          )
                        : null,
                    label: Text(provider.displayName),
                  ),
                )
                .toList(),
          )
        else
          Text('No options available.', style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.details});
  final TitleDetails details;

  String? _tmdbPosterUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/w185$path';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_tmdbPosterUrl(details.posterPath) != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              _tmdbPosterUrl(details.posterPath)!,
              width: 110,
              height: 165,
              fit: BoxFit.cover,
            ),
          )
        else
          Container(
            width: 110,
            height: 165,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.movie, color: theme.colorScheme.onSurfaceVariant),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(details.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    details.mediaType.toUpperCase(),
                    style: theme.textTheme.labelMedium,
                  ),
                  if (details.releaseYear != null)
                    Text(
                      '• ${details.releaseYear}',
                      style: theme.textTheme.labelMedium,
                    ),
                  if (details.rating != null)
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
                          details.rating!.toStringAsFixed(1),
                          style: theme.textTheme.labelMedium,
                        ),
                      ],
                    ),
                  if (details.runtimeMinutes != null)
                    Text(
                      '${details.runtimeMinutes} min',
                      style: theme.textTheme.labelMedium,
                    ),
                ],
              ),
              if (details.genres.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: details.genres
                      .map((g) => Chip(label: Text(g)))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.details});
  final TitleDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasOverview =
        details.overview != null && details.overview!.trim().isNotEmpty;
    final tagline = details.tagline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tagline != null && tagline.isNotEmpty) ...[
          Text(
            '“$tagline”',
            style: theme.textTheme.titleSmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          hasOverview ? details.overview! : 'No summary available.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}
