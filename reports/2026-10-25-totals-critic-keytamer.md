# Отчет 5-эшелонного состязательного аудита totals-critic: Keytamer

- **Дата проведения:** 2026-10-25
- **Объект аудита:** `/Users/manar/AIII/projects/keytamer`
- **Комиссия аудита:** 5-эшелонный состязательный каскад totals-critic (Primary Critic, Protocols Scout, Meta-Critic, Recursive Inquisitor, Totals Arbiter)
- **Итоговый вердикт:** CONDITIONAL_FAIL (блокирующие архитектурные и логические дефекты P0, требующие устранения до релиза)
- **Сводка дефектов:** CRITICAL: 2, HIGH: 3, MEDIUM: 4, LOW: 3 (Всего: 12)

---

## 1. СТАТУС ПО ЭШЕЛОНАМ КАСКАДА

| Эшелон | Наименование | Статус | Подтвержденных находок |
| :--- | :--- | :--- | :--- |
| **Эшелон 1** | Primary Critic & Entrypoint Tracer | `FAIL` | 4 |
| **Эшелон 2** | Protocols & Low-Level Scout | `WARNING` | 3 |
| **Эшелон 3** | Meta-Critic & Blindspot Detector | `FAIL` | 2 |
| **Эшелон 4** | Recursive Inquisitor & Stress Sentinel | `WARNING` | 2 |
| **Эшелон 5** | Totals Arbiter & Synthesis Engine | `FAIL` | 12 (канонический реестр) |

---

## 2. ДЕТАЛЬНЫЕ РЕЗУЛЬТАТЫ ПО ЭШЕЛОНАМ

### 2.1. [ECHELON 1: PRIMARY CRITIC] — Построчная ревизия кода и сверка контрактов

1. **Точки входа и компиляция:**
   - Выполнен проверочный запуск сборки: `KEYTAMER_SIGN_ID="-" bash /Users/manar/AIII/projects/keytamer/build-app.sh`.
   - Результат: код возврата `0`. Приложение успешно компилируется через `swiftc` с флагами оптимизации `-O`, связывается с `Sparkle.framework`, `FluidAudio`, `whisper.cpp` и проходит ad-hoc подпись `codesign --deep --strict`.
   - В процессе сборки зафиксированы предупреждения компилятора: устаревший API `SecKeychain` в `VoiceHistory.swift:311-313`, неиспользуемые переменные в `TextReplacer.swift:422`, `NotchIsland.swift:458`, `AppBanner.swift:190` и кортежные предупреждения Swift 5 в `Engine.swift:1828`.

2. **Ревизия `TextReplacer.pasteViaClipboard` (строки 241–298):**
   - Метод выполняет сохранение снапшота буфера через `pb.pasteboardItems` и эмуляцию нажатия `⌘V` через приватный источник событий `CGEventSource(stateID: .privateState)`.
   - *Дефект 1 (HIGH):* В строке 291 при восстановлении пользовательского снапшота вызывается `it.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))`. Это ошибочно маркирует исходные данные пользователя как транзитные (временные), из-за чего внешние менеджеры буфера обмена (Maccy, Raycast, Paste, Alfred) отбрасывают или не индексируют восстановленный буфер пользователя.
   - *Дефект 2 (HIGH):* В `sendCmdV` захардкожен `vKey = 9` (ANSI V). На альтернативных раскладках ввода (Dvorak, Colemak) виртуальный код клавиши 9 транслируется в символ точки (`.`), порождая системную комбинацию `⌘.` (отмена/прерывание) вместо вставки текста.

