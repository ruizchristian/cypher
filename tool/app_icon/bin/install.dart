import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;

/// Usage: install <iconDir> <projectRoot>
/// Writes Android legacy + adaptive (with monochrome) icons and every iOS
/// AppIcon slot listed in Contents.json, from icon.png / icon_foreground.png.
void main(List<String> a) {
  final dir = a[0], root = a[1];
  img.Image load(String n) => img.decodePng(File('$dir/$n').readAsBytesSync())!;
  final full = load('icon.png'), fg = load('icon_foreground.png');
  void write(img.Image src, int px, String path, {bool opaque = false}) {
    var out = img.copyResize(src, width: px, height: px, interpolation: img.Interpolation.average);
    if (opaque) {
      final flat = img.Image(width: px, height: px, numChannels: 3);
      img.fill(flat, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, out);
      out = flat;
    }
    File(path)..parent.createSync(recursive: true)..writeAsBytesSync(img.encodePng(out));
  }
  final res = '$root/android/app/src/main/res';
  const dens = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
  dens.forEach((d, s) {
    write(full, (48 * s).round(), '$res/mipmap-$d/ic_launcher.png', opaque: true);
    write(fg, (108 * s).round(), '$res/drawable-$d/ic_launcher_foreground.png');
    write(fg, (108 * s).round(), '$res/drawable-$d/ic_launcher_monochrome.png');
  });
  File('$res/mipmap-anydpi-v26/ic_launcher.xml')..parent.createSync(recursive: true)..writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<!-- Adaptive icon (all supported versions: minSdk 30). The monochrome layer
     enables Android 13+ themed icons. Sources: assets/icon/. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
''');
  File('$res/values/ic_launcher_background.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
''');
  final set = '$root/ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final images = (jsonDecode(File('$set/Contents.json').readAsStringSync())['images'] as List).cast<Map>();
  var n = 0;
  for (final i in images) {
    final file = i['filename'] as String?;
    if (file == null) continue;
    final size = double.parse((i['size'] as String).split('x').first);
    final scale = int.parse((i['scale'] as String).replaceAll('x', ''));
    write(full, (size * scale).round(), '$set/$file', opaque: true); // App Store rejects alpha
    n++;
  }
  print('android: 5 densities x 3 images + adaptive xml; ios: $n slots');
}
