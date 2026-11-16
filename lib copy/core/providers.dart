import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Overridden in main() once SharedPreferences is loaded.
final sharedPrefsProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

final apiClientProvider =
    Provider<ApiClient>((ref) => ApiClient(ref.watch(sharedPrefsProvider)));

/// Home tabs: label -> backend endpoint.
const feedTabs = <String, String>{
  'Home': '/home',
  'Movies': '/movies',
  'Anime': '/anime',
  'Western': '/western',
  'Asian': '/asian',
  'Kids': '/kids',
};

final feedProvider = FutureProvider.autoDispose.family<List<Section>, String>(
    (ref, endpoint) => ref.watch(apiClientProvider).feed(endpoint));

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider.autoDispose<List<Movie>>((ref) {
  final q = ref.watch(searchQueryProvider).trim();
  if (q.isEmpty) return Future.value(<Movie>[]);
  return ref.watch(apiClientProvider).search(q);
});

final detailProvider = FutureProvider.autoDispose.family<MovieDetail, String>(
    (ref, id) => ref.watch(apiClientProvider).detail(id));

final episodesProvider = FutureProvider.autoDispose.family<List<Season>, String>(
    (ref, id) => ref.watch(apiClientProvider).episodes(id));
