#!/usr/bin/env python3
import json
import logging
import os
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


BOT_TOKEN = os.environ["LISTEN_SDR_BOT_TOKEN"].strip()
OWNER_ID = int(os.environ["LISTEN_SDR_OWNER_ID"].strip())
RAW_RECIPIENT_IDS = os.environ.get("LISTEN_SDR_RECIPIENT_IDS", "").strip()
BIND_HOST = os.environ.get("LISTEN_SDR_BIND_HOST", "127.0.0.1").strip() or "127.0.0.1"
BIND_PORT = int(os.environ.get("LISTEN_SDR_PORT", "18787").strip())
BOT_BASE_URL = f"https://api.telegram.org/bot{BOT_TOKEN}"
HTTP_TIMEOUT = 20

if RAW_RECIPIENT_IDS:
    RECIPIENT_IDS = [
        int(value.strip())
        for value in RAW_RECIPIENT_IDS.split(",")
        if value.strip()
    ]
else:
    RECIPIENT_IDS = [OWNER_ID]

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


def send_message(chat_id: int, text: str):
    telegram_request(
        "sendMessage",
        {
            "chat_id": str(chat_id),
            "text": text,
            "disable_web_page_preview": "true",
        },
    )


def send_feedback_to_recipients(text: str):
    for recipient_id in RECIPIENT_IDS:
        send_message(recipient_id, text)


def normalize_message_text(text: str) -> str:
    return "\n".join(line.rstrip() for line in text.strip().splitlines() if line.strip())


def format_feedback(
    *,
    kind: str,
    sender_name: str,
    message: str,
    source: str,
    submitted_at: str,
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


class FeedbackHTTPRequestHandler(BaseHTTPRequestHandler):
    server_version = "ListenSDRFeedbackBot/1.1"

    def log_message(self, format, *args):  # noqa: A003
        logging.info("HTTP %s - %s", self.address_string(), format % args)

    def do_GET(self):  # noqa: N802
        if self.path == "/healthz":
            self.respond_json(
                200,
                {
                    "ok": True,
                    "service": "listen-sdr-feedback-bot",
                    "recipients": RECIPIENT_IDS,
                },
            )
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
            submitted_at = str(payload.get("submittedAt", "")).strip() or datetime.now(
                timezone.utc
            ).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")

            if kind not in {"bug", "suggestion"}:
                self.respond_json(400, {"ok": False, "error": "Invalid kind"})
                return
            if not sender_name:
                self.respond_json(400, {"ok": False, "error": "Sender name is required"})
                return
            if not message:
                self.respond_json(400, {"ok": False, "error": "Message is required"})
                return

            formatted = format_feedback(
                kind=kind,
                sender_name=sender_name,
                message=message,
                source=source,
                submitted_at=submitted_at,
                extra=payload,
            )
            send_feedback_to_recipients(formatted)
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


def main():
    logging.info("Starting Listen SDR feedback relay on %s:%s", BIND_HOST, BIND_PORT)
    server = ThreadingHTTPServer((BIND_HOST, BIND_PORT), FeedbackHTTPRequestHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
