import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../core/models.dart';

String stableId(String source, String identity) =>
    '$source:${sha256.convert(utf8.encode(identity)).toString().substring(0, 24)}';
Uri providerUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException(
      'Enter an http:// or https:// provider URL without embedded credentials.',
    );
  }
  return uri;
}

class ConnectionCheck {
  const ConnectionCheck(this.message, {this.maximum, this.active});
  final String message;
  final int? maximum, active;
}

class ProviderClient {
  ProviderClient({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  final discoveredEpg = <String, String>{};
  final accounts = <String, ConnectionCheck>{};

  Source withAccount(Source source) => Source.fromJson({
    ...source.toJson(),
    'providerConnections': accounts[source.id]?.maximum,
  });

  Source? accountSource(Source source) {
    if (source.kind == SourceKind.xtream) return source;
    if (source.kind != SourceKind.m3u) return null;
    final uri = providerUri(source.url);
    // Only contact the same provider when its URL explicitly identifies Xtream.
    if (!uri.path.endsWith('/get.php') ||
        !uri.queryParameters.containsKey('username') ||
        !uri.queryParameters.containsKey('password')) {
      return null;
    }
    return Source.fromJson({
      ...source.toJson(),
      'kind': 'xtream',
      'username': uri.queryParameters['username'],
      'password': uri.queryParameters['password'],
    });
  }

  Future<ConnectionCheck> account(Source source) async {
    final raw = jsonDecode(
      utf8.decode(await download(endpoint(source, ''), maxBytes: 1024 * 1024)),
    );
    final info = raw is Map ? raw['user_info'] : null;
    if (info is! Map || '${info['auth']}' != '1') {
      throw const FormatException('Provider rejected the Xtream credentials.');
    }
    final status = '${info['status'] ?? ''}'.toLowerCase();
    if (status.isNotEmpty && status != 'active') {
      throw const FormatException('The provider account is not active.');
    }
    final maximum = int.tryParse('${info['max_connections']}');
    final active = int.tryParse('${info['active_cons']}');
    final result = ConnectionCheck(
      'Connected. Provider account is active.',
      maximum: maximum != null && maximum > 0 ? maximum : null,
      active: active != null && active >= 0 ? active : null,
    );
    accounts[source.id] = result;
    return result;
  }

  /// A bounded playlist sample, not a catalog import or a playback guarantee.
  Future<ConnectionCheck> testConnection(
    Source source, {
    String? fileText,
  }) async {
    accounts.remove(source.id);
    final accountDetails = accountSource(source);
    if (source.kind == SourceKind.xtream) return account(source);
    if (source.kind == SourceKind.file && fileText == null) {
      throw const FormatException('Choose an M3U file to test.');
    }
    var sample = fileText;
    if (sample == null) {
      try {
        final response = await client
            .send(http.Request('GET', providerUri(source.url)))
            .timeout(const Duration(seconds: 25));
        if (response.statusCode != 200) {
          await response.stream.listen(null).cancel();
          throw FormatException(
            'Provider returned HTTP ${response.statusCode}.',
          );
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 15),
        )) {
          final remaining = 256 * 1024 - bytes.length;
          bytes.add(
            chunk.length > remaining ? chunk.sublist(0, remaining) : chunk,
          );
          if (bytes.length >= 256 * 1024) break;
        }
        sample = utf8.decode(bytes.takeBytes(), allowMalformed: true);
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException(
          'Provider could not be reached. Check the address and browser CORS/HTTPS support.',
        );
      }
    }
    parseM3u({
      'source': source.id,
      'text': sample,
      'base': source.kind == SourceKind.file ? '' : source.url,
    });
    if (accountDetails != null) {
      try {
        return await account(accountDetails);
      } catch (_) {
        /* M3U can work without the account API. */
      }
    }
    return const ConnectionCheck(
      'Playlist is reachable and contains playable URLs. No connection limit was reported; the fallback will be used.',
    );
  }

