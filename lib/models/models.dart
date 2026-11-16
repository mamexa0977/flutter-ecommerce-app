String _s(dynamic v, [String d = '']) => v == null ? d : v.toString();
int? _i(dynamic v) => v is int ? v : int.tryParse(_s(v));
String? _url(dynamic v) {
  final s = _s(v).trim();
  if (s.isEmpty || s == 'null') return null;
  return s.startsWith('//') ? 'https:$s' : s;
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _list(dynamic v) => v is List ? v : const [];

/// A movie / series card as returned by the backend's `map_item`.
class Movie {
  final String id;
  final String title;
  final String? cover;
  final String score;
  final String year;
  final int type; // 1 = movie, 2 = series (others: music, short tv...)
  final String? runtime;
  final String description;
  final String actionType; // movie | category | playlist

  const Movie({
    required this.id,
    required this.title,
    this.cover,
    this.score = 'N/A',
    this.year = 'N/A',
    this.type = 1,
    this.runtime,
    this.description = '',
    this.actionType = 'movie',
  });

  bool get isMovie => type == 1;

  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
        id: _s(j['subjectId'] ?? j['id']),
        title: _s(j['title'], 'Unknown'),
        cover: _url(j['cover']) ?? _url(j['poster']),
        score: _s(j['score'], 'N/A'),
        year: _s(j['releaseTime'], 'N/A'),
        type: _i(j['subjectType']) ?? 1,
        runtime: j['runtime'] == null ? null : _s(j['runtime']),
        description: _s(j['description']),
        actionType: _s(j['actionType'], 'movie'),
      );
}

class Section {
  final String title;
  final List<Movie> items;
  const Section(this.title, this.items);

  factory Section.fromJson(Map<String, dynamic> j) => Section(
        _s(j['title'], 'Section'),
        _list(j['items'])
            .whereType<Map>()
            .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
            .where((m) => m.id.isNotEmpty && m.actionType == 'movie')
            .toList(),
      );
}

class CastMember {
  final String name, role, avatar;
  const CastMember(this.name, this.role, this.avatar);
}

/// A dub (separate subject) or a resource track (same subject, other resourceId).
class LanguageOption {
  final String name;
  final String type; // dub | resource
  final String? resourceId;
  final String? subjectId;
  const LanguageOption(this.name, this.type, this.resourceId, this.subjectId);
}

class MovieDetail {
  final Movie movie;
  final List<CastMember> cast;
  final List<LanguageOption> languages;
  final List<Movie> collection;
  final bool isCollection;
  const MovieDetail(
      this.movie, this.cast, this.languages, this.collection, this.isCollection);

  factory MovieDetail.fromJson(Map<String, dynamic> j) => MovieDetail(
        Movie.fromJson(j),
        _list(j['cast'])
            .whereType<Map>()
            .map((c) =>
                CastMember(_s(c['name']), _s(c['role']), _s(c['avatar'])))
            .toList(),
        _list(j['languages'])
            .whereType<Map>()
            .map((l) => LanguageOption(
                  _s(l['name'], 'Audio'),
                  _s(l['type']),
                  l['id'] == null ? null : _s(l['id']),
                  l['subjectId'] == null ? null : _s(l['subjectId']),
                ))
            .toList(),
        _list(j['collectionItems'])
            .whereType<Map>()
            .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
            .where((m) => m.id.isNotEmpty)
            .toList(),
        j['isCollection'] == true,
      );
}

class Episode {
  final int number;
  final String title;
  const Episode(this.number, this.title);
}

class Season {
  final int number;
  final List<Episode> episodes;
  const Season(this.number, this.episodes);

  static List<Season> parse(Map<String, dynamic> res) {
    final out = <Season>[];
    for (final raw in _list(_map(res['data'])['seasons'])) {
      final m = _map(raw);
      final eps = _list(m['episodes'])
          .map(_map)
          .map((e) => Episode(_i(e['episodeNumber']) ?? 0, _s(e['title'])))
          .where((e) => e.number > 0)
          .toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      if (eps.isNotEmpty) out.add(Season(_i(m['seasonNumber']) ?? 1, eps));
    }
    out.sort((a, b) => a.number.compareTo(b.number));
    return out;
  }
}

class SubtitleItem {
  final String url, label;
  const SubtitleItem(this.url, this.label);
}

/// Response of the backend's `/play/{id}` endpoint.
class PlayInfo {
  final String url;
  final Map<String, String> headers;
  final String cookie;
  final List<SubtitleItem> subtitles;
  final String? subtitleUrl;
  final String? quality; // quality of the stream the server picked
  final List<String> qualities; // all qualities the server knows about

  const PlayInfo(this.url, this.headers, this.cookie, this.subtitles,
      this.subtitleUrl, this.quality, this.qualities);

  factory PlayInfo.fromJson(Map<String, dynamic> j) => PlayInfo(
        _s(j['url']),
        _map(j['headers']).map((k, v) => MapEntry(k, _s(v))),
        _s(j['cookie']),
        _list(j['subtitles'])
            .map(_map)
            .where((s) => _url(s['url']) != null)
            .map((s) => SubtitleItem(
                _url(s['url'])!, _s(s['lanName'] ?? s['lan'], 'Subtitle')))
            .toList(),
        _url(j['subtitleUrl']),
        j['quality'] == null ? null : _s(j['quality']),
        _list(j['qualityList']).map(_s).where((q) => q.isNotEmpty).toList(),
      );
}
