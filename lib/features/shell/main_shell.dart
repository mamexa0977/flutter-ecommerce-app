import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download_manager.dart';
import '../downloads/downloads_screen.dart';
import '../home/home_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

/// Which bottom tab is selected (0 Home, 1 Search, 2 Downloads, 3 Settings).
final mainTabProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  // Tabs are built the first time you open them, then kept alive.
  // (Search auto-focuses its text field, so it must not be built at start-up.)
  final Set<int> _visited = {0};

  Widget _page(int i) {
    switch (i) {
      case 0:
        return const HomeScreen();
      case 1:
        return const SearchScreen();
      case 2:
        return const DownloadsScreen();
      default:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(mainTabProvider);
    _visited.add(index);
    final active = ref.watch(downloadManagerProvider.select((l) => l.where((t) => t.isActive).length));

    return PopScope(
      // Back button: go to Home first, then leave the app.
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(mainTabProvider.notifier).state = 0;
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: [
            for (var i = 0; i < 4; i++)
              _visited.contains(i) ? _page(i) : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          backgroundColor: const Color(0xFF151518),
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) => ref.read(mainTabProvider.notifier).state = i,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.search_rounded),
              selectedIcon: Icon(Icons.search_rounded),
              label: 'Search',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: active > 0,
                label: Text('$active'),
                child: const Icon(Icons.download_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: active > 0,
                label: Text('$active'),
                child: const Icon(Icons.download_rounded),
              ),
              label: 'Downloads',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}