import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/data/providers.dart';
import 'package:lumen_iptv/core/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Blank Xtream EPG uses xmltv endpoint and accepts standard DTD', () async {
    final now = DateTime.now().toUtc();
    String stamp(DateTime value) => value
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(RegExp('[-:T]'), '');
    Uri? requested;
    final provider = ProviderClient(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          '<?xml version="1.0"?><!DOCTYPE tv SYSTEM "https://example.test/xmltv.dtd"><tv>'
          '<programme channel="news" start="${stamp(now.subtract(const Duration(hours: 1)))}" stop="${stamp(now.add(const Duration(hours: 1)))}"><title>News</title></programme></tv>',
          200,
        );
      }),
    );
    addTearDown(provider.close);
    final programmes = await provider.epg(
      const Source(
        id: 's',
        name: 'Test',
        kind: SourceKind.xtream,
        url: 'https://provider.test/panel/player_api.php',
        username: 'user',
        password: 'pass',
        epgUrl: '   ',
      ),
    );
    expect(requested!.path, '/panel/xmltv.php');
    expect(requested!.queryParameters, {
      'username': 'user',
      'password': 'pass',
    });
    expect(programmes.single.title, 'News');
  });
  test(
    'XMLTV still rejects custom entity declarations and internal subsets',
    () {
      expect(
        () => parseXmltv({
          'source': 's',
          'bytes': utf8.encode(
            '<!DOCTYPE tv [<!ENTITY x SYSTEM "file:///secret">]><tv/>',
          ),
          'from': 0,
          'to': 9999999999999,
        }),
        throwsFormatException,
      );
    },
  );
  test('Xtream stream URLs discard API query parameters', () {
    final provider = ProviderClient();
    addTearDown(provider.close);
    final result = Uri.parse(
      provider.streamUrl(
        const Source(
          id: 's',
          name: 'Test',
          kind: SourceKind.xtream,
          url:
              'https://provider.test/player_api.php?username=old&password=old&action=test',
          username: 'user',
          password: 'pass',
        ),
        'live',
        '42',
        'ts',
      ),
    );
    expect(result.path, '/live/user/pass/42.ts');
    expect(result.query, isEmpty);
  });
  test('M3U preserves host and query stream identities across auth rotation', () {
    List<MediaItem> parse(String token) => parseM3u({
      'source': 'source',
      'text':
          '#EXTM3U\n${['https://one.test/play?id=1&token=$token', 'https://one.test/play?id=2&token=$token', 'https://two.test/play?id=1&token=$token'].map((url) => '#EXTINF:-1 tvg-id="news" group-title="TV",News\n$url').join('\n')}',
    });
    final original = parse('old');
    expect(original, hasLength(3));
    expect(original.map((item) => item.id).toSet(), hasLength(3));
    expect(
      parse('new').map((item) => item.id),
      original.map((item) => item.id),
    );
    expect(
      m3uStreamIdentity(Uri.parse('https://one.test/play?id=1&quality=hd')),
      m3uStreamIdentity(Uri.parse('https://one.test/play?quality=hd&id=1')),
    );
  });
  const xtream = Source(
    id: 'account',
    name: 'Account',
    kind: SourceKind.xtream,
    url: 'https://provider.test',
    username: 'u',
    password: 'p',
  );
  test(
    'Connection test reads provider limits without downloading catalogs',
    () async {
      final requests = <Uri>[];
      final provider = ProviderClient(
        client: MockClient((r) async {
          requests.add(r.url);
          return http.Response(
            '{"user_info":{"auth":1,"status":"Active","max_connections":"5","active_cons":"2"}}',
            200,
          );
        }),
      );
      final result = await provider.testConnection(xtream);
      expect(result.maximum, 5);
      expect(result.active, 2);
      expect(requests, hasLength(1));
      expect(requests.single.queryParameters['action'], '');
      expect(provider.withAccount(xtream).connectionLimit, 5);
      provider.close();
    },
  );
  test(
    'Unreported and zero provider limits use fallback, expired accounts fail',
    () async {
      var status = 'Active';
      final provider = ProviderClient(
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'user_info': {
                'auth': 1,
                'status': status,
                'max_connections': '0',
              },
            }),
            200,
          ),
        ),
      );
      expect((await provider.testConnection(xtream)).maximum, isNull);
      expect(provider.withAccount(xtream).connectionLimit, 2);
      status = 'Expired';
      await expectLater(provider.testConnection(xtream), throwsFormatException);
      provider.close();
    },
  );
  test(
    'M3U test validates sample and discovers same-provider Xtream limits',
    () async {
      final provider = ProviderClient(
        client: MockClient(
          (r) async => r.url.path.endsWith('get.php')
              ? http.Response(
                  '#EXTM3U\n#EXTINF:-1,News\nhttps://provider.test/live.ts\n',
                  200,
                )
              : http.Response(
                  '{"user_info":{"auth":1,"max_connections":3}}',
                  200,
                ),
        ),
      );
      final source = Source.fromJson({
        ...xtream.toJson(),
        'kind': 'm3u',
        'url':
            'https://provider.test/get.php?username=u&password=p&type=m3u_plus',
      });
      expect((await provider.testConnection(source)).maximum, 3);
      provider.close();
    },
  );
  test(
    'M3U handles quoted commas, relative streams, headers, and source identities',
    () {
      final items = parseM3u({
        'source': 'one',
        'base': 'https://provider.test/list/main.m3u',
        'text': '''#EXTM3U
#EXTINF:-1 tvg-id="news" tvg-name="News, World" group-title="News, International" tvg-logo="https://img.test/news.png",World News
#EXTVLCOPT:http-user-agent=Lumen Test
../live/news.ts
#EXTINF:-1 group-title="Sports",Match
https://provider.test/live/sport.ts
''',
      });
      expect(items, hasLength(2));
      expect(items.first.name, 'World News');
      expect(items.first.group, 'News, International');
      expect(items.first.url, 'https://provider.test/live/news.ts');
      expect(items.first.headers['User-Agent'], 'Lumen Test');
      expect(items.last.headers, isEmpty);
      expect(items.first.id, startsWith('one:'));
    },
  );
  test('M3U rejects HTML and playlists without valid streams', () {
    expect(
      () => parseM3u({'source': 'x', 'text': '<html>Login required</html>'}),
      throwsFormatException,
    );
    expect(
      () => parseM3u({
        'source': 'x',
        'text': '#EXTM3U\n#EXTINF:-1,Invalid\nfile:///etc/passwd',
      }),
      throwsFormatException,
    );
  });
  test(
    'XMLTV converts explicit offsets across DST without local assumptions',
    () {
      expect(
        xmltvTime('20261025013000 +0200'),
        DateTime.utc(2026, 10, 24, 23, 30),
      );
      expect(
        xmltvTime('20261025013000 +0100'),
        DateTime.utc(2026, 10, 25, 0, 30),
      );
      expect(xmltvTime('20261025013000'), DateTime.utc(2026, 10, 25, 1, 30));
    },
  );
  test('XMLTV scopes channel IDs and filters retention window', () {
    final entries = parseXmltv({
      'source': 'provider-a',
      'offset': 60,
      'from': DateTime.utc(2026, 9, 14).millisecondsSinceEpoch,
      'to': DateTime.utc(2026, 9, 15).millisecondsSinceEpoch,
      'bytes': utf8.encode(
        '''<tv>
<programme channel="news" start="20260914120000 +0000" stop="20260914130000 +0000"><title>News &amp; weather</title><rating><value>12+</value></rating></programme>
<programme channel="news" start="20250914120000 +0000" stop="20250914130000 +0000"><title>Old news</title></programme></tv>''',
      ),
    });
    expect(entries, hasLength(1));
    expect(entries.first.title, 'News & weather');
    expect(entries.first.start, DateTime.utc(2026, 9, 14, 13));
    expect(entries.first.rating, 12);
  });
  test(
    'Xtream rejects authentication failures without logging credentials',
    () async {
      final provider = ProviderClient(
        client: MockClient(
          (r) async => http.Response('{"user_info":{"auth":0}}', 200),
        ),
      );
      await expectLater(
        provider.load(
          const Source(
            id: 'a',
            name: 'A',
            kind: SourceKind.xtream,
            url: 'https://provider.test',
            username: 'user',
            password: 'secret',
          ),
        ),
        throwsFormatException,
      );
      provider.close();
    },
  );
  test('Catch-up enforces provider archive window', () {
    final provider = ProviderClient();
    final now = DateTime.now().toUtc();
    const item = MediaItem(
      id: 'a:1',
      sourceId: 'a',
      name: 'News',
      url: 'https://provider.test/live',
      providerId: '1',
      catchupDays: 2,
    );
    const source = Source(
      id: 'a',
      name: 'A',
      kind: SourceKind.xtream,
      url: 'https://provider.test',
      username: 'u',
      password: 'p',
    );
    final current = Programme(
      id: 'p',
      sourceId: 'a',
      channelId: '1',
      title: 'News',
      start: now.subtract(const Duration(hours: 1)),
      end: now,
    );
    expect(
      provider.catchupUrl(source, item, current),
      contains('/timeshift/u/p/60/'),
    );
    expect(
      () => provider.catchupUrl(
        source,
        item,
        Programme(
          id: 'old',
          sourceId: 'a',
          channelId: '1',
          title: 'Old',
          start: now.subtract(const Duration(days: 4)),
          end: now.subtract(const Duration(days: 3)),
        ),
      ),
      throwsFormatException,
    );
    provider.close();
  });
}
