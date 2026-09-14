import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../platform/pairing.dart';
import '../playback/engine.dart';
import '../core/updates.dart';
import '../platform/update_download.dart';
import 'common.dart';
import 'backup_transfer.dart';
import '../platform/device.dart';

Future<void> showSourceDialog(
  BuildContext context,
  AppController app, {
  Source? source,
  Map<String, dynamic>? paired,
}) async {
  await showDialog(
    context: context,
    builder: (_) => SourceDialog(app: app, source: source, paired: paired),
  );
}

class SourceDialog extends StatefulWidget {
  const SourceDialog({super.key, required this.app, this.source, this.paired});
  final AppController app;
  final Source? source;
  final Map<String, dynamic>? paired;
  @override
  State<SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<SourceDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name,
      url,
      username,
      password,
      epg,
      offset,
      connections,
      refreshInput,
      epgInput;
  late SourceKind kind;
  bool startup = true, epgStartup = true, busy = false;
  String? error, fileText, fileName;
  String? connectionResult;
  int? detectedConnections;
  @override
  void initState() {
    super.initState();
    final s = widget.source;
    final p = widget.paired ?? {};
    name = TextEditingController(text: s?.name ?? p['name'] ?? '');
    url = TextEditingController(text: s?.url ?? p['url'] ?? '');
    username = TextEditingController(text: s?.username ?? p['username'] ?? '');
    password = TextEditingController(text: s?.password ?? p['password'] ?? '');
    epg = TextEditingController(text: s?.epgUrl ?? '');
    offset = TextEditingController(text: '${s?.epgOffsetMinutes ?? 0}');
    connections = TextEditingController(text: '${s?.connections ?? 2}');
    refreshInput = TextEditingController(text: '${s?.refreshHours ?? 24}');
    epgInput = TextEditingController(text: '${s?.epgHours ?? 12}');
    detectedConnections = s?.providerConnections;
    kind =
        s?.kind ?? (p['type'] == 'xtream' ? SourceKind.xtream : SourceKind.m3u);
    startup = s?.startup ?? true;
    epgStartup = s?.epgStartup ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      name,
      url,
      username,
      password,
      epg,
      offset,
      connections,
      refreshInput,
      epgInput,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || busy) return;
    if (kind == SourceKind.file && fileText == null && widget.source == null) {
      setState(() => error = 'Choose an M3U file.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final source = Source(
      id: widget.source?.id ?? const Uuid().v4(),
      name: name.text.trim(),
      kind: kind,
      url: url.text.trim(),
      username: username.text.trim(),
      password: password.text,
      epgUrl: epg.text.trim(),
      refreshHours: int.parse(refreshInput.text.trim()),
      epgHours: int.parse(epgInput.text.trim()),
      startup: startup,
      epgStartup: epgStartup,
      connections: int.parse(connections.text),
      providerConnections: detectedConnections,
      epgOffsetMinutes: int.parse(offset.text),
      updatedAt: widget.source?.updatedAt,
      epgUpdatedAt: widget.source?.epgUpdatedAt,
    );
    try {
      if (widget.source != null) {
        await widget.app.updateSource(source);
      } else {
        await widget.app.addSource(source, fileText: fileText);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> testConnection() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      connectionResult = null;
    });
    try {
      final result = await widget.app.providers.testConnection(
        Source(
          id: widget.source?.id ?? 'connection-test',
          name: name.text.trim(),
          kind: kind,
          url: url.text.trim(),
          username: username.text.trim(),
          password: password.text,
        ),
        fileText: fileText,
      );
      if (!mounted) return;
      setState(() {
        detectedConnections = result.maximum;
        connectionResult =
            '${result.message}${result.maximum == null ? '' : ' Limit: ${result.maximum}.'}${result.active == null ? '' : ' Active now: ${result.active}.'} This test does not import the library or verify video playback.';
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget intervalField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, suffixText: 'hours'),
        validator: (value) {
          final hours = int.tryParse(value?.trim() ?? '');
          return hours == null || hours < 1 || hours > 2147483647
              ? 'Enter positive whole hours'
              : null;
        },
      );

  Widget field(
    TextEditingController c,
    String label, {
    bool secret = false,
    bool required = false,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: c,
      obscureText: secret,
      onChanged: (value) {
        if (c == url || c == username || c == password) {
          setState(() {
            detectedConnections = null;
            connectionResult = null;
          });
        }
      },
      maxLines: secret ? 1 : maxLines,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (v) => v == null || v.trim().isEmpty ? 'Required' : null
          : null,
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        widget.source == null ? 'Bring your playlist.' : 'Playlist settings',
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.paired != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Received from your paired device. Review and confirm these details.',
                    ),
                  ),
                DropdownButtonFormField<SourceKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Playlist type'),
                  items: [
                    const DropdownMenuItem(
                      value: SourceKind.m3u,
                      child: Text('M3U URL'),
                    ),
                    const DropdownMenuItem(
                      value: SourceKind.xtream,
                      child: Text('Xtream Codes'),
                    ),
                    if (!isAppleTV || kind == SourceKind.file)
                      const DropdownMenuItem(
                        value: SourceKind.file,
                        child: Text('Local M3U file'),
                      ),
                  ],
                  onChanged: widget.source != null || busy
                      ? null
                      : (v) => setState(() => kind = v!),
                ),
                const SizedBox(height: 16),
                field(name, 'Playlist name', required: true),
                if (kind != SourceKind.file)
                  field(
                    url,
                    kind == SourceKind.xtream ? 'Server URL' : 'Playlist URL',
                    required: true,
                  )
                else if (widget.source == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: Text(fileName ?? 'Choose M3U file'),
                      onPressed: busy
                          ? null
                          : () async {
                              final file = await FilePicker.platform.pickFiles(
                                withData: true,
                                type: FileType.custom,
                                allowedExtensions: ['m3u', 'm3u8'],
                              );
                              if (file != null && mounted) {
                                setState(() {
                                  fileText = utf8.decode(
                                    file.files.single.bytes!,
                                    allowMalformed: true,
                                  );
                                  fileName = file.files.single.name;
                                });
                              }
                            },
                    ),
                  ),
                if (kind == SourceKind.xtream) ...[
                  field(username, 'Username', required: true),
                  field(password, 'Password', secret: true, required: true),
                ],
                field(
                  epg,
                  kind == SourceKind.xtream
                      ? 'EPG URL (optional override)'
                      : 'XMLTV EPG URL (optional)',
                  maxLines: 3,
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'One EPG URL per line. Earlier feeds take priority when programmes overlap.',
                    style: TextStyle(fontSize: 11, color: mutedColor),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: intervalField(refreshInput, 'Playlist refresh'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: intervalField(epgInput, 'EPG refresh')),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Update playlist on startup'),
                  value: startup,
                  onChanged: (v) => setState(() => startup = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Update EPG on startup'),
                  value: epgStartup,
                  onChanged: (v) => setState(() => epgStartup = v),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: offset,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'EPG offset (minutes)',
                        ),
                        validator: (v) => int.tryParse(v ?? '') == null
                            ? 'Enter a number'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: connections,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Fallback connections',
                        ),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return n == null || n < 1 || n > 16
                              ? 'Use 1–16'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  detectedConnections == null
                      ? 'Connection limits are read from Xtream automatically. Plain M3U or providers that omit a limit use the fallback.'
                      : 'Provider-reported limit: $detectedConnections connections. This overrides the fallback.',
                  style: const TextStyle(fontSize: 12, color: mutedColor),
                ),
                if (connectionResult != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(connectionResult!),
                  ),
                if (busy)
                  AnimatedBuilder(
                    animation: widget.app,
                    builder: (_, _) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        widget.app.activity ?? 'Contacting provider…',
                      ),
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: busy || (kind == SourceKind.file && fileText == null)
              ? null
              : testConnection,
          icon: const Icon(Icons.network_check),
          label: const Text('Test connection'),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.source == null ? 'Add playlist' : 'Save'),
        ),
      ],
    ),
  );
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool busy = false;
  Future<void> pairing() async {
    final app = ref.read(appProvider);
    app.requireAdmin();
    final server = PairingServer();
    Map<String, dynamic>? submitted;
    BuildContext? dialogContext;
    await perform(context, () async {
      await server.start((payload) {
        submitted = payload;
        if (dialogContext?.mounted == true) Navigator.pop(dialogContext!);
      });
      if (!mounted) {
        await server.close();
        return;
      }
      await showDialog(
        context: context,
        builder: (c) {
          dialogContext = c;
          return AlertDialog(
            title: const Text('A little less typing.'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Scan with your phone or PC on the same network. This code expires after 5 minutes.',
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: QrImageView(data: server.url, size: 240),
                  ),
                  const SizedBox(height: 16),
                  if (!isAppleTV)
                    TextButton.icon(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: server.url)),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy setup link'),
                    ),
                  const Text(
                    'Keep this window open. You’ll confirm the playlist on this device.',
                    style: TextStyle(fontSize: 12, color: mutedColor),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
      await server.close();
      if (submitted != null && mounted) {
        await showSourceDialog(context, app, paired: submitted);
      }
    });
    await server.close();
  }

  Future<void> backup({bool restore = false}) async {
    if (isAppleTV) {
      await transferBackup(context, ref.read(appProvider));
      return;
    }
    final app = ref.read(appProvider);
    final password = TextEditingController();
    String? archive;
    if (restore) {
      final file = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: ['lumen'],
      );
      if (file == null) return;
      archive = utf8.decode(file.files.single.bytes!);
    }
    if (!mounted) return;
    final answer = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(restore ? 'Restore a backup' : 'Take your space with you'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                restore
                    ? 'This replaces this device’s library and profiles. A local rollback snapshot is saved, and imported recording schedules are paused.'
                    : 'Includes profiles, credentials, playlists, guide, favorites, history, and settings. Recording media files stay on this device.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Backup password',
                  helperText:
                      'At least 10 characters. Keep this password safe.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(restore ? 'Replace and restore' : 'Export'),
          ),
        ],
      ),
    );
    if (answer == true && mounted) {
      setState(() => busy = true);
      await perform(context, () async {
        if (restore) {
          await app.restoreBackup(archive!, password.text);
        } else {
          final data = await app.exportBackup(password.text);
          await FilePicker.platform.saveFile(
            dialogTitle: 'Save encrypted Lumen backup',
            fileName:
                'lumen-${DateTime.now().toIso8601String().substring(0, 10)}.lumen',
            bytes: Uint8List.fromList(utf8.encode(data)),
            type: FileType.custom,
            allowedExtensions: ['lumen'],
          );
        }
      });
      if (mounted) setState(() => busy = false);
    }
    password.dispose();
  }

  Future<void> newAccount() async {
    final name = TextEditingController(), password = TextEditingController();
    bool saving = false;
    bool discoverable = true;
    String? error;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Make room for someone.'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Profile name'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: password,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    helperText: '4–8 digits',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Discoverable'),
                  subtitle: const Text(
                    'Show automatically in this device’s sign-in profile list.',
                  ),
                  value: discoverable,
                  onChanged: saving
                      ? null
                      : (value) => set(() => discoverable = value),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(c).colorScheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      set(() => saving = true);
                      try {
                        await ref
                            .read(appProvider)
                            .createUser(
                              name.text,
                              password.text,
                              discoverable: discoverable,
                            );
                        if (c.mounted) Navigator.pop(c);
                      } catch (e) {
                        if (c.mounted) {
                          set(() {
                            saving = false;
                            error = friendlyError(e);
                          });
                        }
                      }
                    },
              child: const Text('Create profile'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    password.dispose();
  }

  Future<void> resetPin(Profile profile) async {
    final pin = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Set PIN · ${profile.name}'),
        content: TextField(
          controller: pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: const InputDecoration(
            labelText: 'New PIN',
            helperText: '4–8 digits. Replaces the current sign-in credential.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Set PIN'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await perform(
        context,
        () => ref.read(appProvider).resetUserPin(profile, pin.text),
      );
    }
    pin.dispose();
  }

  Future<void> restrictions(Profile p) async {
    final app = ref.read(appProvider);
    final groups = await app.store.groups(app.current!);
    if (!mounted) return;
    var maximum = p.maxRating;
    var unrated = p.allowUnrated;
    final blocked = p.blockedGroups.toSet();
    final allowed = p.allowedSources.toSet();
    final channels = TextEditingController(text: p.blockedChannels.join('\n'));
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Parental controls · ${p.name}'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: maximum,
                    decoration: const InputDecoration(
                      labelText: 'Maximum age rating',
                    ),
                    items: [0, 6, 9, 12, 15, 16, 18, 100]
                        .map(
                          (n) => DropdownMenuItem(
                            value: n,
                            child: Text(
                              n == 100 ? 'No age limit' : '$n+ and below',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => maximum = v!,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow unrated content'),
                    subtitle: const Text(
                      'Many IPTV channels have no age rating.',
                    ),
                    value: unrated,
                    onChanged: (v) => set(() => unrated = v),
                  ),
                  const Divider(),
                  const Text(
                    'Allowed playlists',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'None selected means all playlists.',
                    style: TextStyle(fontSize: 12, color: mutedColor),
                  ),
                  for (final s in app.sources)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.name),
                      value: allowed.contains(s.id),
                      onChanged: (v) => set(() {
                        if (v == true) {
                          allowed.add(s.id);
                        } else {
                          allowed.remove(s.id);
                        }
                      }),
                    ),
                  const Divider(),
                  const Text(
                    'Blocked groups',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final g in groups)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(g),
                      value: blocked.contains(g),
                      onChanged: (v) => set(() {
                        if (v == true) {
                          blocked.add(g);
                        } else {
                          blocked.remove(g);
                        }
                      }),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: channels,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Blocked channel IDs (one per line)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (await perform(
                  c,
                  () => app.updateUser(
                    Profile.fromJson({
                      ...p.toJson(),
                      'maxRating': maximum,
                      'allowUnrated': unrated,
                      'allowedSources': allowed.toList(),
                      'blockedGroups': blocked.toList(),
                      'blockedChannels': channels.text
                          .split('\n')
                          .map((v) => v.trim())
                          .where((v) => v.isNotEmpty)
                          .toList(),
                    }),
                  ),
                )) {
                  if (c.mounted) Navigator.pop(c);
                }
              },
              child: const Text('Save controls'),
            ),
          ],
        ),
      ),
    );
    channels.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final p = app.current!;
    final prefs = p.preferences;
    final selectedEngine =
        [
          EngineKind.automatic,
          ...PlaybackCapabilities.current.engines,
        ].any((e) => e.name == prefs['engine'])
        ? prefs['engine']
        : 'automatic';
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      children: [
        Text(
          'Make it feel like home.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 10),
        const Text(
          'A few thoughtful adjustments. A space that’s entirely yours.',
          style: TextStyle(color: mutedColor),
        ),
        const SizedBox(height: 32),
        if (busy) const LinearProgressIndicator(),
        if (p.admin) ...[
          section(
            'Your playlists',
            trailing: Wrap(
              spacing: 8,
              children: [
                if (!kIsWeb)
                  OutlinedButton.icon(
                    onPressed: pairing,
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Fill with QR'),
                  ),
                FilledButton.icon(
                  onPressed: () => showSourceDialog(context, app),
                  icon: const Icon(Icons.add),
                  label: const Text('Add playlist'),
                ),
              ],
            ),
          ),
          if (app.sources.isEmpty)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('No playlists connected'),
              subtitle: Text(
                'M3U files, playlist URLs, and Xtream accounts are supported.',
              ),
            ),
          for (final s in app.sources)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: const Icon(Icons.playlist_play, color: limeColor),
                title: Text(s.name),
                subtitle: Text(
                  '${s.kind.name.toUpperCase()} · refresh every ${s.refreshHours}h · EPG every ${s.epgHours}h',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit playlist',
                      onPressed: () =>
                          showSourceDialog(context, app, source: s),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Remove playlist',
                      onPressed: () async {
                        if (await confirm(
                          context,
                          'Remove ${s.name}?',
                          'Channels and guide data from this source will be removed.',
                        )) {
                          if (context.mounted) {
                            await perform(context, () => app.removeSource(s));
                          }
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(),
          section(
            'People in your space',
            trailing: OutlinedButton.icon(
              onPressed: newAccount,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add profile'),
            ),
          ),
          for (final profile in app.profiles)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(profile.name.substring(0, 1).toUpperCase()),
              ),
              title: Text(profile.name),
              subtitle: Text(
                profile.admin
                    ? 'Administrator · Password · Not discoverable'
                    : profile.usesPin
                    ? 'Personal profile · PIN'
                    : 'Personal profile · Legacy password',
              ),
              trailing: profile.admin
                  ? const Icon(Icons.verified_user_outlined)
                  : Wrap(
                      children: [
                        IconButton(
                          tooltip: profile.discoverable
                              ? 'Hide from sign-in list'
                              : 'Show in sign-in list',
                          onPressed: () => perform(
                            context,
                            () => app.setDiscoverable(
                              profile,
                              !profile.discoverable,
                            ),
                          ),
                          icon: Icon(
                            profile.discoverable
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Set PIN',
                          onPressed: () => resetPin(profile),
                          icon: const Icon(Icons.pin_outlined),
                        ),
                        TextButton(
                          onPressed: () => restrictions(profile),
                          child: const Text('Parental controls'),
                        ),
                        IconButton(
                          tooltip: 'Delete profile',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (await confirm(
                              context,
                              'Delete ${profile.name}?',
                              'Their favorites, watch history, and personalization will be removed.',
                            )) {
                              if (context.mounted) {
                                await perform(
                                  context,
                                  () => app.deleteUser(profile),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
            ),
          const Divider(),
        ],
        section('Your look & feel'),
        Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                initialValue: prefs['theme'] ?? 'dark',
                decoration: const InputDecoration(labelText: 'Theme'),
                items: const [
                  DropdownMenuItem(
                    value: 'dark',
                    child: Text('Evening · dark'),
                  ),
                  DropdownMenuItem(
                    value: 'light',
                    child: Text('Daylight · light'),
                  ),
                ],
                onChanged: (v) => app.preferences({'theme': v}),
              ),
            ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                initialValue: prefs['density'] ?? 'comfortable',
                decoration: const InputDecoration(labelText: 'Layout density'),
                items: const [
                  DropdownMenuItem(
                    value: 'comfortable',
                    child: Text('Comfortable'),
                  ),
                  DropdownMenuItem(value: 'compact', child: Text('Compact')),
                ],
                onChanged: (v) => app.preferences({'density': v}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Accent color',
          style: TextStyle(color: mutedColor, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          children: [
            for (final color in [
              limeColor,
              const Color(0xffefbd91),
              const Color(0xffa4cfe2),
              const Color(0xffe3b1c2),
            ])
              Semantics(
                label: 'Accent ${color.toARGB32().toRadixString(16)}',
                button: true,
                child: InkWell(
                  onTap: () => app.preferences({'accent': color.toARGB32()}),
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            (prefs['accent'] ?? limeColor.toARGB32()) ==
                                color.toARGB32()
                            ? Colors.white
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Text size'),
          subtitle: Slider(
            value: (prefs['textScale'] ?? 1.0).toDouble(),
            min: .85,
            max: 1.35,
            divisions: 10,
            label: '${((prefs['textScale'] ?? 1.0) * 100).round()}%',
            onChanged: (v) => app.preferences({'textScale': v}),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Home screen rows'),
          subtitle: const Text(
            'Reorder your favorites, live TV, and continue watching.',
          ),
          trailing: const Icon(Icons.reorder),
          onTap: () => reorderRows(app),
        ),
        const Divider(),
        section('Playback'),
        SizedBox(
          width: 350,
          child: DropdownButtonFormField<String>(
            initialValue: selectedEngine,
            decoration: const InputDecoration(
              labelText: 'Preferred playback engine',
            ),
            items:
                [EngineKind.automatic, ...PlaybackCapabilities.current.engines]
                    .map(
                      (k) => DropdownMenuItem(
                        value: k.name,
                        child: Text(k.name.toUpperCase()),
                      ),
                    )
                    .toList(),
            onChanged: (v) => app.preferences({'engine': v}),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Automatic chooses the device’s default engine. Available alternatives depend on the platform. Each multiview stream uses a separate provider connection.',
          style: TextStyle(color: mutedColor, fontSize: 12, height: 1.6),
        ),
        if (p.admin) ...[
          const Divider(),
          section('Backup & recovery'),
          const Text(
            'An encrypted copy of your library, accounts, and preferences. Bring it to another device or keep it somewhere safe.',
            style: TextStyle(color: mutedColor, height: 1.6),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => backup(),
                icon: const Icon(Icons.download),
                label: const Text('Export encrypted backup'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => backup(restore: true),
                icon: const Icon(Icons.restore),
                label: const Text('Restore backup'),
              ),
            ],
          ),
          const Divider(),
          section('Guide storage'),
          FutureBuilder(
            future: app.store.setting('epg-retention'),
            builder: (context, snapshot) {
              final setting = snapshot.data ?? {};
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final entry in [
                    ('past', 'Past days', 2, [0, 1, 2, 3, 7]),
                    ('future', 'Future days', 7, [1, 3, 7, 14]),
                  ])
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<int>(
                        initialValue: setting[entry.$1] ?? entry.$3,
                        decoration: InputDecoration(labelText: entry.$2),
                        items: entry.$4
                            .map(
                              (n) => DropdownMenuItem(
                                value: n,
                                child: Text('$n days'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) async {
                          await app.store.setSetting('epg-retention', {
                            ...setting,
                            entry.$1: v,
                          });
                          setState(() {});
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        const Divider(),
        section('About Lumen'),
        if (isAppleTV)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Apple TV stores this local library in a cache that tvOS may clear. Export a backup after changing accounts or playlists so your setup can be recovered.',
              style: TextStyle(color: mutedColor, height: 1.6),
            ),
          ),
        if (p.admin && !kIsWeb)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Transfer backup with QR'),
            subtitle: const Text(
              'Export or restore using your phone or PC on the same network.',
            ),
            leading: const Icon(Icons.qr_code),
            onTap: () => transferBackup(context, app),
          ),
        if (p.admin) ...[
          FutureBuilder(
            future: app.store.setting('app-updates'),
            builder: (context, snapshot) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatic app update checks'),
              value: snapshot.data?['startup'] != false,
              onChanged: (v) async {
                await app.store.setSetting('app-updates', {'startup': v});
                setState(() {});
              },
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              app.availableUpdate == null
                  ? 'App updates'
                  : 'Lumen ${app.availableUpdate!.version} is available',
            ),
            subtitle: Text(
              UpdateService.configured
                  ? 'Automatic checks at startup and every six hours. Downloads are verified; installation requires your approval.'
                  : 'No release feed is configured for this development build.',
            ),
            trailing: TextButton(
              onPressed: !UpdateService.configured
                  ? null
                  : () async {
                      await perform(context, () async {
                        final update = await UpdateService.check();
                        app.availableUpdate = update;
                        app.changed();
                        if (update == null && context.mounted) {
                          message(
                            context,
                            'You have the latest published build.',
                          );
                        }
                      });
                    },
              child: const Text('Check now'),
            ),
          ),
          if (app.availableUpdate != null && !kIsWeb && !isAppleTV)
            OutlinedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download and install update'),
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      await perform(context, () async {
                        final release = app.availableUpdate!;
                        final path = await downloadUpdate(release);
                        if (context.mounted) {
                          await showDialog(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Update verified'),
                              content: SelectableText(
                                'Publisher-signed metadata and the package checksum are verified. Stop playback and recordings before installing. Your OS may request permission.\n\n$path',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: const Text('Later'),
                                ),
                                FilledButton(
                                  onPressed: () async {
                                    if (app.recording.active.isNotEmpty) {
                                      message(
                                        c,
                                        'Stop active recordings before installing.',
                                      );
                                      return;
                                    }
                                    await perform(
                                      c,
                                      () => installUpdate(path, release),
                                    );
                                  },
                                  child: const Text('Install'),
                                ),
                              ],
                            ),
                          );
                        }
                      });
                      if (mounted) setState(() => busy = false);
                    },
            ),
        ],
        const Text(
          'Version ${UpdateService.currentVersion} · Build ${UpdateService.currentBuild} · Local-first IPTV\nContent refresh runs while the app is available, with overdue work resumed when you return. No media or subscriptions are included.',
          style: TextStyle(color: mutedColor, fontSize: 12, height: 1.8),
        ),
      ],
    );
  }

  Widget section(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 14,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        ?trailing,
      ],
    ),
  );
  Future<void> reorderRows(AppController app) async {
    final rows = List<String>.from(
      app.current!.preferences['homeRows'] ??
          ['Continue watching', 'Your favorites', 'Live now', 'Movie night'],
    );
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Arrange your home'),
          content: SizedBox(
            width: 400,
            height: 260,
            child: ReorderableListView(
              onReorderItem: (oldIndex, newIndex) => set(() {
                rows.insert(newIndex, rows.removeAt(oldIndex));
              }),
              children: [
                for (final row in rows)
                  ListTile(
                    key: ValueKey(row),
                    title: Text(row),
                    leading: const Icon(Icons.drag_handle),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await app.preferences({'homeRows': rows});
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
