import 'dart:convert';

enum MediaKind { live, movie, series, episode }

enum SourceKind { m3u, xtream, file }

class Source {
  const Source({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
    this.username = '',
    this.password = '',
    this.epgUrl = '',
    this.refreshHours = 24,
    this.epgHours = 12,
    this.startup = true,
    this.epgStartup = true,
    this.connections = 2,
    this.providerConnections,
    this.updatedAt,
    this.epgUpdatedAt,
    this.epgOffsetMinutes = 0,
  });
  final String id, name, url, username, password, epgUrl;
  final SourceKind kind;
  final int refreshHours, epgHours, connections, epgOffsetMinutes;
  final int? providerConnections;
  int get connectionLimit => providerConnections ?? connections;
  final bool startup, epgStartup;
  final DateTime? updatedAt, epgUpdatedAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'url': url,
    'username': username,
    'password': password,
    'epgUrl': epgUrl,
    'refreshHours': refreshHours,
    'epgHours': epgHours,
    'startup': startup,
    'epgStartup': epgStartup,
    'connections': connections,
    'providerConnections': providerConnections,
    'updatedAt': updatedAt?.toIso8601String(),
    'epgUpdatedAt': epgUpdatedAt?.toIso8601String(),
    'epgOffsetMinutes': epgOffsetMinutes,
  };
  factory Source.fromJson(Map<String, dynamic> j) => Source(
    id: j['id'],
    name: j['name'],
    kind: SourceKind.values.byName(j['kind']),
    url: j['url'],
    username: j['username'] ?? '',
    password: j['password'] ?? '',
    epgUrl: j['epgUrl'] ?? '',
    refreshHours: j['refreshHours'] ?? 24,
    epgHours: j['epgHours'] ?? 12,
    startup: j['startup'] ?? true,
    epgStartup: j['epgStartup'] ?? true,
    connections: j['connections'] ?? 2,
    providerConnections: j['providerConnections'],
    epgOffsetMinutes: j['epgOffsetMinutes'] ?? 0,
    updatedAt: DateTime.tryParse(j['updatedAt'] ?? ''),
    epgUpdatedAt: DateTime.tryParse(j['epgUpdatedAt'] ?? ''),
  );
  Source withUpdate({DateTime? library, DateTime? epg}) => Source.fromJson({
    ...toJson(),
    'updatedAt': (library ?? updatedAt)?.toIso8601String(),
    'epgUpdatedAt': (epg ?? epgUpdatedAt)?.toIso8601String(),
  });
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.url,
    this.kind = MediaKind.live,
    this.group = 'Ungrouped',
    this.logo = '',
    this.epgId = '',
    this.providerId = '',
    this.parentId = '',
    this.season = 1,
    this.episode = 0,
    this.durationSeconds = 0,
    this.description = '',
    this.rating = 0,
    this.catchupDays = 0,
    this.catchupTemplate = '',
    this.headers = const {},
  });
  final String id,
      sourceId,
      name,
      url,
      group,
      logo,
      epgId,
      providerId,
      parentId,
      description,
      catchupTemplate;
  final MediaKind kind;
  final int rating, catchupDays;
  final int season, episode, durationSeconds;
  final Map<String, String> headers;
  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'name': name,
    'url': url,
    'kind': kind.name,
    'group': group,
    'logo': logo,
    'epgId': epgId,
    'providerId': providerId,
    'parentId': parentId,
    'season': season,
    'episode': episode,
    'durationSeconds': durationSeconds,
    'description': description,
    'rating': rating,
    'catchupDays': catchupDays,
    'catchupTemplate': catchupTemplate,
    'headers': headers,
  };
  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
    id: j['id'],
    sourceId: j['sourceId'],
    name: j['name'],
    url: j['url'],
    kind: MediaKind.values.byName(j['kind']),
    group: j['group'] ?? 'Ungrouped',
    logo: j['logo'] ?? '',
    epgId: j['epgId'] ?? '',
    providerId: j['providerId'] ?? '',
    parentId: j['parentId'] ?? '',
    season:
        j['season'] ??
        int.tryParse(
          RegExp(r'^S(\d+)').firstMatch(j['name'] ?? '')?.group(1) ?? '',
        ) ??
        1,
    episode:
        j['episode'] ??
        int.tryParse(
          RegExp(r'\bE(\d+)').firstMatch(j['name'] ?? '')?.group(1) ?? '',
        ) ??
        0,
    durationSeconds: j['durationSeconds'] ?? 0,
    description: j['description'] ?? '',
    rating: j['rating'] ?? 0,
    catchupDays: j['catchupDays'] ?? 0,
    catchupTemplate: j['catchupTemplate'] ?? '',
    headers: Map<String, String>.from(j['headers'] ?? {}),
  );
}

