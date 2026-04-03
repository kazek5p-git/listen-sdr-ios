import json
import re
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path

import win32con
import win32gui
from pywinauto import Application


APP_TITLE = "TweeseCake V0.18.0"
DEFAULT_CHAT_NAME = "listen sdr report system"
DEFAULT_OUTPUT_ROOT = Path(r"C:\Users\Kazek\Desktop\iOS\ListenSDR\Reports\Telegram")
DEFAULT_TWEESECAKE_DOCS = Path(
    r"C:\Users\Kazek\AppData\Roaming\TweeseCake\Telegram-1\files\documents"
)
ATTACHMENT_PATTERN = re.compile(
    r"listen-sdr-(?P<kind>bug|suggestion)-(?P<stamp>\d{8}-\d{6})\.txt",
    re.IGNORECASE,
)
TYPE_PATTERN = re.compile(r"Typ:\s*(?P<type>[^\r\n]+)", re.IGNORECASE)
SENDER_PATTERN = re.compile(r"Nadawca:\s*(?P<sender>.+?)(?:,\s*listen-sdr-|$)", re.IGNORECASE)
TARGET_CHAT_PREVIEW = "nowe zgłoszenie listen sdr"
SW_SHOWNOACTIVATE = 4
SW_HIDE = 0
SWP_NOACTIVATE = 0x0010
SWP_NOSIZE = 0x0001
SWP_NOZORDER = 0x0004
DOWNLOAD_WAIT_SECONDS = 8.0


def connect_main_window():
    app = Application(backend="win32").connect(path="tweesecake.exe")
    main = None
    for window in app.windows():
        if window.window_text() == APP_TITLE:
            main = window
            break
    if main is None:
        raise RuntimeError("TweeseCake main window not found.")
    return app, main


def get_children(main):
    children = main.children()
    listboxes = [control for control in children if control.class_name() == "ListBox"]
    listviews = [control for control in children if control.class_name() == "SysListView32"]
    if len(listboxes) < 2 or not listviews:
        raise RuntimeError("TweeseCake controls not found.")
    return listboxes[0], listboxes[1], listviews[0]


def capture_window_state(main):
    left, top, right, bottom = win32gui.GetWindowRect(main.handle)
    return {
        "visible": bool(win32gui.IsWindowVisible(main.handle)),
        "rect": (left, top, right, bottom),
    }


def prepare_window(main):
    win32gui.SetWindowPos(
        main.handle,
        0,
        -32000,
        -32000,
        0,
        0,
        SWP_NOACTIVATE | SWP_NOSIZE | SWP_NOZORDER,
    )
    win32gui.ShowWindow(main.handle, SW_SHOWNOACTIVATE)
    time.sleep(0.5)


def restore_window(main, state):
    left, top, _, _ = state["rect"]
    if state["visible"]:
        win32gui.SetWindowPos(
            main.handle,
            0,
            left,
            top,
            0,
            0,
            SWP_NOACTIVATE | SWP_NOSIZE | SWP_NOZORDER,
        )
        win32gui.ShowWindow(main.handle, SW_SHOWNOACTIVATE)
    else:
        win32gui.ShowWindow(main.handle, SW_HIDE)


def get_listbox_entry_text(listbox, index):
    texts = listbox.texts()[1:]
    if index is None or index < 0 or index >= len(texts):
        return None
    return texts[index]


def get_selected_index(control):
    indices = control.selected_indices()
    if not indices:
        return None
    return indices[0]


def find_listbox_index(listbox, predicate):
    texts = listbox.texts()[1:]
    for index, text in enumerate(texts):
        if predicate(text):
            return index
    return None


def select_listbox_index(listbox, index):
    listbox.select(index)
    time.sleep(0.8)


def get_listview_items(listview):
    items = []
    for index in range(listview.item_count()):
        try:
            text = listview.get_item(index).text()
        except Exception as exc:  # noqa: BLE001
            text = f"<ERR {exc}>"
        items.append({"index": index, "text": text})
    return items


def find_listview_index(listview, predicate, reverse=False):
    indices = range(listview.item_count())
    if reverse:
        indices = reversed(range(listview.item_count()))

    for index in indices:
        try:
            text = listview.get_item(index).text()
        except Exception:  # noqa: BLE001
            continue
        if predicate(text):
            return index
    return None


def select_listview_index(listview, index):
    item = listview.get_item(index)
    item.select()
    time.sleep(0.4)
    listview.set_keyboard_focus()
    time.sleep(0.2)
    return item


def send_secondary_interact(listview):
    win32gui.SendMessage(listview.handle, win32con.WM_KEYDOWN, win32con.VK_SHIFT, 0)
    win32gui.SendMessage(listview.handle, win32con.WM_KEYDOWN, win32con.VK_RETURN, 0)
    win32gui.SendMessage(listview.handle, win32con.WM_KEYUP, win32con.VK_RETURN, 0)
    win32gui.SendMessage(listview.handle, win32con.WM_KEYUP, win32con.VK_SHIFT, 0)
    time.sleep(1.5)


