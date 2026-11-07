# App icon generator (dev-time only)

A standalone Dart package so its `image` dependency never enters the app.

```
cd tool/app_icon
dart pub get
# 1. Square + adaptive-icon variants from the artwork (finds the logo bounds,
#    handles the transparent background), plus logo.png: the tightly cropped
#    in-app logo used by the app's screens (an asset in pubspec.yaml):
dart run bin/prepare.dart ../../assets/icon/cypher_logo_source.png ../../assets/icon
# 2. Write every Android density, the adaptive/monochrome XML and all iOS slots:
dart run bin/install.dart ../../assets/icon ../..
```
