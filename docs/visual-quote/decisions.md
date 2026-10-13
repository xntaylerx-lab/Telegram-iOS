# Visual Quote — журнал решений

Каждое решение: что выбрано, почему, что было альтернативой. Новые записи добавляются снизу.

## M0 — Окружение (2026-10-12)

### D-001. Клон живёт в `~/Developer/Telegram-iOS`, ветка `visual-quote`
Причина: в пути `~/Documents/Telegram contest` есть пробел, Documents может синхронизироваться с iCloud. Так задано в задании (раздел 4).

### D-002. Сборка для симулятора через `Make.py build` с фиктивной подписью из `build-system/fake-codesigning`
Выбрано из двух допустимых путей задания (`generateProject --disableProvisioningProfiles` или `build` с fake-codesigning).
Причина: `build` даёт готовый `bazel-bin/Telegram/Telegram.ipa`, на который завязан штатный workflow обновления приложения в симуляторе из `CLAUDE.md` репозитория (копия `.app` из `.ipa`). Для `generateProject` нужен Xcode-проект и сборка через xcodebuild, а путь Xcode-managed signing требует настоящий Apple team.
Команда (из корня клона):
```
python3 build-system/Make/Make.py --cacheDir="$HOME/telegram-bazel-cache" build \
  --configurationPath="$HOME/Developer/telegram-config/build-config.json" \
  --codesigningInformationPath=build-system/fake-codesigning \
  --buildNumber=1 --configuration=debug_sim_arm64
```

### D-003. Конфиг сборки — копия в `~/Developer/telegram-config/build-config.json` с `team_id = C67CF9S4VU` и `bundle_id = ph.telegra.Telegraph`
Причина: `Make.py` отбирает provisioning-профили по точному префиксу `team_id.bundle_id` в `application-identifier` профиля (`BuildConfiguration.py`, `copy_profiles_from_directory`). Профили в `fake-codesigning` выписаны только на `C67CF9S4VU.ph.telegra.Telegraph`; при другом `bundle_id`/`team_id` ни один профиль не подходит, `aps-environment` не находится и сборка завершается с ошибкой до запуска Bazel.
Оригинальный `config/build-config.json` в папке проекта не изменён; изменённая копия лежит вне репозитория и вне git. Ключи api_id/api_hash в репозиторий не попадают: `build-input/*` в `.gitignore`.
Статус: ждёт подтверждения Ники (bundle id совпадает с официальным Telegram; для симулятора это безопасно, для распространения — нет).

### D-004. Для Xcode 26 нужен отдельный компонент Metal Toolchain
Факт: первая сборка упала на `MetalCompile` с ошибкой `cannot execute tool 'metal' due to missing Metal Toolchain`. Компонент скачан командой `xcodebuild -downloadComponent MetalToolchain` (688 МБ). Это обязательный шаг при настройке окружения с нуля — записать в README.

### D-005. Тестовое окружение Telegram (test DC)
Факт из кода: клиент поддерживает test DC только через аргумент запуска `--ui-test` (`AppDelegate.swift`, `isUITest`). В этом режиме используется отдельная папка данных `telegram-ui-tests-data`, которая **стирается при каждом запуске**, и регистрация идёт на тестовые серверы. Тестовые номера `99966XYYYY` (страна `+999`), код подтверждения — цифра DC пять раз (`docs/ui-testing.md`).
Проверено на симуляторе: при запуске с `--ui-test` клиент подключается к тестовым DC (149.154.167.40, 149.154.175.10, 149.154.175.117), без флага — к продакшн-адресам. Отдельного переключателя в Debug Settings нет. Следствие: без небольшой правки кода тестовый аккаунт не переживает перезапуск приложения. Решение, как вести разработку (реальные аккаунты или test DC с правкой), — за Никой после M0.
