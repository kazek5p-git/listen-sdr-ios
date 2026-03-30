import json
import os
import re
import shutil
import sys
import time
from pathlib import Path

from pywinauto import Application
from pywinauto.keyboard import send_keys


APP_TITLE = "TweeseCake V0.18.0"
DEFAULT_CHAT_NAME = "listen sdr report system"
DEFAULT_OUTPUT_ROOT = Path(r"C:\Users\Kazek\Desktop\iOS\ListenSDR\Reports\Telegram")
DEFAULT_TWEESECAKE_DOCS = Path(
    r"C:\Users\Kazek\AppData\Roaming\TweeseCake\Telegram-1\files\documents"
)
ATTACHMENT_PATTERN = re.compile(r"listen-sdr-(?:bug|suggestion)-\d{8}-\d{6}\.txt", re.IGNORECASE)


def listbox_item_height(listbox):
    rect = listbox.rectangle()
    count = max(1, listbox.item_count())
    return max(1, int((rect.bottom - rect.top) / count))


def click_listbox_item(listbox, index):
    item_height = listbox_item_height(listbox)
    y = item_height * index + item_height // 2
    listbox.click_input(coords=(20, y))


def connect_main_window():
    app = Application(backend="win32").connect(path="tweesecake.exe")
    main = None
    for window in app.windows():
        if window.window_text() == APP_TITLE:
            main = window
            break
    if main is None:
        raise RuntimeError("TweeseCake main window not found.")
    if main.is_minimized():
        main.restore()
    main.set_focus()
    time.sleep(0.3)
    return app, main


def close_auxiliary_windows(app):
    for window in app.windows():
        try:
            title = window.window_text()
        except Exception:  # noqa: BLE001
            continue
        if title.startswith("Message from ") or title == "Select where to save the file":
            try:
                window.close()
                time.sleep(0.05)
            except Exception:  # noqa: BLE001
                pass


def get_children(main):
    children = main.children()
    listboxes = [control for control in children if control.class_name() == "ListBox"]
    listviews = [control for control in children if control.class_name() == "SysListView32"]
    if len(listboxes) < 2 or not listviews:
        raise RuntimeError("TweeseCake controls not found.")
    return listboxes[0], listboxes[1], listviews[0]


def get_listview_items(listview):
    items = []
    for index in range(listview.item_count()):
        try:
            text = listview.get_item(index).text()
        except Exception as exc:  # noqa: BLE001
            text = f"<ERR {exc}>"
        items.append({"index": index, "text": text})
    return items


def select_telegram_report_timeline(main, chat_name):
    sessions, timelines, _ = get_children(main)

    session_texts = sessions.texts()[1:]
    telegram_index = None
    for index, text in enumerate(session_texts):
        if text.startswith("Telegram:"):
            telegram_index = index
            break
    if telegram_index is None:
        raise RuntimeError("TweeseCake Telegram session not found.")

    click_listbox_item(sessions, telegram_index)
    time.sleep(1.0)

    _, timelines, _ = get_children(main)
    timeline_texts = timelines.texts()[1:]
    chat_index = None
    for index, text in enumerate(timeline_texts):
        if text.strip().lower() == chat_name.lower():
            chat_index = index
            break
    if chat_index is None:
        raise RuntimeError(f"TweeseCake timeline '{chat_name}' not found.")

    click_listbox_item(timelines, chat_index)
    time.sleep(1.0)

    _, _, listview = get_children(main)
    return listview


def find_save_dialog(app):
    for window in app.windows():
        try:
            if window.window_text() == "Select where to save the file":
                return window
        except Exception:  # noqa: BLE001
            continue
    return None


