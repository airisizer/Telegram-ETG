"""BasePlugin — порт com.exteragram SDK base_plugin.BasePlugin.

Плагин exteraGram наследует BasePlugin; при импорте модуля класс находится
через _findPluginClass, инстанцируется и кладётся в module.__plugin_instance__.
Вся регистрация хуков/меню копится в инстансе и забирается Swift-стороной
через dump_hooks(); события приходят через dispatch_event/dispatch_method_hook/
dispatch_menu_click.
"""

import json

from ._bridge import bridge_call, log


class _MethodHookSpec:
    def __init__(self, class_name, method_name, mode, filters):
        self.class_name = class_name
        self.method_name = method_name
        self.mode = mode
        self.filters = filters or []
        self.callback = None  # назначается декоратором/регистрацией


class BasePlugin:
    # --- метаданные (переопределяются dunder-полями модуля либо атрибутами) ---
    id = ""
    name = ""
    description = ""
    author = ""
    version = "1.0"
    icon = ""
    app_version = ""
    sdk_version = ""

    def __init__(self):
        self._event_hooks = []      # [{name, match_substring, priority, callback}]
        self._method_hooks = []     # [_MethodHookSpec]
        self._menu_items = []       # [{menu_type, text, ...}]
        self._plugin_id = self.id or getattr(self, "__module__", "plugin")

    # ================================================================
    # API для плагинов (совместимость с extera SDK)
    # ================================================================

    # --- жизненный цикл (переопределяются плагином) ---
    def on_plugin_load(self):
        pass

    def on_plugin_unload(self):
        pass

    def on_app_event(self, event_type):
        pass

    # --- события (переопределяются или регистрируются) ---
    def on_send_message_hook(self, account, params):
        """Вернуть dict с изменёнными params, None = без изменений."""
        return None

    def on_update_hook(self, account, update):
        return None

    def on_updates_hook(self, account, updates):
        return None

    def on_request(self, account, request):
        return None

    def on_response(self, account, response, error):
        return None

    # --- регистрация событийных хуков (add_hook из extera SDK) ---
    def add_hook(self, name, callback=None, priority=0, match_substring=False):
        record = {
            "name": name,
            "priority": priority,
            "match_substring": bool(match_substring),
            "callback": callback,
        }
        self._event_hooks.append(record)
        bridge_call("register_hook", {
            "plugin_id": self._plugin_id,
            "name": name,
            "priority": priority,
            "match_substring": bool(match_substring),
        })
        return record

    # --- Xposed-стиль хуки методов (совместимость с Android-плагинами) ---
    def hook_method(self, class_name, method_name, mode="before_after",
                    filters=None, callback=None):
        """extera: hook_method("org.telegram.messenger.X", "method", ...).
        На iOS класс маппится через таблицу совместимости (см. Swift AndroidCompatMap);
        если маппинга нет — хук зарегистрирован, но не вызовется (лог no-op)."""
        spec = _MethodHookSpec(class_name, method_name, mode, filters)
        spec.callback = callback
        self._method_hooks.append(spec)
        return spec

    def hook_class(self, class_name, **kwargs):
        return self.hook_method(class_name, "__all__", **kwargs)

    def hook_all_methods(self, class_name, **kwargs):
        return self.hook_method(class_name, "*", **kwargs)

    # --- меню ---
    def add_menu_item(self, menu_type, text, on_click=None, item_id=None,
                      icon=None, subtext=None, priority=0, condition=None):
        item = {
            "menu_type": menu_type,
            "text": text,
            "subtext": subtext,
            "icon": icon,
            "item_id": item_id or "%s:%d" % (self._plugin_id, len(self._menu_items)),
            "priority": priority,
            "condition": condition,
            "on_click": on_click,
        }
        self._menu_items.append(item)
        return item["item_id"]

    # --- настройки (совместимость с plugin_settings extera) ---
    def create_settings(self):
        """Плагин переопределяет: возвращает список dict-описаний элементов
        (header/switch/selector/input/edit_text/text/divider/custom)."""
        return []

    def get_setting(self, key, default=None):
        res = bridge_call("get_setting", {
            "plugin_id": self._plugin_id, "key": key, "default": default,
        })
        return res.get("value", default)

    def set_setting(self, key, value):
        bridge_call("set_setting", {
            "plugin_id": self._plugin_id, "key": key, "value": value,
        })

    def get_all_settings(self):
        res = bridge_call("get_all_settings", {"plugin_id": self._plugin_id})
        return res.get("value", {})

    def export_settings(self):
        return json.dumps(self.get_all_settings())

    # --- уведомления пользователю ---
    def show_alert(self, title, text):
        bridge_call("show_alert", {"title": title, "text": text})

    def show_bulletin(self, text):
        bridge_call("show_bulletin", {"text": text})

    def log(self, message):
        log(self._plugin_id, message)

    # ================================================================
    # Служебное: вызывается Swift-стороной (контракт движка)
    # ================================================================

    @staticmethod
    def _findPluginClass(module):
        """Ищет класс-наследник BasePlugin в модуле (как в extera SDK)."""
        import inspect
        for _, obj in inspect.getmembers(module, inspect.isclass):
            if issubclass(obj, BasePlugin) and obj is not BasePlugin:
                return obj
        return None

    def dump_hooks(self):
        return {
            "events": [
                {k: v for k, v in h.items() if k != "callback"}
                for h in self._event_hooks
            ],
            "method_hooks": [
                {
                    "class": s.class_name,
                    "method": s.method_name,
                    "mode": s.mode,
                    "filters": s.filters,
                }
                for s in self._method_hooks
            ],
            "menu_items": [
                {k: v for k, v in m.items() if k != "on_click"}
                for m in self._menu_items
            ],
            "settings": self.create_settings() or [],
        }

    def dispatch_event(self, name, payload_json):
        """Точка входа событий из Swift. Ответ: {strategy, payload}."""
        try:
            payload = json.loads(payload_json) if payload_json else {}
        except Exception:
            payload = {}
        result_payload = payload
        strategy = "DEFAULT"
        try:
            # встроенные события жизненного цикла
            if name == "on_plugin_load":
                self.on_plugin_load()
            elif name == "on_plugin_unload":
                self.on_plugin_unload()
            elif name == "on_app_event":
                self.on_app_event(payload.get("event_type", ""))
            # переопределяемые хуки сообщений/апдейтов
            elif name in ("send_message_hook", "message.send.before"):
                r = self.on_send_message_hook(payload.get("account", 0), payload)
                if r is not None:
                    result_payload = r
                    strategy = "MODIFY"
            elif name in ("update", "message.receive"):
                r = self.on_update_hook(payload.get("account", 0), payload)
                if r is not None:
                    result_payload = r
                    strategy = "MODIFY"
            # зарегистрированные add_hook
            for hook in self._event_hooks:
                cb = hook.get("callback")
                if cb is None:
                    continue
                match = (payload.get("name") == hook["name"]) or (
                    hook["match_substring"] and hook["name"] in str(payload.get("name", ""))
                ) or hook["name"] == name
                if match:
                    r = cb(payload)
                    if isinstance(r, dict):
                        if r.get("cancel"):
                            return {"strategy": "CANCEL", "payload": result_payload}
                        if r.get("final"):
                            return {"strategy": "MODIFY_FINAL", "payload": r.get("payload", result_payload)}
                        result_payload = r.get("payload", result_payload)
                        strategy = "MODIFY"
        except Exception as e:  # плагин упал — не роняем приложение
            self.log("dispatch_event %s failed: %s" % (name, e))
        return {"strategy": strategy, "payload": result_payload}

    def dispatch_method_hook(self, class_name, method_name, args_json):
        """Точка входа xposed-хуков. Возвращает (возможно изменённый) args dict."""
        try:
            args = json.loads(args_json) if args_json else {}
        except Exception:
            args = {}
        for spec in self._method_hooks:
            if spec.class_name != class_name and spec.class_name != "*":
                continue
            if spec.method_name not in (method_name, "*", "__all__"):
                continue
            cb = spec.callback
            if cb is None:
                continue
            try:
                r = cb(args)
                if isinstance(r, dict):
                    args = r
            except Exception as e:
                self.log("method hook %s#%s failed: %s" % (class_name, method_name, e))
        return args

    def dispatch_menu_click(self, item_id, context):
        for item in self._menu_items:
            if item["item_id"] == item_id and item.get("on_click"):
                try:
                    item["on_click"](context)
                except Exception as e:
                    self.log("menu click failed: %s" % e)
                return


def _register_instance(module, instance):
    """Вызывается загрузчиком (PythonRuntime) после импорта модуля."""
    module.__plugin_instance__ = instance
    return instance
