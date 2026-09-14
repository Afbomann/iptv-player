import 'package:flutter/painting.dart';

/// Bound both decoded dimensions without stretching provider artwork. A width
/// alone leaves unusually tall posters/logos free to allocate huge bitmaps.
ImageProvider boundedArtwork(String url, {int width = 480, int height = 480}) =>
    ResizeImage(
      NetworkImage(url),
      width: width,
      height: height,
      policy: ResizeImagePolicy.fit,
    );