class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.passwordHash,
    this.admin = false,
    this.pin = false,
    bool discoverable = true,
    this.allowedSources = const [],
    this.blockedGroups = const [],
    this.blockedChannels = const [],
    this.maxRating = 100,
    this.allowUnrated = true,
    this.preferences = const {},
  }) : discoverable = !admin && discoverable;
  final String id, name, passwordHash;
  final bool admin, allowUnrated;
  final bool pin;
  final bool discoverable;
  bool get usesPin => !admin && pin;
  final List<String> allowedSources, blockedGroups, blockedChannels;
  final int maxRating;
  final Map<String, dynamic> preferences;
  bool allows(MediaItem item) =>
      admin ||
      ((allowedSources.isEmpty || allowedSources.contains(item.sourceId)) &&
          !blockedGroups.contains(item.group) &&
          !blockedChannels.contains(item.id) &&
          (item.rating == 0 ? allowUnrated : item.rating <= maxRating));
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'passwordHash': passwordHash,
    'admin': admin,
    'pin': usesPin,
    'discoverable': discoverable,
    'allowedSources': allowedSources,
    'blockedGroups': blockedGroups,
    'blockedChannels': blockedChannels,
    'maxRating': maxRating,
    'allowUnrated': allowUnrated,
    'preferences': preferences,
  };
  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'],
    name: j['name'],
    passwordHash: j['passwordHash'],
    admin: j['admin'] ?? false,
    pin: j['admin'] == true ? false : j['pin'] == true,
    discoverable: j['discoverable'] ?? true,
    allowedSources: List<String>.from(j['allowedSources'] ?? []),
    blockedGroups: List<String>.from(j['blockedGroups'] ?? []),
    blockedChannels: List<String>.from(j['blockedChannels'] ?? []),
    maxRating: j['maxRating'] ?? 100,
    allowUnrated: j['allowUnrated'] ?? true,
    preferences: j['preferences'] ?? {},
  );
}

class Programme {
  const Programme({
    required this.id,
    required this.sourceId,
    required this.channelId,
    required this.title,
    required this.start,
    required this.end,
    this.description = '',
    this.rating = 0,
  });
  final String id, sourceId, channelId, title, description;
  final DateTime start, end;
  final int rating;
  bool get isNow =>
      !start.isAfter(DateTime.now()) && end.isAfter(DateTime.now());
  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'channelId': channelId,
    'title': title,
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
    'description': description,
    'rating': rating,
  };
  factory Programme.fromJson(Map<String, dynamic> j) => Programme(
    id: j['id'],
    sourceId: j['sourceId'],
    channelId: j['channelId'],
    title: j['title'],
    start: DateTime.fromMillisecondsSinceEpoch(j['start'], isUtc: true),
    end: DateTime.fromMillisecondsSinceEpoch(j['end'], isUtc: true),
    description: j['description'] ?? '',
    rating: j['rating'] ?? 0,
  );
}

Map<String, dynamic> decodeMap(String value) =>
    Map<String, dynamic>.from(jsonDecode(value));