def parse_attachment_name(text):
    match = ATTACHMENT_PATTERN.search(text)
    if match is None:
        return None
    return match.group(0)


def parse_report_type(text):
    match = TYPE_PATTERN.search(text)
    if match is None:
        return None
    return match.group("type").strip()


def parse_sender(text):
    match = SENDER_PATTERN.search(text)
    if match is None:
        return None
    return match.group("sender").strip().rstrip(",")


def parse_stamp_from_attachment(attachment_name):
    if not attachment_name:
        return None
    match = ATTACHMENT_PATTERN.match(attachment_name)
    if match is None:
        return None
    return match.group("stamp")


def attachment_timestamp(attachment_name):
    stamp = parse_stamp_from_attachment(attachment_name)
    if not stamp:
        return None
    return datetime.strptime(stamp, "%Y%m%d-%H%M%S")


def day_directory(output_root, attachment_name):
    timestamp = attachment_timestamp(attachment_name)
    if timestamp is None:
        return output_root
    return output_root / timestamp.strftime("%Y-%m-%d")


def metadata_paths_for(output_root, attachment_name):
    attachment_stem = Path(attachment_name).stem if attachment_name else "unknown"
    base_dir = day_directory(output_root, attachment_name)
    return {
        "final": base_dir / f"{attachment_stem}.json",
        "pending": base_dir / f"{attachment_stem}.pending.json",
    }


def copy_attachment_if_present(documents_dir, output_root, attachment_name):
    if not attachment_name:
        return None

    source_path = documents_dir / attachment_name
    if not source_path.exists():
        return None

    target_dir = day_directory(output_root, attachment_name)
    target_dir.mkdir(parents=True, exist_ok=True)
    target_path = target_dir / attachment_name
    source_stat = source_path.stat()
    if target_path.exists():
        target_stat = target_path.stat()
        if (
            target_stat.st_size == source_stat.st_size
            and int(target_stat.st_mtime) == int(source_stat.st_mtime)
        ):
            return {
                "path": target_path,
                "copied": False,
            }

    shutil.copy2(source_path, target_path)
    return {
        "path": target_path,
        "copied": True,
    }


def wait_for_attachment(documents_dir, attachment_name, timeout_seconds):
    if not attachment_name:
        return None

    source_path = documents_dir / attachment_name
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if source_path.exists():
            return source_path
        time.sleep(0.25)
    return None


