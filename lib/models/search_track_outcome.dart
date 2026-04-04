import 'song.dart';

/// Result of a remote track search (Audius).
class SearchTrackOutcome {
  const SearchTrackOutcome._({
    required this.tracks,
    this.errorMessage,
  });

  final List<Song> tracks;
  final String? errorMessage;

  factory SearchTrackOutcome.success(List<Song> tracks) =>
      SearchTrackOutcome._(tracks: tracks);

  factory SearchTrackOutcome.networkUnavailable() => const SearchTrackOutcome._(
        tracks: [],
        errorMessage:
            'No internet connection. Check your network and try again.',
      );

  factory SearchTrackOutcome.apiFailure({int? statusCode}) =>
      SearchTrackOutcome._(
        tracks: [],
        errorMessage: statusCode != null
            ? 'Search service returned an error ($statusCode). Try again later.'
            : 'Search is temporarily unavailable. Please try again.',
      );

  factory SearchTrackOutcome.parseFailure() => const SearchTrackOutcome._(
        tracks: [],
        errorMessage:
            'Received an unexpected response from search. Please try again.',
      );
}
