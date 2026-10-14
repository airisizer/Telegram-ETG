"""plugin_settings — совместимость с extera SDK plugin_settings.

Глобальные функции для плагинов, которые не через BasePlugin а напрямую:
    import plugin_settings
    plugin_settings.get_setting(plugin_id, key, default)
"""

from ._bridge import bridge_call


def get_setting(plugin_id, key, default=None):
    res = bridge_call("get_setting", {
        "plugin_id": plugin_id, "key": key, "default": default,
    })
    return res.get("value", default)


def set_setting(plugin_id, key, value):
    bridge_call("set_setting", {"plugin_id": plugin_id, "key": key, "value": value})


def get_all_settings(plugin_id):
    res = bridge_call("get_all_settings", {"plugin_id": plugin_id})
    return res.get("value", {})


def set_all_settings(plugin_id, settings):
    for k, v in (settings or {}).items():
        set_setting(plugin_id, k, v)


def clear_settings(plugin_id):
    bridge_call("clear_settings", {"plugin_id": plugin_id})


# Типы элементов настроек (константы PluginsConstants.Settings)
TYPE_HEADER = "header"
TYPE_TEXT = "text"
TYPE_SWITCH = "switch"
TYPE_SELECTOR = "selector"
TYPE_INPUT = "input"
TYPE_EDIT_TEXT = "edit_text"
TYPE_DIVIDER = "divider"
TYPE_CUSTOM = "custom"