def build_report_item(item, chat_name, output_root, documents_dir):
    text = item["text"]
    attachment_name = parse_attachment_name(text)
    if not attachment_name:
        return None

    lower_text = text.lower()
    if chat_name.lower() not in lower_text and TARGET_CHAT_PREVIEW not in lower_text:
        return None

    copied_info = copy_attachment_if_present(documents_dir, output_root, attachment_name)
    copied_path = copied_info["path"] if copied_info else None
    metadata_paths = metadata_paths_for(output_root, attachment_name)
    metadata_paths["final"].parent.mkdir(parents=True, exist_ok=True)

    is_pending = copied_path is None
    metadata_path = metadata_paths["pending"] if is_pending else metadata_paths["final"]
    stale_path = metadata_paths["final"] if is_pending else metadata_paths["pending"]
    if stale_path.exists():
        stale_path.unlink()

    entry = {
        "index": item["index"],
        "chatName": chat_name,
        "text": text,
        "attachmentName": attachment_name,
        "reportType": parse_report_type(text),
        "sender": parse_sender(text),
        "sentAt": attachment_timestamp(attachment_name).isoformat() if attachment_timestamp(attachment_name) else None,
        "metadataPath": str(metadata_path),
        "attachmentPath": str(copied_path) if copied_path else None,
        "attachmentPending": is_pending,
        "attachmentCopied": bool(copied_info and copied_info["copied"]),
    }

    metadata_path.write_text(
        json.dumps(entry, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return entry


def open_telegram_chats(main):
    sessions, timelines, _ = get_children(main)

    original = {
        "sessionIndex": get_selected_index(sessions),
        "sessionText": get_listbox_entry_text(sessions, get_selected_index(sessions)),
        "timelineIndex": get_selected_index(timelines),
        "timelineText": get_listbox_entry_text(timelines, get_selected_index(timelines)),
    }

    telegram_index = find_listbox_index(sessions, lambda text: text.startswith("Telegram:"))
    if telegram_index is None:
        raise RuntimeError("TweeseCake Telegram session not found.")
    select_listbox_index(sessions, telegram_index)

    _, timelines, _ = get_children(main)
    chats_index = find_listbox_index(timelines, lambda text: text.strip().lower() == "chats")
    if chats_index is None:
        raise RuntimeError("TweeseCake Telegram Chats timeline not found.")
    select_listbox_index(timelines, chats_index)

    _, _, listview = get_children(main)
    return listview, original


def restore_original_selection(main, original):
    sessions, timelines, _ = get_children(main)

    target_session = None
    if original["sessionText"]:
        target_session = find_listbox_index(sessions, lambda text: text == original["sessionText"])
    if target_session is None:
        target_session = original["sessionIndex"]

    if target_session is not None and target_session < sessions.item_count():
        select_listbox_index(sessions, target_session)
    else:
        return

    _, timelines, _ = get_children(main)

    target_timeline = None
    if original["timelineText"]:
        target_timeline = find_listbox_index(timelines, lambda text: text == original["timelineText"])
    if target_timeline is None:
        target_timeline = original["timelineIndex"]

    if target_timeline is not None and target_timeline < timelines.item_count():
        select_listbox_index(timelines, target_timeline)


def open_report_chat(main, chat_name):
    _, timelines, listview = get_children(main)

    existing_chat_index = find_listbox_index(timelines, lambda text: text.strip().lower() == chat_name.lower())
    if existing_chat_index is not None:
        select_listbox_index(timelines, existing_chat_index)
        _, _, listview = get_children(main)
        return main, listview

    chat_row_index = find_listview_index(
        listview,
        lambda text: chat_name.lower() in text.lower() and TARGET_CHAT_PREVIEW in text.lower(),
        reverse=True,
    )
    if chat_row_index is None:
        raise RuntimeError(f"TweeseCake chat preview for '{chat_name}' not found.")

    select_listview_index(listview, chat_row_index)
    send_secondary_interact(listview)

    _, main = connect_main_window()
    prepare_window(main)
    _, timelines, listview = get_children(main)
    chat_index = find_listbox_index(timelines, lambda text: text.strip().lower() == chat_name.lower())
    if chat_index is None:
        raise RuntimeError(f"TweeseCake chat '{chat_name}' did not open.")
    select_listbox_index(timelines, chat_index)
    _, _, listview = get_children(main)
    return main, listview


def attempt_missing_attachment_download(main, listview, chat_name, attachment_name, documents_dir):
    source_path = documents_dir / attachment_name
    if source_path.exists():
        return source_path

    message_index = find_listview_index(
        listview,
        lambda text: attachment_name.lower() in text.lower() and chat_name.lower() in text.lower(),
        reverse=True,
    )
    if message_index is None:
        return None

    select_listview_index(listview, message_index)
    send_secondary_interact(listview)
    return wait_for_attachment(documents_dir, attachment_name, DOWNLOAD_WAIT_SECONDS)


def main():
    sys.stdout.reconfigure(encoding="utf-8")

    chat_name = DEFAULT_CHAT_NAME
    if len(sys.argv) > 1 and sys.argv[1].strip():
        chat_name = sys.argv[1].strip()

    output_root = DEFAULT_OUTPUT_ROOT
    if len(sys.argv) > 2 and sys.argv[2].strip():
        output_root = Path(sys.argv[2].strip())

    documents_dir = DEFAULT_TWEESECAKE_DOCS
    if len(sys.argv) > 3 and sys.argv[3].strip():
        documents_dir = Path(sys.argv[3].strip())

    output_root.mkdir(parents=True, exist_ok=True)

    app, main_window = connect_main_window()
    window_state = capture_window_state(main_window)
    prepare_window(main_window)

    listview = None
    original = None
    report_items = []
    downloaded_files = []
    pending_attachments = []

    try:
        _, original = open_telegram_chats(main_window)
        _, main_window = connect_main_window()
        prepare_window(main_window)
        main_window, chat_listview = open_report_chat(main_window, chat_name)
        prepare_window(main_window)

        chat_items = get_listview_items(chat_listview)
        for item in chat_items:
            report_item = build_report_item(item, chat_name, output_root, documents_dir)
            if report_item is None:
                continue
            if report_item["attachmentPending"]:
                downloaded_path = attempt_missing_attachment_download(
                    main_window,
                    chat_listview,
                    chat_name,
                    report_item["attachmentName"],
                    documents_dir,
                )
                if downloaded_path is not None:
                    report_item = build_report_item(item, chat_name, output_root, documents_dir)

            report_items.append(report_item)
            if report_item["attachmentPath"] and report_item["attachmentCopied"]:
                downloaded_files.append(report_item["attachmentPath"])
            else:
                if report_item["attachmentPending"]:
                    pending_attachments.append(report_item["attachmentName"])
    finally:
        try:
            _, main_window = connect_main_window()
            prepare_window(main_window)
            if original is not None:
                restore_original_selection(main_window, original)
            restore_window(main_window, window_state)
        except Exception:  # noqa: BLE001
            pass

    print(
        json.dumps(
            {
                "ok": True,
                "chatName": chat_name,
                "items": report_items,
                "downloadedFiles": downloaded_files,
                "pendingAttachments": pending_attachments,
                "warning": None,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
