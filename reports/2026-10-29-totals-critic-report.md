# ОТЧЕТ ВЕРХОВНОГО АРБИТРАЖА TOTALS-CRITIC (5-ЭШЕЛОННЫЙ КАСКАД)

**Проект:** [Keytamer](file:///Users/manar/AIII/projects/keytamer)  
**Дата аудита:** 2026-10-29  
**Целевой охват:** Реализация расширенного управления диктовкой ([ADR-009](file:///Users/manar/AIII/projects/keytamer/HISTORY.md#L137-L148), [ADR-010](file:///Users/manar/AIII/projects/keytamer/HISTORY.md#L149-L161), [ADR-011](file:///Users/manar/AIII/projects/keytamer/HISTORY.md#L162-L177))  
**Верховный арбитр:** totals-critic (The Supreme Court of Final Appeal & Meta-Meta-Critique Layer)  
**Арбитражный вердикт:** **CONDITIONAL PASS** (Условно принят с обязательным устранением дефектов P0/P1)

---

## 1. [ECHELON 1]: PRIMARY CRITIC (Первичный ревизор точек входа)

### 1.1. Трассировка точек входа и контрактов

1. **Параллельное сосуществование Keytamer и Keyboop ([ADR-009](file:///Users/manar/AIII/projects/keytamer/HISTORY.md#L137-L148)):**
   - Точка входа: [`AppDelegate.acquireSingleInstanceLock()`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/AppDelegate.swift#L1150-L1164).
   - Поведение: Проверка файла замка легаси-приложения `Application Support/Keyboop/singleton.lock` выполняется в неблокирующем режиме (`flock(legacyFD, LOCK_EX | LOCK_NB)`). При обнаружении активного процесса Keyboop фиксируется информационная запись в логе без аварийного выхода (`return false` удален).
   - Изоляция собственного замка: Keytamer удерживает эксклюзивный дескриптор в `Application Support/Keytamer/singleton.lock`.
   - Фактический статус процессов в ОС: процесс Keytamer активен (PID 17425, `/Applications/Keytamer.app/Contents/MacOS/Keytamer` со штампом сборки `2026-10-29 02:56`), Keyboop не запущен. Конфликтов блокировок нет.

2. **Бесшовная миграция настроек из `ru.keyboop.app` ([ADR-010](file:///Users/manar/AIII/projects/keytamer/HISTORY.md#L149-L161)):**
   - Точка входа: [`AppSettings.migrateFromKeyboopIfNeeded()`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/AppSettings.swift#L145-L171).
   - Вызов: Инициализатор [`AppSettings.init()`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/AppSettings.swift#L70-L73).
   - Логика: Чтение домена `persistentDomain(forName: "ru.keyboop.app")` с черным списком системных префиксов (`SU`, `NSWindow Frame`, `NSNav`) и служебных ключей (`lastRunVersion`, `lastCrashScanAt`). Запись в `UserDefaults.standard` только при отсутствии сохраненного значения в Keytamer (`d.object(forKey: key) == nil`).
   - Идемпотентность: Флаг `didMigrateFromKeyboop` гарантирует однократное выполнение.

3. **Пауза и возобновление аудиозаписи по Пробелу ([ADR-011](file:///Users/manar/AIII/projects/keytamer/HISTORY.md#L162-L177)):**
   - Точка входа: [`EventTap.handleKeyDown`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L562-L568).
   - Условие: `s.voicePauseEnabled`, `keyCode == Int64(s.voicePauseKeyCode)` (код 49), `VoiceController.shared.isRecording`, отсутствие модификаторов `Cmd`, `Ctrl`, `Opt`.
   - Захват: Вызов `swallowDown(keyCode)` с парным поглощением `keyUp` в [`EventTap.handleKeyUp`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L833).
   - Маршрутизация: `VoiceController.shared.togglePause()`.

4. **Отмена записи по клавише Command ([ADR-011](file:///Users/manar/AIII/projects/keytamer/HISTORY.md#L162-L177)):**
   - Точка входа: [`EventTap.handleFlags`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L985-L997).
   - Условие: `s.voiceCancelByCommand`, `VoiceController.shared.isRecording`, `isCmdKey` (54 или 55), наличие флага `.maskCommand`, отсутствие посторонних модификаторов.
   - Сброс: `voiceModArmed = false`, `voiceActive = false`, `VoiceGate.set(false)`, `VoiceController.shared.cancel()`, возврат `true`.

5. **Вставка последней расшифровки по 2× Option ([ADR-011](file:///Users/manar/AIII/projects/keytamer/HISTORY.md#L162-L177)):**
   - Точка входа: [`EventTap.handleFlags`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L999-L1017).
   - Детектор: окно 280 мс (`now - lastPasteDictationTap < 0.28`), отсутствие других клавиш, отмена отложенного вызова диктовки `pendingVoiceWorkItem?.cancel()`.

---

## 2. [ECHELON 2]: PROTOCOLS SCOUT (Технический скаут низкого уровня)

### 2.1. Исследование CoreAudio и потокобезопасности AudioRecorder

1. **Синхронизация состояния паузы:**
   - Поле [`paused`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/AudioRecorder.swift#L55) защищено общим `NSLock` (`lock`).
   - Свойства [`isPaused`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/AudioRecorder.swift#L89) и методы [`pause()`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/AudioRecorder.swift#L93-L98) / [`resume()`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/AudioRecorder.swift#L100-L105) выполняют захват `lock`.
   - В методах [`start()`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/AudioRecorder.swift#L118) и [`stop()`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/AudioRecorder.swift#L411) флаг `paused` гарантированно сбрасывается в `false` под замком.

2. **Обработка буферов в `captureOutput`:**
   - В [`AudioRecorder.captureOutput`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/AudioRecorder.swift#L486-L501) проверка аппаратного сигнала (`rms > 0 -> nonZeroSeen = true`) выполняется **до** проверки паузы. Это исключает ложное срабатывание сторожа аппаратного сбоя `deadSignalWatchdog` во время паузы пользователя.
   - При активном флаге `paused`:
     - Вызов `samples.append` не производится, предотвращая накопление тишины и рассинхрон аудиодорожки.
     - Вызовы `_onChunk` (потоковый EOU) и `_onDraft` (живой черновик) блокируются.
     - Замок освобождается перед вызовом хука уровня `lv?(0)`, что предотвращает дедлок и обнуляет индикатор волны.
     - Сэмплы из CoreAudio утилизируются без накопления очередей в памяти.

### 2.2. Архитектура низкоуровневого перехвата в CGEventTap

1. **Поглощение клавиши Пробел:**
   - В [`EventTap.swift#L563-L567`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L563-L567) перехват Пробела происходит с проверкой `event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty`. Это предотвращает перехват системных аккордов (например, `⌘Space` Spotlight).
   - Вызов `swallowDown(keyCode)` регистрирует код клавиши в `swallowedDownKeyCodes`, а в секции `.keyUp` ([строка 833](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L833)) парное отпускание поглощается, исключая появление фантомных символов или залипаний в системе.

---

## 3. [ECHELON 3]: META-CRITIC (Состязательный метакритик 2-го порядка)

### 3.1. Анализ противоречий и ложных гипотез

1. **Гипотеза о гонке потоков при чтении `AudioRecorder.isPaused`:**
   - Проверка: свойство `isPaused` как в `AudioRecorder`, так и транзитно в `VoiceController` читается под `lock`. Обращение потокобезопасно.

2. **Гипотеза о дублировании ключей локализации:**
   - Проверка: скрипт валидации зафиксировал, что все 836 ключей в [`L10n.swift`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/L10n.swift) являются строго уникальными. Ключи `voice.pauseEnabled`, `voice.pauseEnabledSub`, `voice.pauseEnabledHelp`, `voice.cancelByCommand`, `voice.pasteTrigger`, `voice.pasteDoubleOpt` и `voice.paused` зарегистрированы корректно в русской и английской локализациях.

3. **Аудит набора тестов `RemediationTests.swift`:**
   - Тест 9 ([`Tests/RemediationTests.swift#L389-L432`](file:///Users/manar/AIII/projects/keytamer/Tests/RemediationTests.swift#L389-L432)) проверяет исключительно статическое наличие подстрок (`contains("func pause()")`, `contains("togglePause")`, `contains("pasteDictationTrigger")`).
   - Тест не моделирует последовательность поступления событий `flagsChanged` и `keyDown` в конечный автомат `EventTap`. В результате критические дефекты рантайма не были обнаружены тестами.

---

## 4. [ECHELON 4]: RECURSIVE INQUISITOR (Рекурсивный стресс-инквизитор)

### 4.1. Вскрытые критические дефекты реализации

#### ДЕФЕКТ 1 (КРИТИЧЕСКИЙ, P0): Ложный запуск новой записи после 2× Option вставки
- **Локализация:** [`Sources/Keytamer/EventTap.swift:999-1073`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L999-L1073)
- **Механика сбоя:**
  1. Пользователь выполняет первый тап Option (`down` -> `up`):
     - На `down`: фиксируется `lastPasteDictationTap = now`, взводится `voiceModArmed = true`.
     - На `up`: взвод `voiceModArmed` снимается, и в строках [1064-1069](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1064-L1069) планируется отложенный вызов `toggleVoice()` через 250 мс (`pendingVoiceWorkItem`).
  2. Пользователь выполняет второй тап Option (`down`, например через 120 мс):
     - В блоке двойного тапа ([строки 1007-1011](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1007-L1011)) условие `now - lastPasteDictationTap < 0.28` срабатывает: `pendingVoiceWorkItem?.cancel()` отменяет первый вызов, и инициируется вставка текста `handlePasteDictationHotkey()`.
     - **КРИТИЧЕСКАЯ ОШИБКА:** Обработка события продолжается ниже по коду! В строках [1056-1059](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1056-L1059) событие нажатия второго Option снова обрабатывается веткой диктовки: `voiceModArmed = true`!
  3. Пользователь отпускает второй Option (`up`):
     - Флаг `voiceModArmed` равен `true`.
     - Условие `else if voiceModArmed` ([строка 1060](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1060)) срабатывает.
     - Так как вставка текста не переводит `VoiceGate.isActive` в `true`, условие `!VoiceGate.isActive` истинно!
     - Код планирует **НОВЫЙ** отложенный вызов `pendingVoiceWorkItem = work` на запуск диктовки через 250 мс!
  4. Через 250 мс после двойного нажатия Option Keytamer внезапно включает микрофон и начинает запись звука прямо поверх только что вставленного текста.

#### ДЕФЕКТ 2 (ВЫСОКИЙ, P1): Затирание индикатора паузы таймером длительности записи
- **Локализация:** [`Sources/Keytamer/VoiceIndicator.swift:247-259`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceIndicator.swift#L247-L259) и [`VoiceIndicator.swift:614-627`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceIndicator.swift#L614-L627)
- **Механика сбоя:**
  1. При вызове `VoiceIndicator.shared.setPaused(true)` выставляется текст:
     `self.label.stringValue = L10n.t("voice.paused")` («Пауза»), и останавливается волна `self.wave.stop()`.
  2. Однако периодический таймер [`startTicker()`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceIndicator.swift#L614-L627) продолжает работать каждые 0.5 секунды.
  3. На очередном тике таймера проверяется:
     `let s = self.elapsedString()` (например, `"0:03"`).
     Так как `"0:03" != "Пауза"`, таймер безусловно перезаписывает метку:
     `self.label.stringValue = s` (`"0:03"`).
  4. Надпись «Пауза» исчезает с экрана менее чем через 500 мс и заменяется секундомером.
  5. Время в паузе не вычитается из `recStart`: секундомер продолжает тикать, как будто запись продолжается.

#### ДЕФЕКТ 3 (СРЕДНИЙ, P2): Преждевременная отмена записи по нажатию Command (Down vs Up)
- **Локализация:** [`Sources/Keytamer/EventTap.swift:986-996`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L986-L996)
- **Механика сбоя:**
  1. Проверка `s.voiceCancelByCommand` выполняется по событию нажатия (`hasCmd = !flags.intersection(.maskCommand).isEmpty`).
  2. В macOS при нажатии любого сочетания клавиш (например, `⌘C`, `⌘Tab`, `⌘A`) событие `flagsChanged` с нажатым Command доставляется **до** события `keyDown` сопутствующей клавиши.
  3. В момент прихода `flagsChanged` модификатор Command нажат в одиночку (`soloCmd == true`).
  4. Код мгновенно отменяет диктовку `VoiceController.shared.cancel()` и поглощает событие (`return true`), делая невозможным использование любых служебных сочетаний с клавишей Command во время записи.

---

## 5. [ECHELON 5]: TOTALS ARBITER (Верховный арбитр итогов и синтеза)

### 5.1. Канонический реестр выявленных замечаний

| ID | Уровень | Компонент | Описание дефекта | Последствия |
| :--- | :--- | :--- | :--- | :--- |
| **DEF-01** | **P0** | [`EventTap.swift:1007-1069`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L1007-L1069) | Взвод `voiceModArmed` на втором тапе 2× Option при вставке | Через 250 мс после вставки текста самопроизвольно включается запись микрофона |
| **DEF-02** | **P1** | [`VoiceIndicator.swift:247-259, 614-627`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/VoiceIndicator.swift#L247-L259) | Конфликт `setPaused` с тикером `startTicker` | Надпись «Пауза» затирается цифрами таймера через <500 мс, время паузы засчитывается в запись |
| **DEF-03** | **P2** | [`EventTap.swift:986-996`](file:///Users/manar/AIII/projects/keytamer/Sources/Keytamer/EventTap.swift#L986-L996) | Отмена по Command срабатывает на `flagsChanged` DOWN | Любая попытка нажать `⌘C`/`⌘Tab` во время записи мгновенно убивает диктовку |
| **DEF-04** | **P2** | [`Tests/RemediationTests.swift:389-432`](file:///Users/manar/AIII/projects/keytamer/Tests/RemediationTests.swift#L389-L432) | Вакуумные тесты на проверку подстрок (`assertIn`) | Отсутствие симуляции двойных тапов и перехода состояний в регрессионном тесте |

---

### 5.2. Пошаговый план устранения замечаний (Action Plan)

1. **Исправление DEF-01 (P0): Подавление взвода диктовки при распознавании двойного тапа Option**
   - В `EventTap.swift` при успешном детектировании двойного тапа (`now - lastPasteDictationTap < 0.28`):
     - Выставлять флаг `pasteDictationJustTriggered = true` и сбрасывать `voiceModArmed = false`.
     - В блоке `if s.voiceHotkeyMode == "modkey"` проверять `!pasteDictationJustTriggered`. При отпускании Option сбрасывать `pasteDictationJustTriggered = false` без планирования `toggleVoice`.
2. **Исправление DEF-02 (P1): Корректный статус паузы в VoiceIndicator**
   - Ввести флаг `private var isPaused = false` и накопление длительности паузы `pauseStart: Date?`, `accumulatedPauseTime: TimeInterval`.
   - В `startTicker()` проверять: если `isPaused`, отображать локализованную строку `L10n.t("voice.paused")` и не инкрементировать счетчик записи.
3. **Исправление DEF-03 (P2): Перевод отмены по Command на отпускание (Solo Tap Up)**
   - Взводить флаг `cmdCancelArmed = true` на `flagsChanged` с нажатым Command (при отсутствии других модификаторов).
   - Сбрасывать `cmdCancelArmed = false` при любом `keyDown` (аккорд с другой клавишей).
   - Вызывать отмену `VoiceController.shared.cancel()` строго при отпускании Command, если `cmdCancelArmed` остался взведенным.
4. **Исправление DEF-04 (P2): Закалка набора тестов `RemediationTests.swift`**
   - Расширить `RemediationTests.swift` полноценной имитацией конечного автомата `EventTap` для последовательности событий:
     `Option Down -> Option Up -> Option Down -> Option Up`.
     Гарантировать проверку инварианта: `toggleVoiceCalled == false` при двойном тапе.

---

### 5.3. Итоговое арбитражное заключение

Архитектурная база ([ADR-009](file:///Users/manar/AIII/projects/keytamer/HISTORY.md#L137-L148) неблокирующий singleton lock Keyboop, [ADR-010](file:///Users/manar/AIII/projects/keytamer/HISTORY.md#L149-L161) миграция настроек из `ru.keyboop.app`, CoreAudio потокобезопасность `AudioRecorder.pause/resume`) выполнена качественно и стабильно.  
Однако наличие дефекта **DEF-01 (P0)** (самопроизвольный запуск записи после двойного нажатия Option) и **DEF-02 (P1)** (затирание интерфейса паузы) не позволяет выдать безоговорочный допуск.

**Финальный вердикт:** **CONDITIONAL PASS**  
Допуск в Production открывается немедленно после реализации пунктов 1 и 2 Action Plan.
