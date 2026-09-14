import 'dart:async';
import 'package:flutter/material.dart';
import '../playback/engine.dart';
import 'common.dart';

class TrackPicker extends StatefulWidget {
  const TrackPicker({super.key, required this.engine});
  final PlaybackEngine engine;
  @override
  State<TrackPicker> createState() => _TrackPickerState();
}

class _TrackPickerState extends State<TrackPicker> {
  List<PlaybackTrack>? tracks;
  String? error;
  bool busy = false, loading = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  Future<void> refresh() async {
    if (busy || loading || widget.engine.terminated) return;
    loading = true;
    try {
      final values = await widget.engine.tracks();
      if (mounted) {
        setState(() {
          tracks = values;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Tracks are not available yet. Wait for playback, then retry.',
        );
      }
    } finally {
      loading = false;
    }
  }

  Future<void> select(PlaybackTrack track) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.engine.selectTrack(track);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'The engine could not switch this track. It may be unavailable in this browser or stream.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await refresh();
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sound & subtitles'),
    content: SizedBox(
      width: 580,
      height: 390,
      child: tracks == null && error == null
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(icon: Icon(Icons.graphic_eq), text: 'Audio'),
                      Tab(
                        icon: Icon(Icons.subtitles_outlined),
                        text: 'Subtitles',
                      ),
                    ],
                  ),
                  if (busy) const LinearProgressIndicator(minHeight: 2),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        for (final subtitle in [false, true])
                          Builder(
                            builder: (context) {
                              final values = (tracks ?? [])
                                  .where((t) => t.subtitle == subtitle)
                                  .toList();
                              if (values.isEmpty) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Text(
                                      subtitle
                                          ? 'No subtitle tracks are exposed by this stream and engine. Browsers often cannot expose embedded MP4/MKV subtitles. HLS needs subtitle renditions or supported captions; try mpv or VLC on a native device for embedded tracks.'
                                          : 'No selectable audio tracks are exposed by this engine. Browser MP4/MKV playback may have sound without exposing alternate tracks. HLS needs audio renditions; native mpv or VLC can expose more embedded formats.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: mutedColor),
                                    ),
                                  ),
                                );
                              }
                              return ListView.builder(
                                itemCount: values.length,
                                itemBuilder: (_, i) {
                                  final track = values[i];
                                  return ListTile(
                                    selected: track.selected,
                                    leading: Icon(
                                      track.selected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                    ),
                                    title: Text(track.label),
                                    trailing: track.selected
                                        ? const Icon(
                                            Icons.check,
                                            color: limeColor,
                                          )
                                        : null,
                                    onTap: busy ? null : () => select(track),
                                  );
                                },
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          error = null;
          refresh();
        },
        child: const Text('Refresh tracks'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
