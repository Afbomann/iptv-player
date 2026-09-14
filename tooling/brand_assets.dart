// Rebuild platform sizes from the generated brand masters. No network access.
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final icon = img.decodePng(
    File('assets/branding/lumen-icon.png').readAsBytesSync(),
  )!;
  final banner = img.decodePng(
    File('assets/branding/lumen-banner.png').readAsBytesSync(),
  )!;
  img.Image fit(img.Image source, int width, int height) {
    final result = img.Image(width: width, height: height, numChannels: 4);
    img.fill(result, color: img.ColorRgba8(16, 23, 19, 255));
    final scale = width / source.width < height / source.height
        ? width / source.width
        : height / source.height;
    final resized = img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
    img.compositeImage(
      result,
      resized,
      dstX: (width - resized.width) ~/ 2,
      dstY: (height - resized.height) ~/ 2,
    );
    return result;
  }

  void png(String path, img.Image image) {
    File(path).parent.createSync(recursive: true);
    File(path).writeAsBytesSync(img.encodePng(image));
  }

  for (final entry in {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  }.entries) {
    png(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      fit(icon, entry.value, entry.value),
    );
  }
  png(
    'android/app/src/main/res/drawable-nodpi/lumen_launch.png',
    fit(icon, 192, 192),
  );
  png(
    'android/app/src/main/res/drawable-xhdpi/lumen_tv_banner.png',
    fit(banner, 320, 180),
  );
  for (final size in [192, 512]) {
    png('web/icons/Icon-$size.png', fit(icon, size, size));
    png('web/icons/Icon-maskable-$size.png', fit(icon, size, size));
  }
  png('web/favicon.png', fit(icon, 32, 32));
  png('tvos/Runner/Assets.xcassets/LaunchImage.imageset/launch.png', fit(banner, 960, 540));
  png('web/lumen-icon.png', fit(icon, 192, 192));
  File(
    'windows/runner/resources/app_icon.ico',
  ).writeAsBytesSync(img.encodeIco(fit(icon, 256, 256)));
  for (final file in Directory(
    'ios/Runner/Assets.xcassets/AppIcon.appiconset',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.png'))) {
    final old = img.decodePng(file.readAsBytesSync())!;
    // iOS icons must be opaque RGB.
    png(file.path, fit(icon, old.width, old.height).convert(numChannels: 3));
  }
  for (var scale = 1; scale <= 3; scale++) {
    png(
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage${scale == 1 ? '' : '@${scale}x'}.png',
      fit(icon, 128 * scale, 128 * scale),
    );
  }
  for (final file
      in Directory('tvos/Runner/Assets.xcassets/AppIcon.brandassets')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))) {
    final old = img.decodePng(file.readAsBytesSync())!;
    final back =
        file.path.contains('Back.imagestacklayer') ||
        file.path.contains('Top Shelf');
    png(
      file.path,
      back
          ? fit(banner, old.width, old.height)
          : img.Image(width: old.width, height: old.height, numChannels: 4),
    );
  }
  stdout.writeln(
    'Updated Android/TV, iOS, tvOS, Windows and web icons. Linux packaging uses the web icon.',
  );
}
