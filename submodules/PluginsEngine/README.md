# PluginsEngine — движок плагинов для Telegram-ETG (iOS)

Порт движка плагинов exteraGram (Android) на iOS с сохранением совместимости
плагинов: Android-плагины (.plugin = Python-файлы) запускаются без изменений,
если используют высокоуровневый API. Хуки Java-классов маппятся на iOS-точки
через таблицу совместимости (AndroidCompatMap).

## Архитектура

```
Python-плагин (*.plugin, dunder-метаданные __id__/__name__/...)
      │ import extera_compat.base_plugin → BasePlugin
      ▼
extera_compat (sdk/python/) — API-совместимость с extera SDK
      │ _etg.call(command, json) — нативный C-модуль
      ▼
ETGBridge (PythonBridge.c) → ETGBridgeDispatcher (Swift, JSON-команды)
      ▼
PluginController (синглтон) — реестр, хуки, меню, watchdog, safe mode
      ▼
Точки встраивания в Telegram-iOS:
  • EnqueueMessage.swift → message.send.before (модификация/отмена отправки)
  • AppDelegate → app_start + инициализация движка
  • DebugController → пункт "Plugins" (дебаг-меню, 10 тапов по иконке настроек)
```

## Управление состоянием

- `UserDefaults`: `plugin_enabled_<id>`, `plugins_had_crash`, `plugins_crashed_plugin_id`, `pluginsSafeMode` — порт crash-safe логики exteraGram.
- Watchdog: маркирует плагин перед исполнением; если приложение умрёт внутри плагина — при рестарте виновник отключается (или глобальный Safe Mode при "manual!").

## Совместимость с Android-плагинами

| API | iOS |
|---|---|
| `BasePlugin` (on_plugin_load/unload, on_app_event, on_send_message_hook, on_update_hook(s)) | ✅ полностью |
| `add_hook`, `add_menu_item`, `get/set_setting`, `create_settings` | ✅ полностью |
| `client_utils`: send_message, edit_message, delete, forward, send_file, download_media, get_chat_members | ✅ через bridge |
| `hook_method("org.telegram...")` | ⚠️ через AndroidCompatMap (маппится на точки iOS; неизвестные — no-op + запись в Documents/plugins-unmapped.log) |
| `hook_utils` Java-рефлексия (get_private_field и пр.) | ❌ нет Java-объектов на iOS (no-op с логом) |
| pip `requirements` | ⚠️ только pure-python пакеты (нативных wheel для iOS нет) |

## Стратегии хуков (порт PluginsConstants.Strategy)

`DEFAULT` / `MODIFY` (цепочка) / `MODIFY_FINAL` / `CANCEL` — как в exteraGram.

## Точки встраивания (pointId)

- `message.send.before` — перед отправкой сообщения
- `updates.container` — контейнер апдейтов (пока объявлена, встраивание — TODO)
- `chat.open`, `app.event` — объявлены

Таблица Android→iOS: `Sources/AndroidCompatMap.swift`.

## Файлы

- `Sources/PluginController.swift` — оркестратор (порт PluginsController)
- `Sources/PythonRuntime.swift` — встроенный CPython (BeeWare Python.xcframework)
- `Sources/ETGBridge/PythonBridge.c` — нативный CPython-модуль `_etg`
- `Sources/Plugin.swift, PluginStore.swift, HookRecords.swift, PluginsWatchdog.swift, PluginPip.swift, PluginMetadataParser.swift, AndroidCompatMap.swift`
- `Sources/UI/` — менеджер плагинов (UIKit)
- `sdk/python/extera_compat/` — Python API-совместимость

## Сборка

CPython берётся в CI (`.github/workflows/build.yml`) из BeeWare Python-Apple-support 3.14-b10.
ipa собирается неподписанным (fake-codesigning) — ставится через AltStore/TrollStore.
