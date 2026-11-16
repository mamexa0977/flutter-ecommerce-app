/// Builds the /play location with proper query encoding.
String playLocation(String id,
    {required String title,
    int season = 1,
    int episode = 1,
    String? resourceId}) {
  return Uri(path: '/play/$id', queryParameters: {
    'title': title,
    'season': '$season',
    'episode': '$episode',
    if (resourceId != null) 'resource': resourceId,
  }).toString();
}