  Future<Uint8List> download(Uri url, {int maxBytes = 64 * 1024 * 1024}) async {
    try {
      final response = await client
          .send(http.Request('GET', url))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw FormatException('Provider returned HTTP ${response.statusCode}.');
      }
      if ((response.contentLength ?? 0) > maxBytes) {
        throw const FormatException('Feed exceeds the configured size limit.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const FormatException(
            'Feed exceeds the configured size limit.',
          );
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Provider could not be reached. Check the address, connection, and browser CORS/HTTPS support.',
      );
    }
  }

  Uri endpoint(
    Source s,
    String action, {
    Map<String, String> extra = const {},
  }) {
    final base = providerUri(s.url);
    final path = base.path
        .replaceAll(RegExp(r'/(player_api\.php|xmltv\.php|get\.php)/?$'), '')
        .replaceAll(RegExp(r'/$'), '');
    return base.replace(
      path: '$path/player_api.php',
      queryParameters: {
        'username': s.username,
        'password': s.password,
        'action': action,
        ...extra,
      },
    );
  }

  Future<dynamic> api(
    Source s,
    String action, {
    Map<String, String> extra = const {},
  }) async {
    try {
      return jsonDecode(
        utf8.decode(await download(endpoint(s, action, extra: extra))),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Provider returned invalid JSON.');
    }
  }

  Future<List<MediaItem>> load(
    Source source, {
    String? fileText,
    void Function(String)? onProgress,
  }) async {
    accounts.remove(source.id);
    onProgress?.call('Downloading playlist');
    if (source.kind != SourceKind.xtream) {
      final text =
          fileText ??
          utf8.decode(
            await download(providerUri(source.url)),
            allowMalformed: true,
          );
      final header = const LineSplitter().convert(text).firstOrNull ?? '';
      final match = RegExp(
        '(?:x-tvg-url|url-tvg|tvg-url)="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(header);
      if (match != null) {
        discoveredEpg[source.id] = match
            .group(1)!
            .split(',')
            .map((v) => v.trim())
            .join('\n');
      }
      final accountDetails = accountSource(source);
      if (accountDetails != null) {
        try {
          await account(accountDetails);
        } catch (_) {
          /* Optional for M3U. */
        }
      }
      onProgress?.call('Parsing playlist');
      return compute(parseM3u, {
        'source': source.id,
        'text': text,
        'base': source.kind == SourceKind.file ? '' : source.url,
      });
    }
    await account(source);
    final result = <MediaItem>[];
    for (final entry in [
      ('live', MediaKind.live),
      ('vod', MediaKind.movie),
      ('series', MediaKind.series),
    ]) {
      onProgress?.call(
        'Downloading ${entry.$1 == 'vod' ? 'movies' : entry.$1} catalog',
      );
      final categories = await api(source, 'get_${entry.$1}_categories');
      final groups = <String, String>{};
      if (categories is List) {
        for (final c in categories) {
          groups['${c['category_id']}'] = '${c['category_name']}';
        }
      }
      final streams = await api(
        source,
        entry.$1 == 'series' ? 'get_series' : 'get_${entry.$1}_streams',
      );
      if (streams is! List) {
        throw const FormatException('Provider returned an invalid catalog.');
      }
      for (final raw in streams) {
        final id = '${raw[entry.$1 == 'series' ? 'series_id' : 'stream_id']}';
        final extension =
            '${raw['container_extension'] ?? (entry.$1 == 'live' ? 'ts' : 'mp4')}';
        final url = entry.$1 == 'series'
            ? ''
            : streamUrl(
                source,
                entry.$1 == 'vod' ? 'movie' : entry.$1,
                id,
                extension,
              );
        result.add(
          MediaItem(
            id: stableId(source.id, '${entry.$1}:$id'),
            sourceId: source.id,
            name: '${raw['name'] ?? 'Untitled'}',
            url: url,
            kind: entry.$2,
            providerId: id,
            group: groups['${raw['category_id']}'] ?? 'Ungrouped',
            logo: '${raw['stream_icon'] ?? raw['cover'] ?? ''}',
            epgId: '${raw['epg_channel_id'] ?? ''}',
            description: '${raw['plot'] ?? ''}',
            rating: raw['is_adult'] == '1' || raw['is_adult'] == 1 ? 18 : 0,
            catchupDays: '${raw['tv_archive']}' == '1'
                ? int.tryParse('${raw['tv_archive_duration']}') ?? 0
                : 0,
          ),
        );
      }
    }
    return result;
  }

  String streamUrl(Source s, String type, String id, String extension) {
    final base = providerUri(s.url);
    final path = base.path
        .replaceAll(RegExp(r'/(player_api\.php|get\.php)/?$'), '')
        .replaceAll(RegExp(r'/$'), '');
    return base
        .replace(
          path:
              '$path/$type/${Uri.encodeComponent(s.username)}/${Uri.encodeComponent(s.password)}/$id.$extension',
          query: '',
          fragment: '',
        )
        .toString();
  }

  Future<List<MediaItem>> episodes(Source s, MediaItem series) async {
    final result = await api(
      s,
      'get_series_info',
      extra: {'series_id': series.providerId},
    );
    final seasons = result['episodes'];
    if (seasons is! Map) {
      throw const FormatException('No episodes were returned.');
    }
    final items = <MediaItem>[];
    for (final season in seasons.entries) {
      for (final e in season.value as List) {
        final id = '${e['id']}';
        items.add(
          MediaItem(
            id: stableId(s.id, 'episode:$id'),
            sourceId: s.id,
            parentId: series.id,
            season: int.tryParse('${e['season'] ?? season.key}') ?? 1,
            episode: int.tryParse('${e['episode_num']}') ?? 0,
            durationSeconds:
                int.tryParse('${e['info']?['duration_secs']}') ?? 0,
            name:
                'S${season.key.toString().padLeft(2, '0')} · E${'${e['episode_num'] ?? ''}'.padLeft(2, '0')}  ${e['title'] ?? series.name}',
            url: streamUrl(
              s,
              'series',
              id,
              '${e['container_extension'] ?? 'mp4'}',
            ),
            kind: MediaKind.episode,
            providerId: id,
            group: series.group,
            rating: series.rating,
            logo: '${e['info']?['movie_image'] ?? series.logo}',
            description: '${e['info']?['plot'] ?? ''}',
          ),
        );
      }
    }
    return items;
  }

  Future<List<Programme>> epg(
    Source source, {
    int pastDays = 2,
    int futureDays = 7,
  }) async {
    final urls = <Uri>[];
    if (source.epgUrl.trim().isNotEmpty) {
      urls.addAll(
        source.epgUrl
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map(providerUri),
      );
    } else if (source.kind == SourceKind.xtream) {
      urls.add(
        endpoint(source, '').replace(
          path: endpoint(
            source,
            '',
          ).path.replaceFirst('player_api.php', 'xmltv.php'),
          queryParameters: {
            'username': source.username,
            'password': source.password,
          },
        ),
      );
    } else {
      return [];
    }
    final merged = <String, Programme>{};
    for (final url in urls) {
      final bytes = await download(url, maxBytes: 64 * 1024 * 1024);
      final programmes = await compute(parseXmltv, {
        'source': source.id,
        'bytes': bytes,
        'offset': source.epgOffsetMinutes,
        'from': DateTime.now()
            .subtract(Duration(days: pastDays))
            .millisecondsSinceEpoch,
        'to': DateTime.now()
            .add(Duration(days: futureDays))
            .millisecondsSinceEpoch,
      });
      // Earlier feeds win for a matching channel/start identity.
      for (final programme in programmes) {
        merged.putIfAbsent(programme.id, () => programme);
      }
    }
    return merged.values.toList();
  }

  String catchupUrl(Source source, MediaItem item, Programme p) {
    if (item.catchupDays <= 0 ||
        p.start.isAfter(DateTime.now()) ||
        p.start.isBefore(
          DateTime.now().subtract(Duration(days: item.catchupDays)),
        )) {
      throw const FormatException(
        'This programme is outside the provider catch-up window.',
      );
    }
    if (source.kind == SourceKind.xtream) {
      final base = providerUri(source.url);
      final start = p.start.toUtc();
      String pad(int n) => n.toString().padLeft(2, '0');
      final stamp =
          '${start.year}-${pad(start.month)}-${pad(start.day)}:${pad(start.hour)}-${pad(start.minute)}';
      final root = base.path
          .replaceAll(RegExp(r'/(player_api\.php|get\.php)/?$'), '')
          .replaceAll(RegExp(r'/$'), '');
      return base
          .replace(
            path:
                '$root/timeshift/${Uri.encodeComponent(source.username)}/${Uri.encodeComponent(source.password)}/${(p.end.difference(p.start).inSeconds / 60).ceil()}/$stamp/${item.providerId}.ts',
            query: '',
            fragment: '',
          )
          .toString();
    }
    if (item.catchupTemplate.isEmpty) {
      throw const FormatException(
        'This playlist does not provide a catch-up URL template.',
      );
    }
    return item.catchupTemplate
        .replaceAll('{utc}', '${p.start.millisecondsSinceEpoch ~/ 1000}')
        .replaceAll('{utcend}', '${p.end.millisecondsSinceEpoch ~/ 1000}')
        .replaceAll('{duration}', '${p.end.difference(p.start).inSeconds}')
        .replaceAll(
          '{lutc}',
          '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        );
  }

  void close() => client.close();
}

List<MediaItem> parseM3u(Map<String, dynamic> args) {
  final text = (args['text'] as String).replaceFirst('\uFEFF', '');
  if (!text.trimLeft().startsWith('#EXTM3U')) {
    throw const FormatException('The file is not an extended M3U playlist.');
  }
  final source = args['source'] as String;
  final result = <String, MediaItem>{};
  Map<String, String> attributes = {};
  var name = '';
  var group = '';
  final headers = <String, String>{};
  final attributePattern = RegExp(
    '([\\w-]+)=(?:"([^"]*)"|\'([^\']*)\'|([^\\s]+))',
  );
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.startsWith('#EXTINF:')) {
      attributes = {};
      headers.clear();
      var quoted = false;
      var quote = '';
      var comma = -1;
      for (var i = 8; i < line.length; i++) {
        if (line[i] == '"' || line[i] == "'") {
          if (!quoted) {
            quoted = true;
            quote = line[i];
          } else if (quote == line[i]) {
            quoted = false;
          }
        }
        if (line[i] == ',' && !quoted) {
          comma = i;
          break;
        }
      }
      final metadata = comma < 0 ? line : line.substring(0, comma);
      for (final m in attributePattern.allMatches(metadata)) {
        attributes[m.group(1)!.toLowerCase()] =
            m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
      }
      name = comma < 0
          ? (attributes['tvg-name'] ?? '')
          : line.substring(comma + 1).trim();
      group = attributes['group-title'] ?? 'Ungrouped';
    } else if (line.startsWith('#EXTGRP:')) {
      group = line.substring(8).trim();
    } else if (line.startsWith('#EXTVLCOPT:')) {
      final option = line.substring(11);
      final equals = option.indexOf('=');
      if (equals > 0) {
        final key = option.substring(0, equals);
        final value = option.substring(equals + 1);
        if (key == 'http-user-agent') headers['User-Agent'] = value;
        if (key == 'http-referrer') headers['Referer'] = value;
      }
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      final parts = line.split('|');
      final rawUri = Uri.tryParse(parts.first);
      if (rawUri == null) continue;
      final uri = rawUri.hasScheme
          ? rawUri
          : Uri.tryParse(args['base'] ?? '')?.resolve(parts.first);
      if (uri == null ||
          ![
            'http',
            'https',
            'rtsp',
            'rtmp',
            'udp',
            'rtp',
          ].contains(uri.scheme)) {
        continue;
      }
      if (parts.length > 1) {
        for (final e in Uri.splitQueryString(parts.skip(1).join('|')).entries) {
          if (['user-agent', 'referer'].contains(e.key.toLowerCase())) {
            headers[e.key] = e.value;
          }
        }
      }
      final channelName = name.isEmpty
          ? (attributes['tvg-name'] ?? uri.pathSegments.last)
          : name;
      final epg = attributes['tvg-id'] ?? '';
      final identity = '$epg|$channelName|$group|${m3uStreamIdentity(uri)}';
      final id = stableId(source, identity);
      result[id] = MediaItem(
        id: id,
        sourceId: source,
        name: channelName,
        url: uri.toString(),
        group: group,
        epgId: epg,
        logo: attributes['tvg-logo'] ?? '',
        rating: attributes['is-adult'] == '1' ? 18 : 0,
        catchupDays: int.tryParse(attributes['catchup-days'] ?? '') ?? 0,
        catchupTemplate: attributes['catchup-source'] ?? '',
        headers: Map.of(headers),
      );
      name = '';
      attributes = {};
      headers.clear();
      group = 'Ungrouped';
    }
  }
  if (result.isEmpty) {
    throw const FormatException(
      'The playlist contains no supported stream URLs.',
    );
  }
  return result.values.toList();
}

