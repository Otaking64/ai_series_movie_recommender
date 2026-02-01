# series_movie_recommender

AI-GEN tv and movie recommendation application using Gemini API.

## Getting Started

### Prerequisites

- Flutter SDK installed.
- Gemini API key from Google AI Studio.
- TMDB API key for watch-provider lookups.

### Setup

Create a local `.env` file (this file is ignored by Git):

```
GEMINI_API_KEY=YOUR_KEY_HERE
TMDB_API_KEY=YOUR_KEY_HERE
```

Then run:

```sh
flutter pub get
flutter run
```

Alternatively, pass the keys at runtime:

```sh
flutter run \
  --dart-define=GEMINI_API_KEY=YOUR_KEY_HERE \
  --dart-define=TMDB_API_KEY=YOUR_KEY_HERE
```

### Usage

Enter a description of what you want to watch and tap "Get recommendations".
Toggle "Use current location" to resolve the region by GPS; otherwise locale is used.

## Notes

- The app calls the Gemini model for recommendations and TMDB for watch providers.
- If you see a missing key error, confirm `GEMINI_API_KEY` and `TMDB_API_KEY`.
