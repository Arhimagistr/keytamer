# Конспект сессии: Архитектурный рефакторинг Keytamer, режим сосуществования и релиз v1.0.0

- **Дата:** 2026-10-25
- **Проект:** Keytamer (`/Users/manar/AIII/projects/keytamer`)
- **Статус:** Выполнено (Release v1.0.0)
- **Удаленный репозиторий:** `https://github.com/Arhimagistr/keytamer.git`

---

## 1. Контекст и цели задачи
1. Полный архитектурный рефакторинг кодовой базы с жестким соблюдением стандартов разработки:
   - Doc-First (`doc-first-development`): ADR-006, ADR-007, ADR-008, ADR-009.
   - TDD (`tdd-workflow`): Fail-to-Pass циклы RED -> GREEN для каждого батча.
   - YAGNI (`yagni-development`): ликвидация Single-Implementation Interfaces, слияние мелких файлов, устранение неиспользуемых переменных и кортежей.
2. Состязательная независимая приемка через субагенты `work-verifier` (10 контрольных гейтов) и `totals-critic` (арбитраж и финальный вердикт).
3. Обеспечение режима параллельного сосуществования (Coexistence Mode) Keytamer и Keyboop без взаимной блокировки singleton lock (Keyboop остается рабочей утилитой, Keytamer запускается параллельно).
4. Локальная сборка и развертывание в `/Applications/Keytamer.app`.
5. Публикация релизного тега `v1.0.0` на GitHub.

---

## 2. Реализованные изменения по этапам

### Батч 1: Полный ребрендинг и изоляция ресурсов (ADR-006)
- **Doc-First:** Зафиксирован ADR-006 в `HISTORY.md` (коммит `b74e562`).
- **TDD:** Тест Test 4 в `Tests/RemediationTests.swift` (коммит `199c6b3` `[RED]`).
- **Код:**
  - Создан `Sources/Keytamer/KeytamerMark.swift` с канонической отрисовкой векторного логотипа Keytamer, удален `KeyboopMark.swift`.
  - В `build-app.sh` настроена упаковка анимации онбординга `keytamer-logo-anim.mp4`.
  - В `MenuBarController.swift` переключен вызов на `KeytamerMark.draw(in:color:)`.
  - В `Logger.swift` префикс логов изменен на `Keytamer:`.
  - В `VoiceHistoryWindow.swift` экспорт истории переведен на префикс `Keytamer-`.
  - В `L10n.swift` очищены 91 упоминание бренда Keyboop, добавлены нотификации `keytamerLanguageChanged` с обратной совместимостью.
- **Коммит:** `48c2f7b` `[GREEN]`.

### Батч 2: Архитектурный YAGNI-рефакторинг и гигиена компилятора (ADR-007)
- **Doc-First:** Зафиксирован ADR-007 в `HISTORY.md` (коммит `9dd0749`).
- **TDD:** Тест Test 5 в `Tests/RemediationTests.swift` (коммит `13f553e` `[RED]`).
- **Код:**
  - Ликвидирован shallow-файл `SlapTypes.swift`: перечисления `SlapSensitivity` и `SlapDetectorAvailability` перемещены непосредственно в `SlapDetector.swift`.
  - В `Engine.swift` устранены предупреждения Swift 5 tuple shuffle deprecation: унифицирован порядок кортежей `(word: String, deleteCount: Int, tail: String)` для методов `fixTwoLeadingCaps`, `fixCapsLockWord`, `fixTypo`.
  - Очищены неиспользуемые переменные в `TextReplacer.swift` (`let u`), `NotchIsland.swift` (`let nH`), `AppBanner.swift` (`let w`).
- **Коммит:** `b056b1a` `[GREEN]`.

### Батч 3: Надежность ввода и протокольная гигиена (ADR-008)
- **Doc-First:** Зафиксирован ADR-008 в `HISTORY.md` (коммит `d68d1ce`).
- **TDD:** Тест Test 6 в `Tests/RemediationTests.swift` (коммит `a302327` `[RED]`).
- **Код:**
  - В `TextReplacer.swift` удален статический `vKey = 9`. Внедрено динамическое разрешение клавиши `⌘V` через `DynamicKeymap.latinKeyCodes["v"] ?? 9` для безотказной работы на раскладках Dvorak, Colemak, AZERTY.
  - В `MenuBarController.swift` кэш подложки индикатора `plateCache` защищен мьютексом `plateLock = NSLock()`.
  - В `VoiceIndicator.swift` добавлен singleton lifecycle с подпиской на нотификацию `NSApplication.didChangeScreenParametersNotification` для корректной геометрии на внешних мониторах.
- **Коммит:** `b2066a4` `[GREEN]`.

### Состязательная верификация и арбитраж
- **Work-Verifier:** Запуск изолированного субагента QA. Проверено 10 гейтов, 27 проверок, включая codesign и strict sandboxing. Вердикт: **PASS**.
- **Totals-Critic:** Арбитраж субагента высшей критики. Закрыты все 12 архитектурных замечаний. Вердикт: **PASS (ACCEPTED FOR PRODUCTION)**.
- **Отчеты:** Сохранены в `reports/2026-10-25-3batch-refactoring-verification.md` и `reports/2026-10-25-totals-critic-final.md`.

### Режим параллельного сосуществования (ADR-009)
- **Doc-First:** Зафиксирован ADR-009 в `HISTORY.md` (коммит `67603d8`).
- **TDD:** Тест Test 7 в `Tests/RemediationTests.swift` (коммит `23d8e44` `[RED]`).
- **Код:**
  - В `Sources/Keytamer/AppDelegate.swift` снята блокировка `return false` при обнаружении `Keyboop/singleton.lock`.
  - Вместо блокировки процесс Keytamer фиксирует информационную запись в логе и удерживает собственный независимый замок `Keytamer/singleton.lock`.
- **Коммит:** `c5e0e99` `[GREEN]`.

### Сборка, установка и релиз
- В `build-app.sh` добавлено авто-определение валидной подписи codesigning (`Apple Development` или ad-hoc `-`), предотвращающее сбои сборки Sparkle при отсутствии самоподписанного сертификата.
- Выполнена сборка и чистая установка в `/Applications/Keytamer.app` через `install-local.sh`.
- Оба приложения запущены и функционируют параллельно:
  - Keytamer: PID 69040, 69048.
  - Keyboop: PID 77258, 77259.
- Создан аннотированный тег `v1.0.0` и опубликован на GitHub вместе со всеми коммитами.

---

## 3. Рекомендации по эксплуатации двух приложений
1. **Горячие клавиши диктовки:** Чтобы избежать одновременного перехвата нажатий обоими приложениями, рекомендуется назначить разные модификаторы (например, `⌥` для Keyboop и `fn` или `⌃⌥` для Keytamer).
2. **Авто-исправление набора:** В экспериментальном Keytamer можно отключить авто-замену раскладки на лету в строке меню, оставив ее только в Keyboop, либо тестировать новые эвристики изолированно.
3. **Хранилища и логи:** Полностью изолированы (`~/Library/Application Support/Keyboop` и `~/Library/Application Support/Keytamer`).
