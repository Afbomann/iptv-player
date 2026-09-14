import 'package:flutter/material.dart';
import '../core/models.dart';

const canvasColor = Color(0xff101713);
const panelColor = Color(0xff19231d);
const limeColor = Color(0xffd5ed9c);
const mutedColor = Color(0xffa5b2a8);

ThemeData lumenTheme({
  Color accent = limeColor,
  bool light = false,
  bool compact = false,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: light ? Brightness.light : Brightness.dark,
    primary: accent,
    surface: light ? const Color(0xfff3f3e9) : canvasColor,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'Manrope',
    visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontFamily: 'Newsreader',
        fontSize: 48,
        height: 1.1,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Newsreader',
        fontSize: 34,
        color: scheme.onSurface,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? Colors.white : panelColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .5),
      space: 32,
    ),
    focusColor: accent.withValues(alpha: .25),
  );
}

String friendlyError(Object e) {
  if (e is FormatException) return e.message;
  if (e is StateError) return e.message;
  return 'The operation could not be completed. Check your connection and try again.';
}

void message(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> perform(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) message(context, success);
    return true;
  } catch (e) {
    if (context.mounted) message(context, friendlyError(e));
    return false;
  }
}

Future<bool> confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;

class Brand extends StatelessWidget {
  const Brand({super.key, this.small = false});
  final bool small;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: small ? 30 : 38,
        height: small ? 30 : 38,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.wb_twilight_rounded,
          color: Color(0xff243120),
          size: 24,
        ),
      ),
      const SizedBox(width: 12),
      Text(
        'lumen',
        style: TextStyle(
          fontSize: small ? 24 : 29,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
        ),
      ),
    ],
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      letterSpacing: 2.4,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: mutedColor, height: 1.7),
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    ),
  );
}

class MediaTile extends StatelessWidget {
  const MediaTile({
    super.key,
    required this.item,
    required this.onTap,
    this.onFavorite,
    this.onMore,
    this.selected = false,
  });
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final VoidCallback? onMore;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? accent
              : Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: .4),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onMore,
        focusColor: accent.withValues(alpha: .25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          HSLColor.fromAHSL(
                            1,
                            (item.name.hashCode.abs() % 90 + 85).toDouble(),
                            .18,
                            .23,
                          ).toColor(),
                          const Color(0xff17241c),
                        ],
                      ),
                    ),
                  ),
                  if (item.logo.startsWith('http'))
                    Padding(
                      padding: EdgeInsets.all(
                        item.kind == MediaKind.live ? 24 : 0,
                      ),
                      child: Image.network(
                        item.logo,
                        fit: item.kind == MediaKind.live
                            ? BoxFit.contain
                            : BoxFit.cover,
                        cacheWidth: 480,
                        errorBuilder: (_, _, _) => _monogram(),
                      ),
                    )
                  else
                    _monogram(),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        item.kind == MediaKind.live
                            ? '● LIVE'
                            : item.kind.name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          letterSpacing: 1,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (onFavorite != null)
                    Positioned(
                      right: 3,
                      bottom: 3,
                      child: IconButton(
                        tooltip: 'Toggle favorite',
                        onPressed: onFavorite,
                        icon: const Icon(
                          Icons.star_outline_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (onMore != null)
                    Positioned(
                      left: 3,
                      bottom: 3,
                      child: IconButton(
                        tooltip: 'Channel options',
                        onPressed: onMore,
                        icon: const Icon(Icons.more_horiz, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.group,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: mutedColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monogram() => Center(
    child: Text(
      item.name.isEmpty ? 'L' : item.name.substring(0, 1).toUpperCase(),
      style: const TextStyle(
        fontFamily: 'Newsreader',
        fontSize: 64,
        color: Color(0xffcbd9bb),
      ),
    ),
  );
}
