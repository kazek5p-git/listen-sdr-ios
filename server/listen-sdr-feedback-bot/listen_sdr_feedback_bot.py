#!/usr/bin/env python3
import json
import logging
import os
import urllib.parse
import urllib.request
from json import JSONDecodeError
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from uuid import uuid4


BOT_TOKEN = os.environ["LISTEN_SDR_BOT_TOKEN"].strip()
OWNER_ID = int(os.environ["LISTEN_SDR_OWNER_ID"].strip())
RAW_RECIPIENT_IDS = os.environ.get("LISTEN_SDR_RECIPIENT_IDS", "").strip()
BIND_HOST = os.environ.get("LISTEN_SDR_BIND_HOST", "127.0.0.1").strip() or "127.0.0.1"
BIND_PORT = int(os.environ.get("LISTEN_SDR_PORT", "18787").strip())
BOT_BASE_URL = f"https://api.telegram.org/bot{BOT_TOKEN}"
HTTP_TIMEOUT = 20
TELEGRAM_TEXT_LIMIT = 3900
TELEGRAM_CAPTION_LIMIT = 900

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


def parse_telegram_response(response):
    body = response.read()
    if response.status != 200:
        raise RuntimeError(f"Telegram API returned HTTP {response.status}")
    result = json.loads(body.decode("utf-8"))
    if not result.get("ok"):
        raise RuntimeError(f"Telegram API rejected request: {result}")
    return result["result"]


