#!/bin/bash
# Локальный цикл тестирования: собрать DEV-сборку → положить в /Applications → перезапустить.
#
# ⚠️ Это ставит DEV (com.keytamer.tamer.dev): свой домен настроек, СВОЙ лог (Keytamer-dev.log),
# Sparkle ВЫКЛЮЧЕН — такая копия никогда не обновится.
set -e
cd "$(dirname "$0")"

bash build-app.sh

VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Keytamer.app/Contents/Info.plist 2>/dev/null)
echo "▸ Перезапуск и установка в /Applications (v$VER)…"

# Закрыть работающий экземпляр (мягко, потом жёстко).
osascript -e 'tell application "Keytamer" to quit' 2>/dev/null || true
pkill -f "Keytamer.app/Contents/MacOS/Keytamer" 2>/dev/null || true
sleep 0.6

# Заменить в /Applications.
rm -rf /Applications/Keytamer.app
cp -R Keytamer.app /Applications/Keytamer.app

# Пост-проверка установленного бандла: версия совпадает, нет вложенности, подпись цела.
INST_VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" /Applications/Keytamer.app/Contents/Info.plist 2>/dev/null)
if [ -e /Applications/Keytamer.app/Keytamer.app ]; then
  echo "  ⚠️  ОШИБКА: вложенный /Applications/Keytamer.app/Keytamer.app — установка битая!"
elif [ "$INST_VER" != "$VER" ]; then
  echo "  ⚠️  ОШИБКА: установлена v$INST_VER, ожидалась v$VER — старая версия не заменилась!"
elif codesign --verify --deep --strict /Applications/Keytamer.app 2>/dev/null; then
  echo "  проверка установки: v$INST_VER, подпись --deep --strict OK (TCC стабилен)"
else
  echo "  ⚠️  ОШИБКА: установленный бандл не проходит codesign --deep --strict (TCC будет слетать)"
fi

# Запустить свежую версию.
open /Applications/Keytamer.app
BID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" /Applications/Keytamer.app/Contents/Info.plist)
echo "✓ Установлено и запущено: /Applications/Keytamer.app  (v$VER, $BID)"
echo "  ⚠️ Это DEV-сборка: без автообновлений, настройки/лог — свои."
