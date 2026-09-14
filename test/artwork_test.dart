import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/ui/artwork.dart';

void main() {
  test('Artwork bounds both dimensions while preserving aspect ratio', () {
    final image =
        boundedArtwork('https://example.test/poster.png') as ResizeImage;
    expect(image.width, 480);
    expect(image.height, 480);
    expect(image.policy, ResizeImagePolicy.fit);
    final poster =
        boundedArtwork(
              'https://example.test/poster.png',
              width: 360,
              height: 540,
            )
            as ResizeImage;
    expect(poster.width, 360);
    expect(poster.height, 540);
  });
}
