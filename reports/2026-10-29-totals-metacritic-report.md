# ОТЧЕТ ВЕРХОВНОГО АРБИТРАЖА TOTALS-CRITIC (5-ЭШЕЛОННЫЙ КАСКАД)

**Проект:** [Keytamer](file:///Users/manar/AIII/projects/keytamer)  
**Дата аудита:** 2026-10-29  
**Целевой охват:** Реализация Phase 9 (Chunk-Batching Pause, ремедиация дефектов DEF-01–DEF-04) и Phase 10 (Универсальные триггеры, Zero-Loss отмена диктовки ADR-013)  
**Коммиты ревизии:** [`75d8297`](file:///Users/manar/AIII/projects/keytamer) и [`e57ab7b`](file:///Users/manar/AIII/projects/keytamer)  
**Верховный арбитр:** Totals Meta-Critic Arbiter (The Supreme Court of Final Appeal & Meta-Meta-Critique Layer)  
**Арбитражный вердикт:** **CONDITIONAL PASS** (Условно принят с обязательным устранением критических дефектов P0/P1 для 3× Option tripletap)

---

## 1. [ECHELON 1]: PRIMARY CRITIC (Первичный ревизор точек входа)

### 1.1. Трассировка точек входа и функциональных контрактов

1. **Сегментная пауза с батчингом (Chunk-Batching Pause, ADR-012):**
   - **Точка входа:** [`VoiceController.togglePause()`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceController.swift#L264-L297).
   - **Остановка микрофона:** При переводе в паузу вызывается `recorder.stop()`. Аудиопоток CoreAudio честно останавливается, освобождая аудиоустройство. Сэмплы сегмента сохраняются в `sessionAudioSamples`.
   - **Фоновое распознавание сегмента:** Если сегмент содержит полезный сигнал (`rms > 0.001 && samples.count > 1600`), создается асинхронная задача `Task<String, Never>`, которая изолированно транскрибирует кусок через [`transcribeSegmentSamples`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceController.swift#L234-L261) и помещается в массив `pendingSegmentTasks`.
   - **Возобновление записи:** При повторном вызове `togglePause()` вызывается `try recorder.start()`, сбрасывается флаг `isSessionPaused = false`, воспроизводится стартовый сигнал `startSound`, а индикатор размораживается вызовом `VoiceIndicator.shared.setPaused(false)`.

2. **Финализация и склейка сегментов в `VoiceController.end()`:**
   - **Точка входа:** [`VoiceController.end()`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceController.swift#L381-L473).
   - **Сбор хвоста и сегментов:** Если микрофон был активен, извлекаются `tailSamples = recorder.stop()`. Все сегменты сессии объединяются в `totalSamples`.
   - **Асинхронный батчинг:** В фоновом блоке поочередно ожидаются результаты всех фоновых задач `for task in capturedTasks { let seg = await task.value ... }`. Если хвостовой сегмент `tailSamples` не пуст, он транскрибируется через `transcribeSegmentSamples`.
   - **Единая склейка:** Все непустые распознанные текстовые блоки объединяются через пробел: `let fullText = accumulated.filter { !$0.isEmpty }.joined(separator: " ")`.
   - **Единая доставка:** Полный аудиотрек сессии сохраняется в хранилище `VoiceClips.save(samples: fullAudio)`, после чего единое полотно текста передается в [`deliver(fullText, historyOnly: ..., audio: ..., wave: ...)`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceController.swift#L839-L877).

3. **Zero-Loss сохранение всех сегментов при отмене диктовки (ADR-013):**
   - **Точка входа:** [`VoiceController.cancel()`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceController.swift#L550-L572).
   - **Поведение:** Отмена больше не сбрасывает массив накопленных сегментов `sessionTextSegments.removeAll()`. Вместо этого выставляется маркер поколения `historyOnlyGens.insert(transcribeGen + 1)` и вызывается штатный метод `end()`.
   - **Результат:** Все надиктованные сегменты дораспознаются, объединяются через пробел и сохраняются в [`VoiceHistory`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceHistory.swift) без вставки в активное поле ввода. Последующий вызов вставки последней диктовки восстанавливает 100% надиктованного текста всей сессии.

4. **Ремедиация дефектов totals-critic:**
   - **DEF-01 (P0):** В [`EventTap.swift#L1058`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1058) при срабатывании 2× Option выставляется `suppressVoiceOnNextUp = true` и `voiceModArmed = false`. На последующем отпускании Option в строке 1107 флаг подавляет ложный запуск диктовки.
   - **DEF-02 (P1):** В [`VoiceIndicator.swift#L247-L255`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceIndicator.swift#L247-L255) метод `setPaused(true)` инвалидирует таймер `ticker?.invalidate()`, обнуляет ссылку `ticker = nil`, выставляет `isPausedIndicator = true` и фиксирует надпись `voice.paused`. В [`startTicker()`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceIndicator.swift#L623) добавлен сторож `guard !self.isPausedIndicator else { return }`.
   - **DEF-03 (P2):** В [`EventTap.swift#L1023-L1034`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1023-L1034) отмена по Command взводится `cmdCancelArmed = true` на `flagsChanged` DOWN, сбрасывается в `false` при любом `keyDown` в строке 539, и срабатывает строго на solo UP.

5. **Универсальные триггеры команд (ADR-013):**
   - **Точки конфигурации:** В [`AppSettings.swift`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/AppSettings.swift#L271-L316) определены свойства `voicePauseTrigger`, `voicePauseKeyCode`, `voicePauseModifiers`, `voicePauseKeyLabel`, `voiceCancelTrigger`, `pasteDictationTrigger`.
   - **По умолчанию для паузы:** Комбинация `⌥Пробел` (`Option + Space`, `keyCode 49`, `mods = maskAlternate`).
   - **Интерфейс:** В [`SettingsWindow.swift#L4210-L4256`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/SettingsWindow.swift#L4210-L4256) добавлены пресеты паузы (`⌥Пробел`, `Пробел`, `⌃Пробел`, `⇧Пробел`, `2× Пробел`, `3× Пробел`) и интерактивный рекордер комбинаций.

---

## 2. [ECHELON 2]: PROTOCOLS SCOUT (Технический скаут низкого уровня)

### 2.1. Исследование CoreAudio и жизненного цикла AVAudioEngine
- Остановка записи через `recorder.stop()` в момент паузы полностью закрывает аудиосессию CoreAudio: аппаратный микрофон физически выключается (индикатор микрофона в macOS Control Center корректно гаснет).
- Буферы сэмплов не накапливаются в оперативной памяти в виде тишины.
- Запуск `recorder.start()` при возобновлении записи поднимает чистый граф без накопленного дрейфа таймстемпов.

### 2.2. Синхронизация потоков и фоновый инференс
- **Whisper Engine:** Вызовы инференса направляются в последовательную очередь `self.transcribeQueue.async`. Библиотека `whisper.cpp`, требующая монопольного владения контекстом модели, защищена от параллельных обращений.
- **Parakeet Engine:** Модель CoreML обрабатывается на Apple Neural Engine (ANE). Поскольку задачи сегментов запускаются последовательно по мере пауз, перегрузки ANE не происходит.
- **CGEventTap:** Обработка событий в `EventTap` сохраняет парность `swallowDown` / `swallowUp`. Для паузы поглощаются как нажатие, так и отпускание, исключая появление паразитных символов в текстовом поле ввода.

---

## 3. [ECHELON 3]: META-CRITIC (Состязательный метакритик 2-го порядка)

### 3.1. Анализ устойчивости и отсечение ложных гипотез
1. **Гипотеза о дедлоке в `Task` при завершении `end()` во время паузы:**
   - *Проверка:* Если запись находится на паузе и вызывается `end()`, `tailSamples` возвращается пустым. Цикл `for task in capturedTasks` ожидает только уже запущенные задачи. Так как `transcribeSegmentSamples` не содержит блокирующих бесконечных ожиданий (используются таймауты и безопасные продолжения `CheckedContinuation`), дедлок исключен.
2. **Гипотеза о дублировании пробелов при склейке сегментов:**
   - *Проверка:* Метод `filter { !$0.isEmpty }` и предварительная очистка `trimmingCharacters(in: .whitespacesAndNewlines)` гарантируют, что пустые или состоящие только из пробелов сегменты отбрасываются до вызова `joined(separator: " ")`.

---

## 4. [ECHELON 4]: RECURSIVE INQUISITOR (Рекурсивный стресс-инквизитор)

### 4.1. Вскрытые дефекты реализации

#### ДЕФЕКТ 1 (КРИТИЧЕСКИЙ, P0): Ложный запуск записи диктовки на первом тапе при выборе 3× Option (tripletap)
- **Локализация:** [`Sources/Keytamer/EventTap.swift:1113-1121`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1113-L1121)
- **Механика сбоя:**
  1. В строке 1113 условие арбитражной задержки проверяет строго флаг двойного тапа:
     ```swift
     if s.pasteDictationDoubleTap && !VoiceGate.isActive {
     ```
  2. В [`AppSettings.swift:714`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/AppSettings.swift#L714) свойство `pasteDictationDoubleTap` вычисляется как:
     ```swift
     var pasteDictationDoubleTap: Bool {
         get { pasteDictationTrigger == "doubletap" }
         ...
     }
     ```
  3. Если пользователь выбирает режим вставки по 3× Option (`pasteDictationTrigger = "tripletap"`), то `s.pasteDictationDoubleTap` возвращает `false`!
  4. При первом нажатии и отпускании клавиши Option срабатывает ветка `else` ([строка 1121](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1121)):
     ```swift
     } else {
         toggleVoice(override: isOver)
     }
     ```
  5. В результате при первой же попытке нажать 3× Option программа мгновенно включает запись микрофона на первом тапе!
  6. При последующих втором и третьем тапах условие в строке 1044:
     ```swift
     if isOptKey && down && solo && !VoiceController.shared.isRecording
     ```
     блокирует счетчик мульти-тапа, так как диктовка уже началась (`isRecording == true`).
  7. **Итог:** Режим вставки 3× Option (tripletap) в рантайме полностью сломан.

#### ДЕФЕКТ 2 (ВЫСОКИЙ, P1): Отсутствие отмены отложенного вызова диктовки на промежуточных тапах мульти-тапа Option
- **Локализация:** [`Sources/Keytamer/EventTap.swift:1046-1057`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1046-L1057)
- **Механика сбоя:**
  1. Отмена отложенного запуска `pendingVoiceWorkItem?.cancel()` расположена строго внутри блока финализации:
     ```swift
     if pasteDictationTapCount >= targetCount {
         ...
         pendingVoiceWorkItem?.cancel()
         pendingVoiceWorkItem = nil
     ```
  2. При выполнении тройного тапа между 1-м и 2-м тапом взводится `pendingVoiceWorkItem` с таймаутом 0.17 с.
  3. На 2-м тапе счетчик инкрементируется (`pasteDictationTapCount = 2 < 3`), но `pendingVoiceWorkItem` **не отменяется**.
  4. Если между 1-м и 3-м тапами проходит более 170 мс, таймер 1-го тапа срабатывает и включает микрофон прямо посреди серии тапов пользователя.
  5. **Итог:** Вызов `pendingVoiceWorkItem?.cancel()` обязан производиться на каждом тапе `down` в окне мульти-тапа.

#### ДЕФЕКТ 3 (СРЕДНИЙ, P2): Утечка времени нахождения в паузе в таймер длительности записи (Timer Drift)
- **Локализация:** [`Sources/Keytamer/VoiceIndicator.swift:603`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceIndicator.swift#L603)
- **Механика сбоя:**
  1. Длительность записи рассчитывается от метки старта: `Date().timeIntervalSince(recStart ?? Date())`.
  2. При паузе тикер останавливается, но время нахождения в паузе не аккумулируется и не вычитается из `recStart` при возобновлении.
  3. Если запись простояла на паузе 3 минуты, то при продолжении записи таймер мгновенно перескакивает вперед на 3 минуты.

#### ДЕФЕКТ 4 (СРЕДНИЙ, P2): Отсутствие обработки мульти-тапа для отмены записи в `handleKeyDown`
- **Локализация:** [`Sources/Keytamer/EventTap.swift:564-573`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L564-L573)
- **Механика сбоя:**
  1. В `AppSettings.swift` добавлено свойство `voiceCancelTrigger` со значениями `doubletap` и `tripletap`.
  2. В `EventTap.swift#L569` отмена записи срабатывает на первом же нажатии клавиши отмены без проверки `s.voiceCancelTrigger`.

#### ДЕФЕКТ 5 (НИЗКИЙ, P3): Регрессионный тест `RemediationTests.swift` проверяет подстроки без симуляции 3× Option
- **Локализация:** [`Tests/RemediationTests.swift:545-587`](file:///Users/manar/AIII/projects/keytamer/Tests/RemediationTests.swift#L545-L587)
- **Механика сбоя:**
  1. Тест 11 проверяет наличие строк `"tripletap"`, но автомат состояний симулирует только 2× Option.
  2. Отсутствие симуляции трех последовательных тапов привело к пропуску дефектов DEF-01-B (P0) и DEF-02-B (P1).

---

## 5. [ECHELON 5]: TOTALS ARBITER (Верховный арбитр итогов и синтеза)

### 5.1. Канонический реестр выявленных дефектов

| ID | Приоритет | Компонент | Описание дефекта | Последствия |
| :--- | :--- | :--- | :--- | :--- |
| **DEF-05** | **P0** | [`EventTap.swift:1113`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1113) | Проверка `s.pasteDictationDoubleTap` вместо учета `tripletap` | При выборе 3× Option первый же тап запускает запись микрофона вместо ожидания серии |
| **DEF-06** | **P1** | [`EventTap.swift:1046`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1046) | `pendingVoiceWorkItem?.cancel()` не вызывается на промежуточных тапах | Таймер 1-го тапа (170 мс) срабатывает во время тройного тапа и включает диктовку |
| **DEF-07** | **P2** | [`VoiceIndicator.swift:603`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceIndicator.swift#L603) | `recStart` не корректируется на время нахождения в паузе | Таймер записи скачкообразно учитывает время простоя в паузе |
| **DEF-08** | **P2** | [`EventTap.swift:569`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L569) | Отсутствие логики мульти-тапа для отмены диктовки | `voiceCancelTrigger` игнорируется при нажатии клавиши отмены |
| **DEF-09** | **P3** | [`Tests/RemediationTests.swift:580`](file:///Users/manar/AIII/projects/keytamer/Tests/RemediationTests.swift#L580) | Вакуумная проверка `contains("tripletap")` без симуляции автомата состояний | Тесты пропускают рассинхрон мульти-тапов в рантайме |

---

### 5.2. Пошаговый план исправления (Remediation Plan)

1. **Устранение DEF-05 (P0) и DEF-06 (P1) в `EventTap.swift`:**
   - В блоке обработки мульти-тапа Option ([строка 1044](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1044)) при любом нажатии Option (`down && solo`) немедленно отменять отложенный ворк-айтем:
     ```swift
     pendingVoiceWorkItem?.cancel()
     pendingVoiceWorkItem = nil
     ```
   - В строке 1113 проверять общий признак мульти-тапа:
     ```swift
     let isMultiTapPaste = (s.pasteDictationTrigger == "doubletap" || s.pasteDictationTrigger == "tripletap")
     if isMultiTapPaste && !VoiceGate.isActive {
         ...
     ```
2. **Устранение DEF-07 (P2) в `VoiceIndicator.swift`:**
   - Ввести поля `private var pauseStart: Date?` и `private var totalPausedDuration: TimeInterval = 0`.
   - При `setPaused(true)` фиксировать `pauseStart = Date()`.
   - При `setPaused(false)` прибавлять `totalPausedDuration += Date().timeIntervalSince(pauseStart)`.
   - В `elapsedString()` вычитать `totalPausedDuration`.
3. **Устранение DEF-09 (P3) в `Tests/RemediationTests.swift`:**
   - Расширить автомат состояний `DoubleTapOptionStateMachine` поддержкой 3× Option и симуляцией всех трех тапов.

---

### 5.3. Итоговое арбитражное заключение

Реализация Chunk-Batching Pause (сегментная пауза с честным остановом CoreAudio, асинхронным распознаванием и последующей единой склейкой) выполнена на высоком инженерном уровне.  
Zero-Loss сохранение всех сегментов при отмене диктовки (`cancel()`) в `VoiceHistory` (ADR-013) гарантирует целостность пользовательских данных.  
Дефекты предыдущего аудита totals-critic (DEF-01, DEF-02, DEF-03) успешно ремедиированы для базовых сценариев.  

Однако обнаружение критического дефекта **DEF-05 (P0)** (сломанный режим 3× Option с ложным стартом диктовки на 1-м тапе) и **DEF-06 (P1)** (гонка таймера 170 мс при тройном тапе) требует вердикта **CONDITIONAL PASS**.

**Финальный статус:** **CONDITIONAL PASS**  
Полный допуск к релизу открывается после устранения дефектов DEF-05 и DEF-06 по предложенному Remediation Plan.