def telegram_request(method: str, payload: dict):
    data = urllib.parse.urlencode(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{BOT_BASE_URL}/{method}",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded; charset=utf-8"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
        return parse_telegram_response(response)


def telegram_multipart_request(
    method: str,
    fields: dict[str, str],
    *,
    file_field_name: str,
    filename: str,
    file_bytes: bytes,
    content_type: str,
):
    boundary = f"----ListenSDRBoundary{uuid4().hex}"
    body = bytearray()

    for key, value in fields.items():
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(
            f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode("utf-8")
        )
        body.extend(str(value).encode("utf-8"))
        body.extend(b"\r\n")

    body.extend(f"--{boundary}\r\n".encode("utf-8"))
    body.extend(
        (
            f'Content-Disposition: form-data; name="{file_field_name}"; '
            f'filename="{filename}"\r\n'
        ).encode("utf-8")
    )
    body.extend(f"Content-Type: {content_type}\r\n\r\n".encode("utf-8"))
    body.extend(file_bytes)
    body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode("utf-8"))

    request = urllib.request.Request(
        f"{BOT_BASE_URL}/{method}",
        data=bytes(body),
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
        return parse_telegram_response(response)


def send_message(chat_id: int, text: str):
    telegram_request(
        "sendMessage",
        {
            "chat_id": str(chat_id),
            "text": text,
            "disable_web_page_preview": "true",
        },
    )


def build_feedback_document_caption(text: str) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return "Listen SDR"

    caption_lines = [lines[0]]
    if len(lines) > 1:
        caption_lines.append(lines[1])
    if len(lines) > 4:
        caption_lines.append(lines[4])

    caption = "\n".join(caption_lines).strip()
    return caption[:TELEGRAM_CAPTION_LIMIT]


def build_feedback_document_filename(text: str) -> str:
    lowered = text.lower()
    feedback_type = "suggestion" if "typ: sugestia" in lowered else "bug"
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    return f"listen-sdr-{feedback_type}-{timestamp}.txt"


def send_feedback_document(chat_id: int, text: str):
    normalized = text.strip()
    telegram_multipart_request(
        "sendDocument",
        {
            "chat_id": str(chat_id),
            "caption": build_feedback_document_caption(normalized),
            "disable_content_type_detection": "true",
        },
        file_field_name="document",
        filename=build_feedback_document_filename(normalized),
        file_bytes=normalized.encode("utf-8"),
        content_type="text/plain; charset=utf-8",
    )


def send_feedback_to_recipients(text: str) -> tuple[list[int], list[dict[str, str]]]:
    normalized = text.strip()
    use_document = len(normalized) > TELEGRAM_TEXT_LIMIT
    delivered: list[int] = []
    failed: list[dict[str, str]] = []
    for recipient_id in RECIPIENT_IDS:
        try:
            if use_document:
                send_feedback_document(recipient_id, normalized)
            else:
                send_message(recipient_id, normalized)
            delivered.append(recipient_id)
        except Exception as exc:  # noqa: BLE001
            logging.exception("Unable to send feedback to recipient %s: %s", recipient_id, exc)
            failed.append(
                {
                    "recipient": str(recipient_id),
                    "error": str(exc),
                }
            )
    return delivered, failed


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
    type_label = "B\u0142\u0105d" if kind == "bug" else "Sugestia"
    message_label = "Tre\u015b\u0107 zg\u0142oszenia" if kind == "bug" else "Tre\u015b\u0107 sugestii"
    lines = [
        "Nowe zg\u0142oszenie Listen SDR",
        f"Typ: {type_label}",
        f"{message_label}:",
        message.strip(),
        "",
        f"Nadawca: {sender_name}",
        f"\u0179r\u00f3d\u0142o: {source}",
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
        session = extra.get("session")
        audio_output = extra.get("audioOutput")
        audio_diagnostics = extra.get("audioDiagnostics")
        audio_log_excerpt = extra.get("audioLogExcerpt")
        receiver = extra.get("receiver")
        diagnostics_text = extra.get("diagnosticsText")

        if app_name or app_version or build_number:
            version_parts = [part for part in [app_name, app_version] if part]
            version_text = " ".join(version_parts).strip()
            if build_number:
                version_text = f"{version_text} (build {build_number})".strip()
            lines.append(f"Aplikacja: {version_text}".strip())
        if locale_identifier:
            lines.append(f"J\u0119zyk/system locale: {locale_identifier}")
        if system_version:
            lines.append(f"System: {system_version}")
        if device_model:
            lines.append(f"Urz\u0105dzenie: {device_model}")
        if voice_over is not None:
            lines.append(f"VoiceOver: {'Tak' if voice_over else 'Nie'}")

        if isinstance(session, dict):
            if session.get("state"):
                lines.append(f"Stan sesji: {session['state']}")
            if session.get("statusText"):
                lines.append(f"Status sesji: {session['statusText']}")
            if session.get("backendStatusText"):
                lines.append(f"Status backendu: {session['backendStatusText']}")
            if session.get("lastError"):
                lines.append(f"Ostatni b\u0142\u0105d: {session['lastError']}")
            if session.get("audioMuted") is not None:
                lines.append(f"Wyciszenie audio: {'Tak' if session['audioMuted'] else 'Nie'}")
            if session.get("audioVolumePercent") is not None:
                lines.append(f"G\u0142o\u015bno\u015b\u0107 audio: {session['audioVolumePercent']}%")

        if isinstance(audio_output, dict):
            queued_duration = audio_output.get("queuedDurationSeconds")
            queued_duration_text = ""
            if queued_duration is not None:
                queued_duration_text = f" queued_s={float(queued_duration):.2f}"
            lines.append(
                "Audio wyj\u015bciowe: "
                f"running={audio_output.get('engineRunning')} "
                f"queued={audio_output.get('queuedBuffers')} "
                f"{queued_duration_text}"
                f"session={audio_output.get('sessionConfigured')} "
                f"out={audio_output.get('outputSampleRateHz')}Hz"
            )
            if audio_output.get("lastInputSampleRateHz") is not None:
                lines.append(f"Ostatni input audio: {audio_output['lastInputSampleRateHz']} Hz")
            if audio_output.get("secondsSinceLastEnqueue") is not None:
                lines.append(
                    f"Ostatni enqueue audio: {audio_output['secondsSinceLastEnqueue']:.2f} s temu"
                )
            if audio_output.get("lastStartError"):
                lines.append(f"Ostatni b\u0142\u0105d startu audio: {audio_output['lastStartError']}")

        if isinstance(audio_diagnostics, dict):
            connected_duration = audio_diagnostics.get("connectedDurationSeconds")
            reconnect_attempts = audio_diagnostics.get("automaticReconnectAttempts")
            reconnect_successes = audio_diagnostics.get("automaticReconnectSuccesses")
            if connected_duration is not None:
                lines.append(f"Czas bie\u017c\u0105cej sesji: {connected_duration:.1f} s")
            if reconnect_attempts is not None or reconnect_successes is not None:
                lines.append(
                    "Automatyczne reconnecty: "
                    f"pr\u00f3by={reconnect_attempts if reconnect_attempts is not None else '-'} "
                    f"sukcesy={reconnect_successes if reconnect_successes is not None else '-'}"
                )

            shared_audio = audio_diagnostics.get("sharedAudio")
            if isinstance(shared_audio, dict):
                lines.append(
                    "Bufory shared audio: "
                    f"pr\u00f3bki={shared_audio.get('sampleCount', '-')} "
                    f"max_bufory={shared_audio.get('peakQueuedBuffers', '-')} "
                    f"max_enqueue_gap={float(shared_audio.get('peakSecondsSinceLastEnqueue', 0)):.2f}s"
                )

            fmdx_audio = audio_diagnostics.get("fmdxAudio")
            if isinstance(fmdx_audio, dict):
                current_quality = fmdx_audio.get("currentQualityScore")
                current_quality_level = fmdx_audio.get("currentQualityLevel")
                quality_suffix = ""
                if current_quality is not None:
                    quality_suffix = f" jako\u015b\u0107={current_quality}"
                    if current_quality_level:
                        quality_suffix += f" ({current_quality_level})"
                lines.append(
                    "Bufory FM-DX: "
                    f"pr\u00f3bki={fmdx_audio.get('sampleCount', '-')} "
                    f"start={fmdx_audio.get('queueStarted')} "
                    f"teraz={float(fmdx_audio.get('currentQueuedDurationSeconds', 0)):.2f}s/"
                    f"{fmdx_audio.get('currentQueuedBuffers', '-')}buf "
                    f"gap={float(fmdx_audio.get('currentOutputGapSeconds', 0)):.2f}s "
                    f"max={float(fmdx_audio.get('peakQueuedDurationSeconds', 0)):.2f}s/"
                    f"{fmdx_audio.get('peakQueuedBuffers', '-')}buf "
                    f"max_gap={float(fmdx_audio.get('peakOutputGapSeconds', 0)):.2f}s "
                    f"trimy={fmdx_audio.get('latencyTrimEvents', '-')}"
                    f"{quality_suffix}"
                )
                if fmdx_audio.get("currentLatencyTrimAgeSeconds") is not None:
                    lines.append(
                        f"Ostatni trim FM-DX: {float(fmdx_audio['currentLatencyTrimAgeSeconds']):.2f} s temu"
                    )

        if audio_log_excerpt:
            lines.append("")
            lines.append("Skrót logów audio:")
            lines.append(str(audio_log_excerpt).strip())

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
                lines.append(f"Cz\u0119stotliwo\u015b\u0107: {receiver_frequency} Hz")
            if receiver_mode:
                lines.append(f"Tryb: {receiver_mode}")

        if diagnostics_text:
            lines.append("")
            lines.append("Diagnostyka:")
            lines.append(str(diagnostics_text).strip())
        return "\n".join(lines)

    return "\n".join(lines)


class FeedbackHTTPRequestHandler(BaseHTTPRequestHandler):
    server_version = "ListenSDRFeedbackBot/1.2"

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
            raw_body = self.rfile.read(length)
            payload = json.loads(raw_body.decode("utf-8-sig"))
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
            delivered, failed = send_feedback_to_recipients(formatted)
            if not delivered:
                self.respond_json(
                    502,
                    {
                        "ok": False,
                        "error": "Unable to deliver feedback to Telegram recipients",
                    },
                )
                return

            response_payload: dict[str, object] = {"ok": True}
            if failed:
                logging.warning(
                    "Feedback delivered only partially: delivered=%s failed=%s",
                    delivered,
                    failed,
                )
                response_payload["partial"] = True
                response_payload["failedRecipients"] = [
                    failure["recipient"] for failure in failed
                ]

            self.respond_json(200, response_payload)
        except JSONDecodeError as exc:
            logging.warning("Feedback HTTP request rejected: invalid JSON (%s)", exc)
            self.respond_json(400, {"ok": False, "error": "Invalid JSON payload"})
        except Exception as exc:  # noqa: BLE001
            logging.exception("Feedback HTTP request failed: %s", exc)
            self.respond_json(500, {"ok": False, "error": "Internal server error"})

    def respond_json(self, status: int, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            logging.warning("Client disconnected before response body was written")


def main():
    logging.info("Starting Listen SDR feedback relay on %s:%s", BIND_HOST, BIND_PORT)
    server = ThreadingHTTPServer((BIND_HOST, BIND_PORT), FeedbackHTTPRequestHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