3. **Сверка контрактов документации (`README.md`, `ROADMAP.md`, `HISTORY.md`, `CHANGELOG.md`) с кодом:**
   - *Дефект 3 (CRITICAL):* В `CHANGELOG.md` (п. 34) и `ROADMAP.md` заявлен полный переход на идентификатор `com.keytamer.tamer` и независимую изоляцию приложения. Фактический аудит кодовой базы выявил свыше 365 вхождений легаси-имен `Keyboop` и `ru.keyboop.app`.
   - Самый опасный разрыв зафиксирован в путях файловой системы:
     * `AppDelegate.swift:1152`: берет `Application Support/Keytamer/singleton.lock`.
     * `VoiceHistory.swift:21, 295`: читает и пишет базу в `Application Support/Keyboop/history.enc`.
     * `VoiceController.swift:717`: маркер занятости пишет в `Application Support/Keyboop/voice-busy`.
     * `VoiceClips.swift:55`: сохраняет зашифрованные клипы в `Application Support/Keytamer/voice/`.
   - *Следствие:* Если у пользователя в системе запущен оригинальный `Keyboop`, `Keytamer` не видит его замок (разные файлы `singleton.lock`) и запускается параллельно. Возникает одновременная работа двух активных `CGEventTap`, что приводит к двойному перехвату, двойной автозамене и порче набора.

4. **Ревизия `VoiceIndicator`, `MenuBarController`, `AppSettings`, `LayoutManager`:**
   - В `MenuBarController.swift:151` словарь `plateCache` объявлен как статический изменяемый `[String: NSImage]` без синхронизации доступа, что создает риск гонки потоков при параллельных обновлениях.
   - В `VoiceIndicator.swift` кнопки управления в острове скрываются во время записи согласно спецификации, неоновая волна и цвет `techCyan` соответствуют когнитивной разметке.
   - В `LayoutManager.swift` методы `availableLayouts()` и `selectSource(id:)` корректно управляют retain-циклами CoreFoundation через `takeRetainedValue()`.

---

### 2.2. [ECHELON 2: PROTOCOLS SCOUT] — Анализ системных протоколов macOS и рантайма

1. **CGEventTap и подсистема ввода:**
   - Тап инициализируется как активный `.cgSessionEventTap` с маской `.headInsertEventTap` и типом `.defaultTap`.
   - Предохранитель шторма таймаутов (`tapStormLimit = 3` за `tapStormWindow = 60с`) реализован корректно и спасает macOS от зависания курсора и клавиатуры при медленных колбэках.
   - Однако внутри `convertBeforeReturn` (Engine.swift:2270) часть проверок выполняется синхронно прямо в теле колбэка WindowServer, что повышает дисперсию задержки ввода.

2. **NSPasteboard и тайминги владения:**
   - В `TextReplacer.pasteViaClipboard` окно владения `PasteboardOwnership.beginOwnedWindow()` удерживается асинхронно в течение 250 мс (`.now() + 0.25`).
   - На протяжении этих 250 мс `ClipboardWatcher` полностью глушит мониторинг буфера. Любое честное копирование, совершенное пользователем в эти 250 мс, безвозвратно теряется и не попадает в историю буфера.
   - Задержка 250 мс является жестко зафиксированной эвристикой: в тяжелых приложениях на базе Web/Electron задержка обработки `⌘V` может превысить 250 мс, приводя к тому, что приложение вставит восстановленный старый буфер вместо диктовки.

3. **CoreAudio, AVCaptureSession и дескрипторы:**
   - `AudioRecorder.swift` опирается на `AVCaptureSession` с прямой конфигурацией `audioSettings` (16 kHz Float32 mono). Дескрипторы сессии корректно закрываются на очереди `sessionQueue`.
   - Реализована двухконтурная защита: сторож тишины (3 секунды цифровых нулей) и сторож отсутствия буферов (2 секунды). При сбое выполняется эскалация к системному дефолту, затем к встроенному микрофону.
   - Утечек мак-портов в `IOHIDEventSystemClient` и `AppleSPU` не обнаружено.

4. **Анализ GCD-очередей и дедлоков:**
   - `com.keytamer.synth` (`TextReplacer`): сериализованная очередь с QoS `.userInteractive`.
   - *Дефект 4 (HIGH):* `TextReplacer.insert` и `replace` отправляют синтетические задания в очередь `synthQueue`, тогда как `pasteViaClipboard` исполняется на `DispatchQueue.main`. Отсутствует взаимное исключение между `synthQueue` и `pasteViaClipboard`. Если во время выполнения очереди синтетики будет инициирована вставка через буфер, события Backspace/Unicode и `⌘V` перемешаются во времени.

