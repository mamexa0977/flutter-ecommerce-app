import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../widgets/common.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _set(String v) => ref.read(searchQueryProvider.notifier).state = v;

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider).trim();
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
              hintText: 'Search movies & series', border: InputBorder.none),
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 450), () => _set(v));
          },
          onSubmitted: (v) {
            _debounce?.cancel();
            _set(v);
          },
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                _set('');
                setState(() {});
              },
            ),
        ],
      ),
      body: query.isEmpty
          ? const Center(child: Text('Type something to search'))
          : results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView('$e', onRetry: () => ref.invalidate(searchResultsProvider)),
              data: (items) => items.isEmpty
                  ? Center(child: Text('No results for "$query"'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 150,
                        childAspectRatio: 0.52,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => MovieCard(items[i]),
                    ),
            ),
    );
  }
}
