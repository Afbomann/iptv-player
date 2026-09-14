import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../playback/engine.dart';

Future<void> itemActions(
  BuildContext context,
  AppController app,
  MediaItem item,
) async {
  final groups = Map<String, dynamic>.from(
    app.current!.preferences['customGroups'] ?? {},
  );
  final name = TextEditingController();
  final setting = await app.store.setting('engine:${item.id}');
  var engine = setting?['engine'] ?? 'automatic';
  if (!PlaybackCapabilities.current.engines.any((e) => e.name == engine)) {
    engine = 'automatic';
  }
  if (!context.mounted) {
    name.dispose();
    return;
  }
  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(item.name),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your custom groups',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                for (final group in groups.keys.toList())
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(group),
                    value: (groups[group] as List).contains(item.id),
                    onChanged: (checked) => set(() {
                      final members = List<String>.from(groups[group]);
                      if (checked == true) {
                        members.add(item.id);
                      } else {
                        members.remove(item.id);
                      }
                      groups[group] = members.toSet().toList();
                    }),
                  ),
                TextField(
                  controller: name,
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: 'New group',
                    suffixIcon: IconButton(
                      tooltip: 'Create group',
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final value = name.text.trim();
                        if (value.isEmpty || groups.length >= 30) return;
                        set(() {
                          groups[value] = <String>{
                            ...List<String>.from(groups[value] ?? []),
                            item.id,
                          }.toList();
                          name.clear();
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: engine,
                  decoration: const InputDecoration(
                    labelText: 'Engine for this channel',
                  ),
                  items:
                      [
                            EngineKind.automatic,
                            ...PlaybackCapabilities.current.engines,
                          ]
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.name,
                              child: Text(e.name.toUpperCase()),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => engine = v,
                ),
                if (app.current!.admin) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: item.id)),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy ID for parental controls'),
                  ),
                ],
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
              await app.preferences({'customGroups': groups});
              await app.store.setSetting('engine:${item.id}', {
                'engine': engine,
              });
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
}
