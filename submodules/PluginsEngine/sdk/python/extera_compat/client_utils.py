"""client_utils — порт extera SDK client_utils для iOS-хоста.

На Android эти функции дергали Java-объекты Telegram (ConnectionsManager и пр.).
Здесь — мост _etg → Swift → TelegramCore. Обработчики регистрируются
приложением при старте (ETGBridgeDispatcher.register).
"""

from ._bridge import bridge_call


def get_client(account=0):
    """Возвращает лёгкий прокси клиента (все вызовы — через bridge)."""
    return _ClientProxy(account)


def get_account_instance(account=0):
    return {"account": account}


class _ClientProxy:
    def __init__(self, account=0):
        self.account = account

    def send_message(self, peer_id, text, **kwargs):
        payload = {"account": self.account, "peer_id": peer_id, "text": text}
        payload.update(kwargs)
        return bridge_call("send_message", payload)

    def edit_message(self, peer_id, message_id, text, **kwargs):
        payload = {"account": self.account, "peer_id": peer_id,
                   "message_id": message_id, "text": text}
        payload.update(kwargs)
        return bridge_call("edit_message", payload)

    def delete_messages(self, peer_id, message_ids):
        return bridge_call("delete_messages", {
            "account": self.account, "peer_id": peer_id, "message_ids": message_ids,
        })

    def forward_messages(self, from_peer_id, to_peer_id, message_ids):
        return bridge_call("forward_messages", {
            "account": self.account, "from_peer_id": from_peer_id,
            "to_peer_id": to_peer_id, "message_ids": message_ids,
        })

    def send_file(self, peer_id, path, caption="", **kwargs):
        payload = {"account": self.account, "peer_id": peer_id,
                   "path": path, "caption": caption}
        payload.update(kwargs)
        return bridge_call("send_file", payload)

    def download_media(self, message, path):
        return bridge_call("download_media", {
            "account": self.account, "message": message, "path": path,
        })

    def get_chat_members(self, peer_id):
        return bridge_call("get_chat_members", {
            "account": self.account, "peer_id": peer_id,
        })
