# Lumen IPTV

Direct APK, Windows installer and Linux package tooling: [distribution setup](distribution/README.md). Native builds and publication still require the signing/build environment described there.

A device-local Flutter IPTV player. No channels or subscriptions are supplied. Use only content you are authorized to access and record.

## Run

Use Flutter 3.47.4 / Dart 3.13.3 and the committed lockfile. This workspace includes Flutter in `.tools/flutter`; elsewhere substitute your installed SDK.

```powershell
.\.tools\flutter\bin\flutter.bat pub get
.\.tools\flutter\bin\flutter.bat run -d chrome
```

Create the first administrator, then add M3U or Xtream sources. Only the administrator manages accounts and libraries. Each account has independent favorites, history, custom groups and appearance. Keep an encrypted backup and its password: there is no cloud password recovery.

The administrator uses a password (at least 10 characters). New regular profiles use 4–8 digit PINs, including leading zeroes. Existing password profiles remain usable; the administrator can select **Set PIN** to convert or reset them. PINs use the same salted password derivation and five-failure/five-minute lockout. PINs are more convenient but less resistant to offline guessing than long passwords.

**Discoverable** means visible in this device’s sign-in profile list, not network discovery. It defaults on for new regular profiles; the administrator can disable it at creation or toggle the eye icon in profile management. Hidden users can sign in by account name and PIN (or their legacy password). The administrator is never listed as discoverable and has a separate password sign-in entry. Hiding a profile is a convenience/privacy setting, not protection against someone with access to local storage.

## Features

- Multiple M3U/Xtream libraries; live TV, movies and series; startup/interval refresh.
- Incremental catalog and EPG writes: keyed fingerprints skip unchanged records and search entries, update changed entries, and remove deleted entries transactionally. Providers still supply full feeds; the first refresh after upgrading builds fingerprints. Unchanged series retain cached episodes; refreshing a series reconciles its episode list.
- Live TV opens a category list, then a guide scoped to that category and playlist. Movies/Series/Live TV searches stay within their media type; home search remains global.
- Numerically ordered season and episode selection, episode details and resume/watched indicators. Full-screen player overlays auto-hide during playback.
- Any positive whole-hour playlist/EPG interval (for example, every 5 or 7 hours), plus independent startup toggles. These are elapsed intervals, not times of day.
- Test connection without importing: Xtream authentication/account status and a bounded M3U sample. Xtream `max_connections` is loaded on import/refresh/save and overrides the local fallback; recognizable same-provider `get.php` M3U URLs are also checked. Missing, zero, or invalid limits use the fallback, not an assumed unlimited allowance. Active connections are an informational provider snapshot; this app cannot reserve slots used on other devices.
- XMLTV/gzip, multiple EPG feeds, retention, offsets, channel mapping, guide search and provider-supported catch-up.
- SQLite/FTS search, paginated browsing, favorites, history and custom groups.
- Local administrator-managed accounts and parental source/group/channel/rating restrictions.
- Theme, accent, density, text scaling and home-row preferences.
- Two/four-pane viewing, source connection limits, engine preferences and available audio/subtitle tracks.
- Native live/scheduled direct-stream and clear MPEG-TS HLS recording.
- Password-encrypted portable backups, transactional restore and rollback; recording media is excluded.
- Single-use, five-minute LAN QR provider entry and backup transfer (64 MB transfer limit).
- Signed release checks and verified package downloads when configured; installation is manual.

## Platform status

| Target | Engine integration | Verification |
| --- | --- | --- |
| Web | HTML video + hls.js | Release build; synthetic HLS playback, alternate audio and rendered captions tested |
| Android / Android TV / Fire TV | Media3, mpv, VLC | Runner/TV integration; native hardware testing pending |
| iOS | AVPlayer, mpv, VLC | Runner configured; Mac build and device testing pending |
| Windows / Linux | mpv | Runners configured; native build/device testing pending |
| Apple TV | Community Flutter tvOS + AVPlayer | Separate runner/plugins; Mac build/device testing pending |

Android needs its SDK; Windows needs Visual Studio desktop C++; Linux needs Flutter native dependencies and libmpv; Apple targets need macOS/Xcode and signing. The tvOS runner uses `fluttertv/flutter-tvos` templates (CLI dev 1.10.2, Flutter pin 3.47.2), not official Flutter. Use its matching SDK and build instructions on a Mac. Companion plugin source inspected: `fluttertv/fluttertv-plugins` commit `5a0ff62655f1249a7fd30b585c02f90abb2c39cd`.

## Validation

```powershell
.\.tools\flutter\bin\flutter.bat analyze --no-pub
.\.tools\flutter\bin\flutter.bat test --no-pub
.\.tools\flutter\bin\flutter.bat build web --release --no-pub
bun install
bun tooling/serve.ts
# Another terminal; use Node for Playwright on Windows:
node --experimental-strip-types tooling/browser-smoke.ts
```