// Strip only recognized authentication fields, not stream selectors such as id.
// Sort keys so query ordering changes do not invalidate favorites/history.
String m3uStreamIdentity(Uri uri) {
  const authentication = {
    'username',
    'password',
    'token',
    'access_token',
    'auth_token',
    'signature',
    'expires',
  };
  final keys =
      uri.queryParametersAll.keys
          .where((key) => !authentication.contains(key.toLowerCase()))
          .toList()
        ..sort();
  return uri
      .replace(
        userInfo: '',
        fragment: '',
        queryParameters: {
          for (final key in keys) key: uri.queryParametersAll[key]!,
        },
      )
      .toString();
}

DateTime xmltvTime(String input) {
  final m = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?(?:\s*([+-])(\d{2})(\d{2})|\s*(?:Z|UTC|GMT))?$',
  ).firstMatch(input.trim());
  if (m == null) {
    throw const FormatException('Invalid XMLTV timestamp or timezone.');
  }
  int n(int i) => int.parse(m.group(i) ?? '0');
  final offset = (n(8) * 60 + n(9)) * (m.group(7) == '-' ? -1 : 1);
  final parsed = DateTime.utc(n(1), n(2), n(3), n(4), n(5), n(6));
  if (parsed.year != n(1) ||
      parsed.month != n(2) ||
      parsed.day != n(3) ||
      n(4) > 23 ||
      n(5) > 59 ||
      n(6) > 59 ||
      n(8) > 23 ||
      n(9) > 59) {
    throw const FormatException('Invalid XMLTV calendar date.');
  }
  return parsed.subtract(Duration(minutes: offset));
}

