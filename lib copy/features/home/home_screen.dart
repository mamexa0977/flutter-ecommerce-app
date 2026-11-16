import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _tab = feedTabs.keys.first;

  @override
  Widget build(BuildContext context) {
    final endpoint = feedTabs[_tab]!;
    final feed = ref.watch(feedProvider(endpoint));

    return Scaffold(
      appBar: AppBar(
        title: const Text('MovieBox', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () => context.push('/search')),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/settings')),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final t in feedTabs.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t),
                      selected: t == _tab,
                      onSelected: (_) => setState(() => _tab = t),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView('$e', onRetry: () => ref.invalidate(feedProvider(endpoint))),
        data: (sections) => sections.isEmpty
            ? ErrorView('Nothing to show here yet.', onRetry: () => ref.invalidate(feedProvider(endpoint)))
            : RefreshIndicator(
                onRefresh: () => ref.refresh(feedProvider(endpoint).future),
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  itemCount: sections.length,
                  itemBuilder: (_, i) => _SectionRow(sections[i]),
                ),
              ),
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow(this.section);
  final Section section;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(section.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      SizedBox(
        height: 235,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: section.items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: 125, child: MovieCard(section.items[i])),
        ),
      ),
    ]);
  }
}
