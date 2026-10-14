"""Мост в нативный _etg-модуль с защитой от падений.""" ""

import json

try:
    import _etg  # нативный C-модуль, регистрируется Swift-стороной
except ImportError:  # плагин запустили вне хоста (тесты) — мокаем
    class _FakeEtg:
        @staticmethod
        def call(command, payload_json):
            return json.dumps({"ok": False, "error": "no host"})

    _etg = _FakeEtg()


def bridge_call(command, payload=None):
    """Единая точка вызова хоста. Возвращает dict (JSON-ответ)."""
    if payload is None:
        payload = {}
    raw = _etg.call(command, json.dumps(payload))
    if raw is None:
        return {}
    try:
        return json.loads(raw)
    except Exception:
        return {"ok": False, "error": "bad json from host"}


def log(plugin_id, message):
    bridge_call("log", {"plugin_id": plugin_id, "message": str(message)})
