import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../playback/engine.dart';
import 'common.dart';

class RecordingsPage extends ConsumerStatefulWidget {
  const RecordingsPage({super.key});
  @override
  ConsumerState<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends ConsumerState<RecordingsPage> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> schedule() async {
    final app = ref.read(appProvider);
    final channels = await app.store.browse(
      app.current!,
      kind: MediaKind.live,
      limit: 200,
    );
    if (!mounted) return;
    if (channels.isEmpty) {
      message(context, 'Add a live playlist first.');
      return;
    }
    var selected = channels.first;
    var duration = 60;
    var start = DateTime.now();
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Schedule a recording'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<MediaItem>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Channel (first 200; use the guide for more)',
                  ),
                  items: channels
                      .map(
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text(i.name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => selected = v!,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: duration,
                  decoration: const InputDecoration(labelText: 'Duration'),
                  items: [30, 60, 90, 120, 180, 240]
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text('$n minutes'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => duration = v!,
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(DateFormat('EEE d MMM · HH:mm').format(start)),
                  subtitle: const Text('Tap to choose start time'),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: c,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                      initialDate: start,
                    );
                    if (date == null || !c.mounted) return;
                    final time = await showTimePicker(
                      context: c,
                      initialTime: TimeOfDay.fromDateTime(start),
                    );
                    if (time != null) {
                      set(
                        () => start = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        ),
                      );
                    }
                  },
                ),
                const Text(
                  'Two minutes of padding are added before and after. The app must remain available; sleeping devices cannot record.',
                  style: TextStyle(fontSize: 12, color: mutedColor),
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
                if (await perform(
                  c,
                  () => app.recording.schedule(
                    app.current!,
                    selected,
                    start,
                    start.add(Duration(minutes: duration)),
                  ),
                  success: 'Recording scheduled.',
                )) {
                  if (c.mounted) Navigator.pop(c);
                }
              },
              child: const Text('Schedule'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    if (!PlaybackCapabilities.current.recording) {
      return const EmptyState(
        icon: Icons.fiber_manual_record_outlined,
        title: 'Recording needs a native device.',
        body:
            'Use the Android, Windows, or Linux app for local recording. This platform does not provide reliable unattended recording.',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Keep the good moments.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: schedule,
                icon: const Icon(Icons.add),
                label: const Text('Schedule'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: app.recording.visible(app.current!),
            builder: (context, snapshot) {
              final jobs =
                  (snapshot.data ?? [])
                      .where(
                        (j) =>
                            app.current!.admin ||
                            j['profile'] == app.current!.id,
                      )
                      .toList()
                    ..sort((a, b) => (b['start'] as int).compareTo(a['start']));
              if (jobs.isEmpty) {
                return const EmptyState(
                  icon: Icons.fiber_manual_record_outlined,
                  title: 'Worth watching again.',
                  body:
                      'Record live TV now or schedule a programme from the guide. Recordings stay on this device.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: jobs.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, i) {
                  final j = jobs[i];
                  return ListTile(
                    leading: Icon(
                      j['status'] == 'recording'
                          ? Icons.fiber_manual_record
                          : Icons.video_file_outlined,
                      color: j['status'] == 'recording'
                          ? Colors.redAccent
                          : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(j['title']),
                    subtitle: Text(
                      '${DateFormat('EEE d MMM · HH:mm').format(DateTime.fromMillisecondsSinceEpoch(j['start']))}  ·  ${j['status']}\n${j['error'] ?? ''}',
                    ),
                    trailing: Wrap(
                      children: [
                        if (j['status'] == 'completed' &&
                            (j['path'] as String).isNotEmpty)
                          IconButton(
                            tooltip: 'Open recording',
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () async {
                              await perform(context, () async {
                                final item = await app.store.item(
                                  app.current!,
                                  j['item'],
                                );
                                if (item == null ||
                                    !app.current!.allows(item)) {
                                  throw StateError('Recording is restricted.');
                                }
                                if (!kIsWeb &&
                                    defaultTargetPlatform ==
                                        TargetPlatform.android) {
                                  await const MethodChannel(
                                    'app.lumen/device',
                                  ).invokeMethod('openRecording', {
                                    'path': j['path'],
                                  });
                                } else if (!await launchUrl(
                                  Uri.file(j['path']),
                                )) {
                                  throw StateError(
                                    'No application could open the recording.',
                                  );
                                }
                              });
                            },
                          ),
                        if (['scheduled', 'recording'].contains(j['status']))
                          IconButton(
                            tooltip: 'Cancel recording',
                            icon: const Icon(Icons.stop_circle_outlined),
                            onPressed: () async {
                              await app.recording.cancel(app.current!, j);
                              if (mounted) setState(() {});
                            },
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
