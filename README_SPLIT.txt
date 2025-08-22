# Végvári Ablak – két ZIP telepítés
1) Csomagold ki **vegvari_ablak_part1_base.zip** tartalmát egy üres mappába.
2) Ugyanoda bontsd ki **vegvari_ablak_part2_code.zip** tartalmát és engedd felülírni a fájlokat, ha kéri.
3) A gyökérben legyen: `pubspec.yaml`, `.github/…`, `lib/main.dart`.
4) Ezután futtasd: `flutter pub get` majd `flutter create --platforms=android --org hu.vegvariablak .` és `flutter build apk --debug`.
