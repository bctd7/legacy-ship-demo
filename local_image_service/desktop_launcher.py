"""Small local service window. User launches it; no generation on startup."""
import ctypes
import os
from pathlib import Path
import queue
import threading

from launcher_core import Controller, LauncherError, SingleInstance
from private_config import ConfigError

TITLE = '图片生成服务 · Flash'
ERROR_TEXT = {
    'private_config_missing': '请先复制 private/api_key.example.json 为 api_key.local.json，填写 api_key 后点启动。',
    'private_config_invalid': '本地配置未填写或格式不正确；请检查 private/api_key.local.json。内容不会显示到这里。',
    'existing_service_incompatible': '8769 端口仍被旧服务占用。请在旧 PowerShell 窗口停止一次，再点启动。',
    'port_in_use': '8769 端口已被占用，未启动第二个实例。',
    'request_in_progress': '正在生成，请等待返回；关闭窗口不会取消服务商计费。',
    'result_not_available': '本次尚无可查看的图片，请先查看错误或等待完成。',
    'retry_not_available': '只能手动重试已结束的失败请求；进行中和已成功请求不会重发。',
    'session_limit': '当前演示会话额度已到上限，请核对已发生的调用。',
    'busy': '已有一个请求正在生成，本次未发送。',
    'in_progress': '该请求仍在进行，本次未重发。',
    'outcome_unknown': '原请求结果未知。可先查看已保留响应；仅点击手动重试才会发送新请求。',
    'upstream_outcome_unknown': '官方调用未取得有效图片。错误详情已保留；不会自动重试。',
}


def main():
    import tkinter as tk
    from tkinter import messagebox, ttk
    mutex = SingleInstance()
    if not mutex.acquire():
        window = ctypes.windll.user32.FindWindowW(None, TITLE)
        if window:
            ctypes.windll.user32.ShowWindow(window, 9)
            ctypes.windll.user32.SetForegroundWindow(window)
        return
    base = Path(__file__).resolve().parent
    controller = Controller(base / 'private')
    root = tk.Tk()
    root.title(TITLE)
    root.geometry('760x470')
    root.minsize(650, 380)
    root.option_add('*Font', ('Microsoft YaHei', 10))
    events = queue.Queue()
    busy = False
    status = tk.StringVar(value='正在连接本机服务；启动不会生成图片。')
    note = tk.StringVar(value='Flash · 0.12 元/张 · 同一时间只生成一张 · 无自动重试')
    ttk.Label(root, textvariable=note).pack(anchor='w', padx=16, pady=(16, 5))
    ttk.Label(root, textvariable=status, wraplength=710).pack(anchor='w', padx=16, pady=5)
    bar = ttk.Frame(root)
    bar.pack(fill='x', padx=16, pady=8)
    tree = ttk.Treeview(root, columns=('state', 'error'), show='headings', height=10)
    tree.heading('state', text='请求状态 / ID')
    tree.heading('error', text='错误 / 官方状态')
    tree.column('state', width=380)
    tree.column('error', width=320)
    tree.pack(fill='both', expand=True, padx=16, pady=6)
    ttk.Label(root, text='Key 仅由你填写在 private/api_key.local.json；不在此窗口显示。', wraplength=710).pack(anchor='w', padx=16, pady=(4, 12))

    def task(action, work):
        nonlocal busy
        if busy: return
        busy = True
        retry_button.configure(state='disabled')
        start_button.configure(state='disabled')
        def run():
            try: events.put((action, True, work()))
            except Exception as error:
                # Only our fixed errors. Never show JSON snippets, key, headers,
                # raw exception strings, tracebacks or file contents.
                code = error.args[0] if isinstance(error, (LauncherError, ConfigError)) and error.args else 'local_service_unavailable'
                events.put((action, False, code if code in ERROR_TEXT else 'local_service_unavailable'))
        threading.Thread(target=run, daemon=True).start()

    def selected():
        rows = tree.selection()
        return rows[0] if rows else None

    def retry_selected():
        operation = selected()
        if operation: task('retry', lambda: controller.retry(operation, confirmed=True))
        else: status.set('先选择一条失败请求。手动重试会发送一次新的计费请求。')

    def view_selected():
        operation = selected()
        if operation: task('view', lambda: controller.save_result(operation))
        else: status.set('先选择一条成功请求。')

    def open_config():
        folder = base / 'private'
        folder.mkdir(exist_ok=True)
        os.startfile(str(folder))  # Open the folder, never read/prefill the user's key.

    start_button = ttk.Button(bar, text='启动 / 重新连接', command=lambda: task('start', controller.start))
    start_button.pack(side='left')
    ttk.Button(bar, text='打开配置目录', command=open_config).pack(side='left', padx=6)
    retry_button = ttk.Button(bar, text='手动重试（新计费请求）', command=retry_selected)
    retry_button.pack(side='left', padx=6)
    ttk.Button(bar, text='查看选中结果', command=view_selected).pack(side='left')

    def refresh():
        def read(): return controller.status(), controller.operations()
        if not busy: task('refresh', read)

    def consume():
        nonlocal busy
        try:
            while True:
                action, ok, data = events.get_nowait()
                busy = False
                retry_button.configure(state='normal')
                start_button.configure(state='normal')
                if not ok:
                    status.set(ERROR_TEXT.get(data, '本机服务未连接，请检查配置并点启动。'))
                    continue
                if action == 'start': status.set('本机服务已就绪。直接在 Godot 中提交图片，无需每次重启。')
                elif action == 'retry':
                    code = data[1].get('error', {}).get('code') if data[0] != 200 else None
                    status.set('重试已返回图片，可查看结果。' if data[0] == 200 else ERROR_TEXT.get(code, '重试未完成，详情保留；没有再次重发。'))
                elif action == 'view': os.startfile(str(data))
                elif action == 'refresh':
                    audit, operations = data
                    keep = selected()
                    for row in tree.get_children(): tree.delete(row)
                    names = {'done': '成功', 'unknown': '失败/未知', 'inflight': '生成中'}
                    for operation in operations:
                        diagnostic = operation.get('diagnostic', {})
                        error = ' / '.join(str(diagnostic[k]) for k in ('category', 'upstream_http_status', 'vendor_code') if k in diagnostic)
                        tree.insert('', 'end', iid=operation['request_id'], values=(names.get(operation['state'], operation['state']) + ' · ' + operation['request_id'], error))
                    if keep and tree.exists(keep): tree.selection_set(keep)
                    note.set('Flash · 0.12 元/张 · 已调用 %s 次 · %s' % (audit['real_calls'], '生成中' if audit['inflight'] else '可提交'))
        except queue.Empty: pass
        root.after(120, consume)

    def tick():
        if controller.client.session and not busy: refresh()
        root.after(1500, tick)

    def close():
        try: controller.stop()
        except LauncherError:
            messagebox.showinfo('正在生成', ERROR_TEXT['request_in_progress'])
            return
        mutex.close()
        root.destroy()

    # No background startup registration. A user double-click starts only this process.
    root.protocol('WM_DELETE_WINDOW', close)
    root.report_callback_exception = lambda *_: status.set('界面操作未完成，请重新连接；未显示配置内容。')
    root.after(100, lambda: task('start', controller.start))
    root.after(120, consume)
    root.after(1500, tick)
    try: root.mainloop()
    finally: mutex.close()


if __name__ == '__main__': main()
