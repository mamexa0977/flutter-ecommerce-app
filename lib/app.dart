import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/detail/detail_screen.dart';
import 'features/shell/main_shell.dart';
import 'features/player/player_screen.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const MainShell()),
    GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(
      path: '/detail/:id',
      builder: (_, s) => DetailScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/play/:id',
      builder: (_, s) {
        final q = s.uri.queryParameters;
        return PlayerScreen(
          key: ValueKey(
              '${s.pathParameters['id']}-${q['season']}-${q['episode']}'),
          id: s.pathParameters['id']!,
          title: q['title'] ?? '',
          season: int.tryParse(q['season'] ?? '') ?? 1,
          episode: int.tryParse(q['episode'] ?? '') ?? 1,
          resourceId: q['resource'],
          fresh: q['fresh'] == '1',
          localPath: q['local'],
        );
      },
    ),
  ],
);

class MovieApp extends StatelessWidget {
  const MovieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MovieBox',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFE50914),
        scaffoldBackgroundColor: const Color(0xFF0E0E10),
      ),
    );
  }
}