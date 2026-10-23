# Keytamer

> **wrong layout? keytamer.**
> Бесплатный open-source переключатель раскладки для macOS, который исправляет
> неверно набранный текст без повреждения буфера обмена. Поддерживает локальный
> голосовой ввод на базе нейросетей непосредственно на устройстве.

Keytamer автоматически распознает и исправляет текст, набранный в ошибочной раскладке (RU <-> EN),
как во время ввода, так и по границе слова. Доступно гибкое ручное исправление по горячим клавишам,
автозамена сниппетов и локальная диктовка.

## Ключевые возможности

- Прямой ввод без использования буфера обмена: текст исправляется через синтез событий ввода без перезаписи системного clipboard.
- Локальный голосовой ввод: интеграция Whisper и Parakeet (Apple Neural Engine). Обработка аудио происходит полностью на Mac.
- Перевод выделенного текста: сочетание горячих клавиш заменяет выделенный фрагмент через Apple Translation API (macOS 15+).
- Настраиваемое окно отката: отмена и повторное преобразование последнего слова или группы слов.
- Сниппеты и шаблоны: быстрый ввод предопределенного текста по аббревиатурам независимо от активной раскладки.
- Полная приватность: отсутствие исходящего сетевого трафика с текстом ввода или аудиозаписями.

## Требования к системе

- Apple Silicon (M1 и новее): macOS 14.0+
- Intel: macOS 13.0+ (голосовой ввод работает через Whisper на CPU)

## Сборка из исходников

Для сборки требуются Xcode Command Line Tools и внешние библиотеки в каталоге `vendor/`:

```bash
mkdir -p vendor && cd vendor

# 1. whisper.cpp — распознавание речи
git clone https://github.com/ggml-org/whisper.cpp
cd whisper.cpp
cmake -B build-macos14 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF
cmake --build build-macos14 -j
cd ..
```

Зависимости `Sparkle.framework` и `FluidAudio` размещаются в `vendor/sparkle/` и `vendor/fluidaudio-prebuilt/`.

Сборка приложения:

```bash
bash build-app.sh      # dev-сборка -> Keytamer.app
bash install-local.sh  # сборка и установка в /Applications/Keytamer.app
```

## Лицензия

MIT License. См. файл LICENSE.
