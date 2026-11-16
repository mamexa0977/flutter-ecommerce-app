import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/subtitle_service.dart';
import '../../models/models.dart';

/// What the user picked in the sheet.
class SubtitleChoice {
  const SubtitleChoice.off()
      : label = 'Off',
        url = null,
        data = null,
        language = null;
  const SubtitleChoice.url(this.url, this.label)
      : data = null,
        language = null;
  const SubtitleChoice.data(this.data, this.label, this.language) : url = null;

  final String label;
  final String? url; // remote subtitle file (backend provided)
  final String? data; // subtitle text (downloaded from SubDL)
  final String? language;
  bool get isOff => url == null && data == null;
}

Future<SubtitleChoice?> showSubtitleSheet(
  BuildContext context, {
  required String title,
  required bool series,
  required int season,
  required int episode,
  required List<SubtitleItem> builtIn,
  required List<SubtitleChoice> downloaded,
  required String? activeLabel,
  required double scale,
  required ValueChanged<double> onScale,
}) {
  return showModalBottomSheet<SubtitleChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SubtitleSheet(
      title: title,
      series: series,
      season: season,
      episode: episode,
      builtIn: builtIn,
      downloaded: downloaded,
      activeLabel: activeLabel,
      scale: scale,
      onScale: onScale,
    ),
  );
}

class _SubtitleSheet extends ConsumerStatefulWidget {
  const _SubtitleSheet({
    required this.title,
    required this.series,
    required this.season,
    required this.episode,
    required this.builtIn,
    required this.downloaded,
    required this.activeLabel,
    required this.scale,
    required this.onScale,
  });
  final String title;
  final bool series;
  final int season, episode;
  final List<SubtitleItem> builtIn;
  final List<SubtitleChoice> downloaded;
  final String? activeLabel;
  final double scale;
  final ValueChanged<double> onScale;

  @override
  ConsumerState<_SubtitleSheet> createState() => _SubtitleSheetState();
}

class _SubtitleSheetState extends ConsumerState<_SubtitleSheet> {
  late final TextEditingController _query = TextEditingController(text: widget.title);
  final TextEditingController _key = TextEditingController();
  late String _lang = ref.read(subtitleServiceProvider).language;
  late double _scale = widget.scale;

  bool _editingKey = false;
  bool _searching = false;
  String? _error;
  SubSearchResult? _result;
  OnlineSub? _downloading;

  @override
  void dispose() {
    _query.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    await ref.read(subtitleServiceProvider).setApiKey(_key.text);
    if (!mounted) return;
    setState(() => _editingKey = false);
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _result = null;
    });
    try {
      final svc = ref.read(subtitleServiceProvider);
      await svc.setLanguage(_lang);
      final r = await svc.search(q,
          series: widget.series,
          season: widget.season,
          episode: widget.episode,
          language: _lang);
      if (!mounted) return;
      setState(() {
        _result = r;
        if (r.subs.isEmpty) {
          _error = 'No subtitles found. Try a shorter title or another language.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _download(OnlineSub s) async {
    if (_downloading != null) return;
    setState(() {
      _downloading = s;
      _error = null;
    });
    try {
      final d = await ref.read(subtitleServiceProvider).download(s,
          season: widget.series ? widget.season : null,
          episode: widget.series ? widget.episode : null);
      if (!mounted) return;
      Navigator.pop(context, SubtitleChoice.data(d.text, d.label, d.language));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _downloading = null;
        });
      }
    }
  }

  Widget _choiceTile(String label, SubtitleChoice choice, {IconData? icon}) {
    final active = widget.activeLabel == label ||
        (choice.isOff && widget.activeLabel == null);
    return ListTile(
      dense: true,
      leading: Icon(icon ?? Icons.subtitles_outlined, size: 20),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: active ? const Icon(Icons.check, size: 20) : null,
      onTap: () => Navigator.pop(context, choice),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.watch(subtitleServiceProvider);
    final hasKey = svc.apiKey.isNotEmpty && !_editingKey;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        shrinkWrap: true,
        children: [
          const Text('Subtitles',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _choiceTile('Off', const SubtitleChoice.off(), icon: Icons.subtitles_off_outlined),
          for (final s in widget.builtIn)
            _choiceTile(s.label, SubtitleChoice.url(s.url, s.label)),
          for (final d in widget.downloaded)
            _choiceTile(d.label, d, icon: Icons.download_done_rounded),

          const Divider(height: 28),
          const Text('Text size', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0.8, label: Text('S')),
              ButtonSegment(value: 1.0, label: Text('M')),
              ButtonSegment(value: 1.25, label: Text('L')),
              ButtonSegment(value: 1.6, label: Text('XL')),
              ButtonSegment(value: 2.0, label: Text('XXL')),
            ],
            selected: {_scale},
            onSelectionChanged: (v) {
              setState(() => _scale = v.first);
              svc.setScale(v.first);
              widget.onScale(v.first);
            },
          ),

          const Divider(height: 28),
          Row(children: [
            const Expanded(
              child: Text('Find subtitles online',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (svc.apiKey.isNotEmpty && !_editingKey)
              TextButton(
                onPressed: () => setState(() {
                  _key.text = svc.apiKey;
                  _editingKey = true;
                }),
                child: const Text('Change key'),
              ),
          ]),
          const SizedBox(height: 8),
          if (!hasKey) ...[
            const Text(
              'Powered by SubDL (free). Make a free account at subdl.com, open '
              'Account \u2192 API, and paste your API key here. You only do this once.',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _key,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'SubDL API key',
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _saveKey, child: const Text('Save key')),
            ),
          ] else ...[
            TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: widget.series
                    ? 'Title (S${widget.season} \u00B7 E${widget.episode})'
                    : 'Title',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searching ? null : _search,
                ),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: kSubLanguages.containsKey(_lang) ? _lang : 'EN',
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Language',
                isDense: true,
              ),
              items: [
                for (final e in kSubLanguages.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _lang = v ?? 'EN'),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _searching ? null : _search,
                icon: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                label: const Text('Search'),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            if (_result != null && _result!.subs.isNotEmpty) ...[
              if (_result!.matchedTitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text('Matched: ${_result!.matchedTitle}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              for (final s in _result!.subs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.releaseName, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      if (s.language.isNotEmpty) s.language.toUpperCase(),
                      if (s.author.isNotEmpty) s.author,
                      if (s.hi) 'HI',
                      if (s.fullSeason) 'season pack',
                    ].join(' \u00B7 '),
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  trailing: _downloading == s
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_rounded),
                  onTap: _downloading == null ? () => _download(s) : null,
                ),
            ],
          ],
        ],
      ),
    );
  }
}