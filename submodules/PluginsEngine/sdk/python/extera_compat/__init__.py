# extera_compat — слой совместимости exteraGram Plugin SDK для iOS.
# Делает вид, что плагин живёт в exteraGram-Android: тот же BasePlugin,
# те же hook_method/add_menu_item/get_setting. Под капотом — мост _etg
# в Swift-сторону Telegram-ETG.

from .base_plugin import BasePlugin  # noqa: F401
from . import client_utils  # noqa: F401
from . import hook_utils  # noqa: F401
from . import plugin_settings  # noqa: F401

__sdk_version__ = "1.4.5.7"