5. **TCC и безопасность:**
   - Сборка Dev изолирована через `com.keytamer.tamer.dev`, `SUFeedURL` удаляется, что исключает несанкционированное обновление и подмену прав доступа TCC.

---

### 2.3. [ECHELON 3: META-CRITIC] — Слепые зоны и отсечение ложных дефектов

1. **Критическая слепая зона: сбой временного оверрайда языка по модификатору (CRITICAL):**
   - *Локализация:* `Sources/Keytamer/EventTap.swift`, строки 977–980.
   - *Анализ кода:*
     ```swift
     if voiceModArmed {
         let vm = relevantMods(CGEventFlags(rawValue: s.voiceHotkeyModifiers))
         if !relevantMods(flags).subtracting(vm).isEmpty { voiceModArmed = false }
     }
     ```
   - *Механизм бага:*
     Когда пользователь удерживает клавишу оверрайда (например, Command) и нажимает клавишу диктовки (например, правый Option), взводятся флаги `voiceModArmed = true` и `voiceModArmedOverride = true`.
     При отпускании правого Option генерируется системное событие `flagsChanged`. На входе в метод (строки 977–980) вычисляется разность: `relevantMods(flags).subtracting(vm)`. Поскольку клавиша Command все еще удерживается, результат не пуст (содержит `.maskCommand`).
     Строка 979 немедленно сбрасывает `voiceModArmed = false`!
     Далее в строке 1009 условие `else if voiceModArmed` оказывается ложным. Вызов `toggleVoice(override: voiceModArmedOverride)` блокируется.
   - *Следствие:* Временный оверрайд языка по модификатору в режиме toggle никогда не срабатывает при штатном удержании Command.

2. **Поведение в Web/Electron против AppKit и потеря фокуса:**
   - В AppKit `replaceInOwnField` осуществляет мгновенную замену через `NSTextView.insertText`. В Electron-приложениях Accessibility часто возвращает таймаут или пустые границы каретки (`CaretLocator`), из-за чего ввод деградирует до синтетических пакетов `CGEvent`.

3. **Secure Input:**
   - Политика `SecureInputPolicy.canWrite` верифицирована. При активном скрытом вводе в чужом окне Keytamer корректно опрашивает саброль элемента (`AXSecureTextField`). Если под кареткой поле пароля или Electron не отвечает, вставка блокируется, а текст диктовки сохраняется в истории `VoiceHistory`.

4. **Отсечение ложных дефектов и оверинжиниринга раннера:**
   - Раннер `totals_critic.py` выдал флаг `[CRITICAL]` на строке 20 в `install-local.sh`: `rm -rf /Applications/Keytamer.app` из-за эвристического сопоставления подстроки `"rm -rf /"`.
   - *Арбитраж:* Это ложноположительное срабатывание статического сканера (False Positive). Команда удаляет строго изолированный целевой бандл приложения. Однако для повышения защищенности рекомендовано применить конструкцию безопасного раскрытия переменных `rm -rf "${TARGET_APP:?}"`.

---

### 2.4. [ECHELON 4: RECURSIVE INQUISITOR] — Стресс-тестирование краевых сценариев

1. **Отказоустойчивость при падении whisper.cpp / Parakeet:**
   - Если движок распознавания возвращает ненулевой код ошибки (`rc != 0`), `WhisperBridge.transcribe` возвращает пустую строку `""`.
   - В `VoiceController.deliver` при `clean.isEmpty` воспроизводится мягкий сигнал ошибки `playCue(failSound)`, осиротевший аудиоклип удаляется с диска через `VoiceClips.delete`, ресурсы освобождаются, приложение не крашится.

2. **Гонка `changeCount mismatch` в системном буфере обмена:**
   - Если во время 250 мс ожидания вставки пользователь или сторонняя утилита изменили системный буфер обмена (`pb.changeCount != ours`), строка 282 прерывает восстановление: `kbLog("voice paste clipboard: буфер сменился на чужой... — не восстанавливаю")`.
   - *Стресс-последствие:* Прежнее содержимое пользовательского буфера, скопированное в `snapshot` перед вставкой, безвозвратно уничтожается, так как `pb.clearContents()` уже выполнился на строке 259.