List<Programme> parseXmltv(Map<String, dynamic> args) {
  List<int> bytes = args['bytes'];
  if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    final output = BoundedOutputStream(128 * 1024 * 1024);
    GZipDecoder().decodeStream(InputMemoryStream(bytes), output);
    bytes = output.getBytes();
  }
  if (bytes.length > 256 * 1024 * 1024) {
    throw const FormatException('Expanded EPG is too large.');
  }
  var text = utf8.decode(bytes, allowMalformed: true);
  // A normal XMLTV external DTD declaration is metadata, not an instruction
  // to fetch a resource. Never allow internal subsets or custom entities.
  text = text.replaceAll(
    RegExp(
      r'''<!DOCTYPE\s+tv(?:\s+SYSTEM\s+(?:"[^"<>]*"|'[^'<>]*')|\s+PUBLIC\s+(?:"[^"<>]*"|'[^'<>]*')\s+(?:"[^"<>]*"|'[^'<>]*'))?\s*>''',
    ),
    '',
  );
  if (text.contains('<!DOCTYPE') || text.contains('<!ENTITY')) {
    throw const FormatException('XML entities are not supported.');
  }
  // Read one programme at a time instead of constructing a full XML document.
  final result = <String, Programme>{};
  final expression = RegExp(r'<programme\b[^>]*>[\s\S]*?</programme>');
  var found = 0;
  for (final match in expression.allMatches(text)) {
    found++;
    try {
      final node = XmlDocument.parse(match.group(0)!).rootElement;
      final start = xmltvTime(
        node.getAttribute('start') ?? '',
      ).add(Duration(minutes: args['offset'] ?? 0));
      final end = xmltvTime(
        node.getAttribute('stop') ?? '',
      ).add(Duration(minutes: args['offset'] ?? 0));
      if (!end.isAfter(start) ||
          end.millisecondsSinceEpoch < args['from'] ||
          start.millisecondsSinceEpoch > args['to']) {
        continue;
      }
      final channel = node.getAttribute('channel') ?? '';
      if (channel.isEmpty) continue;
      final title = node.getElement('title')?.innerText ?? 'Untitled';
      final ratingText =
          node.getElement('rating')?.getElement('value')?.innerText ?? '';
      final id = stableId(
        args['source'],
        '$channel:${start.millisecondsSinceEpoch}',
      );
      result[id] = Programme(
        id: id,
        sourceId: args['source'],
        channelId: channel,
        title: title,
        start: start,
        end: end,
        description: node.getElement('desc')?.innerText ?? '',
        rating:
            int.tryParse(
              RegExp(r'\d+').firstMatch(ratingText)?.group(0) ?? '',
            ) ??
            0,
      );
    } on FormatException {
      continue;
    }
  }
  if (!text.contains('<tv') || (found > 0 && result.isEmpty)) {
    throw const FormatException(
      'EPG contains no valid programmes in the selected time window.',
    );
  }
  return result.values.toList();
}

class BoundedOutputStream extends OutputMemoryStream {
  BoundedOutputStream(this.maximum);
  final int maximum;
  void check(int count) {
    if (length + count > maximum) {
      throw const FormatException('Expanded EPG exceeds the memory limit.');
    }
  }

  @override
  void writeByte(int value) {
    check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    check(count);
    super.writeBackReference(distance, count);
  }
}
