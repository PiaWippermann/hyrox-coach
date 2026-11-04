#!/bin/bash
# Erzeugt alle App-Icons aus dem LogoPainter. Aufruf im Ordner app/: bash tool/make_app_icons.sh
set -euo pipefail
flutter test tool/render_app_icon_test.dart > /dev/null
SRC=build/app_icon_1024.png

# iOS: Größen aus den Dateinamen im AppIcon-Set (z. B. Icon-App-20x20@3x.png → 60 px)
IOS=ios/Runner/Assets.xcassets/AppIcon.appiconset
for f in "$IOS"/Icon-App-*.png; do
  name=$(basename "$f" .png)
  base=$(echo "$name" | sed -E 's/Icon-App-([0-9.]+)x[0-9.]+@([0-9])x/\1 \2/')
  px=$(echo "$base" | awk '{printf "%d", $1 * $2}')
  sips -z "$px" "$px" "$SRC" --out "$f" > /dev/null
done

# Android: mipmap-Stufen
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  dir=${pair%%:*}; px=${pair##*:}
  sips -z "$px" "$px" "$SRC" --out "android/app/src/main/res/mipmap-$dir/ic_launcher.png" > /dev/null
done
echo "App-Icons aktualisiert."