3. **Отключение внешнего аудиоинтерфейса во время записи:**
   - `AudioRecorder` слушает уведомление `AVCaptureDevice.wasDisconnectedNotification`.
   - При отключении сессия перезапускается на системный вход без сброса накопленного массива сэмплов `samples`.

4. **Динамическая смена геометрии экранов (Dynamic Island vs обычный дисплей):**
   - *Дефект 5 (MEDIUM):* В кодовой базе отсутствует подписка на `NSApplication.didChangeScreenParametersNotification`.
   - Если во время активного отображения индикатора пользователь подключает внешний монитор или меняет системное разрешение, координаты `NotchIsland` и плашки не пересчитываются до следующего вызова `present()`, что приводит к визуальному сдвигу и зависанию черного прямоугольника выреза в неверной экранной области.

---

## 3. КАНОНИЧЕСКИЙ РЕЕСТР ДЕФЕКТОВ (ZERO-LOSS REGISTRY)

| № | Уровень | Файл | Строка | Описание дефекта и обоснование |
| :--- | :--- | :--- | :--- | :--- |
| 1 | **[CRITICAL]** | `Sources/Keytamer/EventTap.swift` | 977–980 | Преждевременный сброс `voiceModArmed = false` при отпускании хоткея диктовки с зажатым модификатором оверрайда (`subtracting(vm)` не исключает `overMod`). Полная блокировка оверрайда языка. |
| 2 | **[CRITICAL]** | `Sources/Keytamer/AppDelegate.swift`<br>`Sources/Keytamer/VoiceHistory.swift` | 1152<br>21, 295 | Архитектурная фрагментация путей Application Support: замок берется в `Keytamer/singleton.lock`, а история и маркер пишутся в `Keyboop/`. Возможность параллельного запуска Keyboop и Keytamer с порчей ввода. |
| 3 | **[HIGH]** | `Sources/Keytamer/TextReplacer.swift` | 241, 253 | Отсутствие синхронизации и взаимного исключения между `pasteViaClipboard` (на `DispatchQueue.main`) и очередью `synthQueue` (`insert`, `replace`). Риск перемешивания пакетов синтетики. |
| 4 | **[HIGH]** | `Sources/Keytamer/TextReplacer.swift` | 291 | Запись `org.nspasteboard.TransientType` в восстанавливаемые пользовательские объекты буфера. Сторонние менеджеры буфера обмена теряют данные пользователя. |
| 5 | **[HIGH]** | `Sources/Keytamer/TextReplacer.swift` | 222–234 | Хардкод `vKey = 9` в методе `sendCmdV`. На раскладках Dvorak/Colemak эмулируется `⌘.` вместо `⌘V`, срывая вставку текста. |
| 6 | **[MEDIUM]** | `Sources/Keytamer/TextReplacer.swift` | 277–285 | Фиксированный таймаут 250 мс для восстановления буфера. В медленных Electron-приложениях буфер успевает восстановиться до того, как приложение обработает `⌘V`. |
| 7 | **[MEDIUM]** | `Sources/Keytamer/VoiceIndicator.swift`<br>`Sources/Keytamer/NotchIsland.swift` | 416–421<br>243 | Отсутствие обработки нотификации `NSApplication.didChangeScreenParametersNotification`. Дрейф координат островка при подключении/отключении мониторов. |
| 8 | **[MEDIUM]** | `Sources/Keytamer/MenuBarController.swift` | 151 | Статический кэш `plateCache: [String: NSImage]` изменяется без блокировки `NSLock`, потенциальная гонка при обновлении настроек. |
| 9 | **[MEDIUM]** | `build-app.sh`<br>`install-local.sh` | 1<br>1 | Отсутствие перехвата сигналов прерывания (`trap '...' EXIT INT TERM`) для гарантированного закрытия дочерних утилит и временных файлов сборки. |
| 10 | **[LOW]** | `install-local.sh` | 20 | Использование сырой команды `rm -rf /Applications/Keytamer.app` без проверки целостности целевого пути через переменные с защитой `${VAR:?}`. |
| 11 | **[LOW]** | `Sources/Keytamer/MenuBarController.swift` | 980–986 | Смешение локализованных ключей `L10n.t` и захардкоженных строк "Русский (RU)" / "English (EN)" в подменю языка диктовки. |
| 12 | **[LOW]** | `Sources/Keytamer/TextReplacer.swift`<br>`Sources/Keytamer/NotchIsland.swift` | 422<br>458 | Предупреждения компилятора о неиспользуемых мутабельных переменных (`var u`, `let nH`). |