Preview: http://127.0.0.1:8080. Browser automation uses synthetic playlists. Optional index benchmark: `flutter test tooling/performance_test.dart`, producing `build/benchmark.json`. Query benchmarks do not measure playback CPU/RAM; imports and backups still materialize data in memory.

`flutter test tooling/import_performance_test.dart` exercises actual encryption, catalog writes and search indexing across 5,000/10,000-item imports and refreshes. For the browser fixture, run the preview server on port 8081 (`$env:PORT='8081'; bun tooling/serve.ts`), then set `LUMEN_TEST_URL=http://127.0.0.1:8081` and `LUMEN_TEST_LARGE=1` before running the browser smoke script. It imports 10,000 channels and logs storage usage after the guide settles. Normal import growth includes catalog payloads and both search indexes; EPG is downloaded after the catalog. Bulk index writes avoid the previous per-channel full search-table scan. Existing local data is retained; no storage reset is required.

## Limits and security

Star Live TV categories to pin them ahead of other categories. Category favorites are per profile and playlist scope and travel with profile backups. Player shortcuts: click video or Space to pause/play, Left/Right to seek 10 seconds, and 0–9 to jump to 0–90% of on-demand content. Forward/back buttons seek 10 seconds. Live playback supports pause/play but does not offer these seek jumps.

For You search hides cached series episodes unless “Show episodes” is enabled. Live guide channel filtering stays within the selected category/playlist. Live channels use provider feed order, not alphabetical order; refresh existing playlists once after upgrading to capture their current provider order. Provider order is stored separately from payloads, so reordering does not re-encrypt unchanged channels, and is included in backups. When combining playlists, each playlist retains its own channel order.

Playback does not automatically request fullscreen; use the player's Fullscreen button. Series details include provider artwork, and episode playback offers a season/episode dialog with the current episode marked. Switching episodes saves the previous position and reuses the player's connection slot. Browser track selection includes HLS renditions and browser-exposed captions/native tracks; embedded MP4/MKV track selection remains dependent on browser capabilities.

Refresh progress no longer invalidates library views. A completed refresh reports added/changed/removed/unchanged counts; unchanged feeds do not rebuild the catalog or its search index. Older records without fingerprints are compared before seeding hashes, preserving unchanged encrypted payloads. Error banners classify failures without printing credentials. Web startup uses the bundled CanvasKit renderer instead of its remote CDN and skips unused media_kit initialization.

Browser HLS audio/subtitle selection uses hls.js; other formats depend on tracks exposed by the browser. Native track support depends on the chosen engine; unavailable tracks are shown explicitly. Browser fullscreen requires permission/user activation; native immersive mode does not implement desktop OS-window fullscreen.

Rebuild the browser video bridge after changes with `bun run build:video`, before building Flutter web. To run playback/navigation fixtures, generate media with `tooling/create-media-fixture.ps1` (requires FFmpeg), serve on port 8082, and run `node --experimental-strip-types tooling/browser-features.ts`.

This is not yet a hardware-certified release. Desktop VLC, reliable OS wake-up for recording, tvOS frame-rate matching and automatic update installation are not implemented. Android mpv refresh-rate requests depend on the display. Recording requires the app to remain available; Android foreground service behavior is not yet device-tested and does not provide reboot recovery. Encrypted HLS, fMP4 HLS and DRM recording are rejected.

Web providers must satisfy CORS, browser codecs and mixed-content rules. Browser data may be cleared. tvOS database storage is a purgeable cache; external backups are essential. Verify remote focus, codecs, lifecycle, signing and plugin registration on actual hardware before distribution.

Credentials/stream payloads use device-key encryption; searchable metadata is clear. Passwords use salted PBKDF2-HMAC-SHA256 and backups authenticated AES-GCM. Profiles enforce application policy, not protection against someone controlling the device/database. QR client code is delivered over HTTP: encrypted submissions do not defeat active LAN attackers modifying that code. Use a trusted LAN and never expose pairing to the internet. Prefer HTTPS provider URLs.

Rebuild pairing code with `bun run build:pairing`. After Drift upgrades rebuild its worker with `dart compile js -O4 tooling/drift_worker.dart -o web/drift_worker.dart.js`. Font licenses are bundled in `assets/fonts`; review mpv/FFmpeg, VLC and all transitive library licenses before distributing binaries. Configure production signing separately.

Signed updates use compile-time `LUMEN_UPDATE_URL` (HTTPS) and `LUMEN_UPDATE_PUBLIC_KEY` (base64 Ed25519). The envelope has base64 `payload` and `signature`. Signed payload: `schema: 1`, increasing integer `build`, `version`, `notes`, and `assets` keyed by platform with HTTPS `url` and lowercase hex `sha256`. No production feed is configured; keep private signing keys outside this repository.