def save_buffer_to_path(app, destination_path):
    dialog = find_save_dialog(app)
    if dialog is None:
        raise RuntimeError("TweeseCake save dialog not found.")

    dialog.set_focus()
    time.sleep(0.2)
    edits = [control for control in dialog.children() if control.class_name() == "Edit"]
    if not edits:
        raise RuntimeError("TweeseCake save dialog edit field not found.")

    edits[0].set_edit_text(str(destination_path))
    time.sleep(0.2)
    send_keys("{ENTER}")
    time.sleep(1.2)


def close_save_dialog(app):
    dialog = find_save_dialog(app)
    if dialog is None:
        return False
    dialog.close()
    time.sleep(0.2)
    return True


def list_matching_attachments(documents_dir):
    return {
        path.name: path.stat().st_mtime
        for path in documents_dir.iterdir()
        if path.is_file() and ATTACHMENT_PATTERN.match(path.name)
    }


def extract_attachment_name(item_text):
    match = ATTACHMENT_PATTERN.search(item_text)
    if match is None:
        return None
    return match.group(0)


def copy_attachment_if_present(documents_dir, output_root, file_name):
    if not file_name:
        return []
    source_path = documents_dir / file_name
    if not source_path.exists():
        return []
    target_path = output_root / file_name
    source_stat = source_path.stat()
    if target_path.exists():
        target_stat = target_path.stat()
        if (
            target_stat.st_size == source_stat.st_size
            and int(target_stat.st_mtime) == int(source_stat.st_mtime)
        ):
            return []
    shutil.copy2(source_path, target_path)
    return [str(target_path)]


def download_attachment_for_item(app, main, listview, item_index, item_text, documents_dir, output_root):
    attachment_name = extract_attachment_name(item_text)
    copied_paths = copy_attachment_if_present(documents_dir, output_root, attachment_name)
    if copied_paths:
        return copied_paths

    before = list_matching_attachments(documents_dir)

    listview.select(item_index)
    time.sleep(0.2)
    main.set_focus()
    time.sleep(0.1)
    main.type_keys("+{ENTER}")
    time.sleep(1.5)
    close_save_dialog(app)
    time.sleep(0.4)

    after = list_matching_attachments(documents_dir)
    downloaded = copied_paths[:]
    for file_name, modified_at in after.items():
        if file_name not in before or before[file_name] != modified_at:
            source_path = documents_dir / file_name
            target_path = output_root / file_name
            shutil.copy2(source_path, target_path)
            downloaded.append(str(target_path))
    return downloaded


def export_buffer(app, main, output_root):
    output_root.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y%m%d-%H%M%S")
    export_path = output_root / f"listen-sdr-report-system-buffer-{timestamp}.txt"

    main.set_focus()
    time.sleep(0.1)
    main.type_keys("^+e")
    time.sleep(1.2)
    save_buffer_to_path(app, export_path)
    return export_path


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

    export_buffer_enabled = False
    if len(sys.argv) > 4 and sys.argv[4].strip().lower() in {"1", "true", "yes", "y"}:
        export_buffer_enabled = True

    output_root.mkdir(parents=True, exist_ok=True)

    app, main_window = connect_main_window()
    close_auxiliary_windows(app)
    history_list = select_telegram_report_timeline(main_window, chat_name)
    items = get_listview_items(history_list)

    downloaded_files = []
    for item in items:
        text = item["text"]
        if text.startswith(f"{chat_name}: File: Nowe zgłoszenie Listen SDR"):
            downloaded_files.extend(
                download_attachment_for_item(
                    app,
                    main_window,
                    history_list,
                    item["index"],
                    text,
                    documents_dir,
                    output_root,
                )
            )

    export_path = None
    export_warning = None
    if export_buffer_enabled:
        try:
            export_path = export_buffer(app, main_window, output_root)
        except Exception as exc:  # noqa: BLE001
            export_warning = str(exc)

    print(
        json.dumps(
            {
                "ok": True,
                "chatName": chat_name,
                "items": items,
                "downloadedFiles": downloaded_files,
                "exportPath": str(export_path) if export_path else None,
                "warning": export_warning,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