---

## 4. ПРИОРИТИЗИРОВАННЫЙ ПЛАН ДЕЙСТВИЙ (ACTION PLAN)

### P0 (Блокирующие дефекты — устранить немедленно):
1. **Починить логику оверрайда языка в `EventTap.swift`:**
   В строке 979 изменить проверку сброса взвода, исключив активный модификатор оверрайда:
   ```swift
   let overMod = relevantMods(overrideModifierMask())
   if !relevantMods(flags).subtracting(vm).subtracting(overMod).isEmpty { voiceModArmed = false }
   ```
2. **Ликвидировать фрагментацию директорий ребрендинга (SSOT Storage):**
   - Унифицировать все пути к Application Support на каталог `Keytamer`:
     * В `VoiceHistory.swift` заменить `"Keyboop"` на `"Keytamer"` с автоматической однократной миграцией данных из старого каталога `Keyboop/history.enc` при его наличии.
     * В `VoiceController.swift` перевести `busyMarker` на `Keytamer/voice-busy`.
     * В `AppDelegate.swift` при захвате single-instance проверять наличие активного замка как `Keytamer/singleton.lock`, так и легаси `Keyboop/singleton.lock` для предотвращения параллельного запуска с оригинальным Keyboop.

### P1 (Высокий приоритет — дефекты протоколов и вставки):
3. **Изолировать синхронизацию буфера в `TextReplacer.swift`:**
   - Удалить ошибочную установку `TransientType` при восстановлении снапшота (строка 291).
   - Встроить выполнение `pasteViaClipboard` в координационную цепочку `synthQueue` (через асинхронный переход на main строго для операций с `NSPasteboard` с удержанием блокировки очереди синтетики).
   - Заменить сырой `vKey = 9` на динамическое определение виртуального кода клавиши 'V' для текущей активной раскладки через `TISGetInputSourceProperty` или использовать эмуляцию независимого селектора Carbon.

### P2 (Плановый приоритет — надежность и гигиена кода):
4. **Добавить адаптивность к экранам:**
   Подписаться на `NSApplication.didChangeScreenParametersNotification` в `VoiceIndicator` для немедленной инвалидации геометрии островка и плашки при изменении конфигурации дисплеев.
5. **Потокобезопасность интерфейса:**
   Защитить `MenuBarController.plateCache` через `os_unfair_lock` или `NSLock`.
6. **Shell-гигиена:**
   Добавить `trap` обработчики в сборочные скрипты и применить безопасное удаление бандлов.

---

## 5. ИТОГОВЫЙ ВЕРДИКТ ВЫСШЕЙ ИНСТАНЦИИ (TOTALS ARBITER VERDICT)

Проект **Keytamer** демонстрирует высокую культуру низкоуровневой системной интеграции с macOS (прямой перехват событий без деградации runloop, устойчивость к сбоям CoreAudio, локальное распознавание Whisper/Parakeet без утечек в сеть).

Однако релиз в текущем состоянии **НЕ ДОПУСКАЕТСЯ** из-за двух блокирующих дефектов уровня P0:
1. Поломка временного оверрайда языка диктовки в `EventTap.swift` (дефект свежего коммита `6cead84`).
2. Неполный ребрендинг путей хранилища в `VoiceHistory` и маркерах процесса, делающий приложение уязвимым к конфликтам с `Keyboop`.

**Окончательное решение:** `CONDITIONAL_FAIL`. Допуск к продакшн-релизу выдается строго после реализации пунктов плана P0 и P1.
