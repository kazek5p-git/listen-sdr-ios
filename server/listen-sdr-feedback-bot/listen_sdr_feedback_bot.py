#!/usr/bin/env python3
import json
import logging
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


BOT_TOKEN = os.environ["LISTEN_SDR_BOT_TOKEN"].strip()
OWNER_ID = int(os.environ["LISTEN_SDR_OWNER_ID"].strip())
BIND_HOST = os.environ.get("LISTEN_SDR_BIND_HOST", "0.0.0.0").strip() or "0.0.0.0"
BIND_PORT = int(os.environ.get("LISTEN_SDR_PORT", "18787").strip())
BOT_BASE_URL = f"https://api.telegram.org/bot{BOT_TOKEN}"
HTTP_TIMEOUT = 20
USER_STATES = {}

MENU_BUG = "Zgłoś błąd"
MENU_SUGGESTION = "Napisz sugestię"
MENU_CANCEL = "Anuluj"

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s %(message)s",
)


def telegram_request(method: str, payload: dict):
    data = urllib.parse.urlencode(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{BOT_BASE_URL}/{method}",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded; charset=utf-8"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
        body = response.read()
        if response.status != 200:
            raise RuntimeError(f"Telegram API returned HTTP {response.status}")
        result = json.loads(body.decode("utf-8"))
        if not result.get("ok"):
            raise RuntimeError(f"Telegram API rejected request: {result}")
        return result["result"]


def send_message(chat_id: int, text: str, include_menu: bool = False):
    payload = {
        "chat_id": str(chat_id),
        "text": text,
        "disable_web_page_preview": "true",
    }
    if include_menu:
        payload["reply_markup"] = json.dumps(
            {
                "keyboard": [
                    [{"text": MENU_BUG}],
                    [{"text": MENU_SUGGESTION}],
                    [{"text": MENU_CANCEL}],
                ],
                "resize_keyboard": True,
                "one_time_keyboard": False,
            }
        )
    telegram_request("sendMessage", payload)


def normalize_message_text(text: str) -> str:
    return "\n".join(line.rstrip() for line in text.strip().splitlines() if line.strip())


def format_user_feedback(
    *,
    kind: str,
    sender_name: str,
    message: str,
    source: str,
    submitted_at: str,
    chat_id: int | None = None,
    username: str | None = None,
    extra: dict | None = None,
) -> str:
    type_label = "Błąd" if kind == "bug" else "Sugestia"
    lines = [
        "Nowe zgłoszenie Listen SDR",
        f"Typ: {type_label}",
        f"Nadawca: {sender_name}",
        f"Źródło: {source}",
        f"Czas: {submitted_at}",
    ]

    if chat_id is not None:
      lines.append(f"Telegram user id: {chat_id}")
    if username:
      lines.append(f"Telegram username: @{username}")

    if extra:
        app_name = extra.get("appName")
        app_version = extra.get("appVersion")
        build_number = extra.get("buildNumber")
        locale_identifier = extra.get("localeIdentifier")
        system_version = extra.get("systemVersion")
        device_model = extra.get("deviceModel")
        voice_over = extra.get("voiceOverEnabled")
        receiver = extra.get("receiver")

        if app_name or app_version or build_number:
            version_parts = [part for part in [app_name, app_version] if part]
            version_text = " ".join(version_parts).strip()
            if build_number:
                version_text = f"{version_text} (build {build_number})".strip()
            lines.append(f"Aplikacja: {version_text}".strip())
        if locale_identifier:
            lines.append(f"Język/system locale: {locale_identifier}")
        if system_version:
            lines.append(f"System: {system_version}")
        if device_model:
            lines.append(f"Urządzenie: {device_model}")
        if voice_over is not None:
            lines.append(f"VoiceOver: {'Tak' if voice_over else 'Nie'}")
        if isinstance(receiver, dict):
            receiver_name = receiver.get("name")
            receiver_backend = receiver.get("backend")
            receiver_endpoint = receiver.get("endpoint")
            receiver_frequency = receiver.get("frequencyHz")
            receiver_mode = receiver.get("mode")
            if receiver_name:
                lines.append(f"Odbiornik: {receiver_name}")
            if receiver_backend:
                lines.append(f"Typ odbiornika: {receiver_backend}")
            if receiver_endpoint:
                lines.append(f"Adres odbiornika: {receiver_endpoint}")
            if receiver_frequency:
                lines.append(f"Częstotliwość: {receiver_frequency} Hz")
            if receiver_mode:
                lines.append(f"Tryb: {receiver_mode}")

    lines.append("")
    lines.append(message)
    return "\n".join(lines)


def reset_user_state(chat_id: int):
    USER_STATES.pop(chat_id, None)


def begin_flow(chat_id: int, kind: str):
    USER_STATES[chat_id] = {"kind": kind, "step": "sender"}
    send_message(
        chat_id,
        "Podaj imię lub nick, który ma być dołączony do zgłoszenia.",
        include_menu=True,
    )


def handle_feedback_message(chat_id: int, message_text: str, username: str | None):
    state = USER_STATES.get(chat_id)
    if not state:
        return

    text = normalize_message_text(message_text)
    if not text:
        send_message(chat_id, "Wiadomość nie może być pusta.", include_menu=True)
        return

    if state["step"] == "sender":
        state["sender_name"] = text
        state["step"] = "message"
        send_message(chat_id, "Podaj treść zgłoszenia lub sugestii.", include_menu=True)
        return

    if state["step"] == "message":
        kind = state["kind"]
        sender_name = state["sender_name"]
        submitted_at = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
        payload = format_user_feedback(
            kind=kind,
            sender_name=sender_name,
            message=text,
            source="telegram",
            submitted_at=submitted_at,
            chat_id=chat_id,
            username=username,
        )
        send_message(OWNER_ID, payload, include_menu=False)
        send_message(chat_id, "Dziękuję. Zgłoszenie zostało przekazane.", include_menu=True)
        reset_user_state(chat_id)


def handle_telegram_text(chat_id: int, text: str, username: str | None):
    normalized = text.strip()

    if normalized == "/start":
        reset_user_state(chat_id)
        send_message(
            chat_id,
            "Wybierz, co chcesz zrobić.",
            include_menu=True,
        )
        return

    if normalized == "/cancel" or normalized == MENU_CANCEL:
        reset_user_state(chat_id)
        send_message(chat_id, "Anulowano bieżące zgłoszenie.", include_menu=True)
        return

    if normalized == MENU_BUG:
        begin_flow(chat_id, "bug")
        return

    if normalized == MENU_SUGGESTION:
        begin_flow(chat_id, "suggestion")
        return

    if chat_id in USER_STATES:
        handle_feedback_message(chat_id, normalized, username)
        return

    send_message(
        chat_id,
        "Nie rozumiem tej wiadomości. Użyj przycisków poniżej albo polecenia /start.",
        include_menu=True,
    )


def poll_updates():
    offset = None
    while True:
        try:
            payload = {"timeout": "30"}
            if offset is not None:
                payload["offset"] = str(offset)

            result = telegram_request("getUpdates", payload)
            for update in result:
                offset = update["update_id"] + 1
                message = update.get("message")
                if not message:
                    continue
                chat = message.get("chat", {})
                text = message.get("text")
                if not text:
                    continue
                chat_id = chat.get("id")
                username = chat.get("username")
                if chat_id is None:
                    continue
                handle_telegram_text(int(chat_id), text, username)
        except Exception as exc:  # noqa: BLE001
            logging.exception("Telegram polling failed: %s", exc)
            time.sleep(5)


class FeedbackHTTPRequestHandler(BaseHTTPRequestHandler):
    server_version = "ListenSDRFeedbackBot/1.0"

    def log_message(self, format, *args):  # noqa: A003
        logging.info("HTTP %s - %s", self.address_string(), format % args)

    def do_GET(self):  # noqa: N802
        if self.path == "/healthz":
            self.respond_json(200, {"ok": True, "service": "listen-sdr-feedback-bot"})
            return
        self.respond_json(404, {"ok": False, "error": "Not found"})

    def do_POST(self):  # noqa: N802
        if self.path != "/api/feedback":
            self.respond_json(404, {"ok": False, "error": "Not found"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            kind = str(payload.get("kind", "")).strip().lower()
            sender_name = normalize_message_text(str(payload.get("senderName", "")).strip())
            message = normalize_message_text(str(payload.get("message", "")).strip())
            source = str(payload.get("source", "unknown")).strip() or "unknown"
            submitted_at = str(payload.get("submittedAt", "")).strip() or datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")

            if kind not in {"bug", "suggestion"}:
                self.respond_json(400, {"ok": False, "error": "Invalid kind"})
                return
            if not sender_name:
                self.respond_json(400, {"ok": False, "error": "Sender name is required"})
                return
            if not message:
                self.respond_json(400, {"ok": False, "error": "Message is required"})
                return

            formatted = format_user_feedback(
                kind=kind,
                sender_name=sender_name,
                message=message,
                source=source,
                submitted_at=submitted_at,
                extra=payload,
            )
            send_message(OWNER_ID, formatted, include_menu=False)
            self.respond_json(200, {"ok": True})
        except Exception as exc:  # noqa: BLE001
            logging.exception("Feedback HTTP request failed: %s", exc)
            self.respond_json(500, {"ok": False, "error": "Internal server error"})

    def respond_json(self, status: int, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def run_http_server():
    server = ThreadingHTTPServer((BIND_HOST, BIND_PORT), FeedbackHTTPRequestHandler)
    logging.info("HTTP feedback endpoint listening on %s:%s", BIND_HOST, BIND_PORT)
    server.serve_forever()


def main():
    logging.info("Starting Listen SDR feedback bot")
    http_thread = threading.Thread(target=run_http_server, daemon=True)
    http_thread.start()
    poll_updates()


if __name__ == "__main__":
    main()
