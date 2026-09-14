import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'core/controller.dart';
import 'data/database.dart';
import 'ui/app.dart';
import 'platform/device.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 160;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 * 1024 * 1024;
  if (!kIsWeb && !isAppleTV) MediaKit.ensureInitialized();
  try {
    final store = await LibraryStore.open();
    final app = AppController(store);
    await app.initialize();
    runApp(
      ProviderScope(
        overrides: [appProvider.overrideWith((ref) => app)],
        child: const LumenApp(),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.storage_outlined, size: 48),
                    SizedBox(height: 24),
                    Text(
                      'Lumen could not open local storage.',
                      style: TextStyle(fontSize: 24),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Check that secure storage is available. In a browser, use localhost or HTTPS, allow site storage, and make sure the SQLite web assets are deployed. Your existing data has not been reset.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
