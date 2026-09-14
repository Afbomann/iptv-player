import 'package:flutter/material.dart';
import 'artwork.dart';

/// A small, bounded logo slot; channel names provide the accessible label.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, required this.url, this.size = 36});
  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url.trim());
    final valid =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    final fallback = Icon(
      Icons.live_tv_outlined,
      size: size * .55,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(7),
        ),
        clipBehavior: Clip.antiAlias,
        child: valid
            ? Image(
                image: boundedArtwork(
                  url.trim(),
                  width: (size * MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(1, 256),
                  height: (size * MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(1, 256),
                ),
                fit: BoxFit.contain,
                frameBuilder: (_, child, frame, synchronous) =>
                    synchronous || frame != null ? child : fallback,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}
