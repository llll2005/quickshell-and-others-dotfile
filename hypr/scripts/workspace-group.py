#!/usr/bin/env python3
"""
Workspace group manager for Hyprland - 動態分組管理
Usage:
  # 導航
  workspace-group.py next-in-group       # 切換到同組下一個 workspace
  workspace-group.py prev-in-group       # 切換到同組上一個 workspace
  workspace-group.py switch <group>      # 切換到指定組的第一個 workspace

  # 查詢
  workspace-group.py list                # 列出所有分組
  workspace-group.py current-group       # 顯示當前所屬分組

  # 動態管理
  workspace-group.py create <name> <label> <icon> <color>  # 建立新分組
  workspace-group.py add <group> <workspace_id>            # 將 workspace 加入分組
  workspace-group.py remove <group> <workspace_id>         # 從分組移除 workspace
  workspace-group.py delete <group>                        # 刪除分組
  workspace-group.py set-current <group>                   # 將當前 workspace 加入指定分組
  workspace-group.py ui                                    # 開啟互動式管理 UI
"""
import json
import subprocess
import sys
from pathlib import Path

CONFIG_PATH = Path.home() / ".config/hypr/workspace-groups.json"

def load_groups():
    if not CONFIG_PATH.exists():
        return {}
    with open(CONFIG_PATH) as f:
        return json.load(f)["groups"]

def get_current_workspace():
    result = subprocess.run(
        ["hyprctl", "activeworkspace", "-j"],
        capture_output=True, text=True
    )
    return json.loads(result.stdout)["id"]

def get_group_for_workspace(ws_id, groups):
    for group_name, group_data in groups.items():
        if ws_id in group_data["workspaces"]:
            return group_name, group_data
    return None, None

def switch_workspace(ws_id):
    subprocess.run(["hyprctl", "dispatch", f"workspace({ws_id})"])

def next_in_group():
    groups = load_groups()
    current_ws = get_current_workspace()
    group_name, group_data = get_group_for_workspace(current_ws, groups)

    if not group_data:
        print(f"Workspace {current_ws} not in any group")
        return

    workspaces = sorted(group_data["workspaces"])
    try:
        idx = workspaces.index(current_ws)
        next_ws = workspaces[(idx + 1) % len(workspaces)]
        switch_workspace(next_ws)
        print(f"{group_data['icon']} {group_data['label']}: {current_ws} → {next_ws}")
    except ValueError:
        pass

def prev_in_group():
    groups = load_groups()
    current_ws = get_current_workspace()
    group_name, group_data = get_group_for_workspace(current_ws, groups)

    if not group_data:
        print(f"Workspace {current_ws} not in any group")
        return

    workspaces = sorted(group_data["workspaces"])
    try:
        idx = workspaces.index(current_ws)
        prev_ws = workspaces[(idx - 1) % len(workspaces)]
        switch_workspace(prev_ws)
        print(f"{group_data['icon']} {group_data['label']}: {current_ws} → {prev_ws}")
    except ValueError:
        pass

def switch_to_group(group_name):
    groups = load_groups()
    if group_name not in groups:
        print(f"Group '{group_name}' not found")
        return

    group_data = groups[group_name]
    first_ws = sorted(group_data["workspaces"])[0]
    switch_workspace(first_ws)
    print(f"{group_data['icon']} {group_data['label']}: → workspace {first_ws}")

def list_groups():
    groups = load_groups()
    current_ws = get_current_workspace()

    for group_name, group_data in groups.items():
        ws_list = ", ".join(map(str, sorted(group_data["workspaces"])))
        marker = "●" if current_ws in group_data["workspaces"] else " "
        print(f"{marker} {group_data['icon']} {group_data['label']}: {ws_list}")

def current_group():
    groups = load_groups()
    current_ws = get_current_workspace()
    group_name, group_data = get_group_for_workspace(current_ws, groups)

    if group_data:
        print(f"{group_data['icon']} {group_data['label']}")
    else:
        print("未分組")

def save_groups(groups):
    """儲存分組配置"""
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_PATH, 'w') as f:
        json.dump({"groups": groups}, f, indent=2, ensure_ascii=False)

def create_group(name, label, icon, color):
    """建立新分組"""
    groups = load_groups()
    if name in groups:
        print(f"❌ 分組 '{name}' 已存在")
        return

    groups[name] = {
        "label": label,
        "icon": icon,
        "workspaces": [],
        "color": color
    }
    save_groups(groups)
    print(f"✓ 已建立分組: {icon} {label}")

def add_to_group(group_name, workspace_id):
    """將 workspace 加入分組"""
    groups = load_groups()
    if group_name not in groups:
        print(f"❌ 分組 '{group_name}' 不存在")
        return

    workspace_id = int(workspace_id)

    # 從其他分組中移除
    for gname, gdata in groups.items():
        if workspace_id in gdata["workspaces"]:
            gdata["workspaces"].remove(workspace_id)
            print(f"從 {gdata['icon']} {gdata['label']} 移除 workspace {workspace_id}")

    # 加入新分組
    if workspace_id not in groups[group_name]["workspaces"]:
        groups[group_name]["workspaces"].append(workspace_id)
        groups[group_name]["workspaces"].sort()

    save_groups(groups)
    print(f"✓ workspace {workspace_id} → {groups[group_name]['icon']} {groups[group_name]['label']}")

def remove_from_group(group_name, workspace_id):
    """從分組移除 workspace"""
    groups = load_groups()
    if group_name not in groups:
        print(f"❌ 分組 '{group_name}' 不存在")
        return

    workspace_id = int(workspace_id)
    if workspace_id in groups[group_name]["workspaces"]:
        groups[group_name]["workspaces"].remove(workspace_id)
        save_groups(groups)
        print(f"✓ 已從 {groups[group_name]['icon']} {groups[group_name]['label']} 移除 workspace {workspace_id}")
    else:
        print(f"❌ workspace {workspace_id} 不在此分組中")

def delete_group(group_name):
    """刪除分組"""
    groups = load_groups()
    if group_name not in groups:
        print(f"❌ 分組 '{group_name}' 不存在")
        return

    group_data = groups[group_name]
    del groups[group_name]
    save_groups(groups)
    print(f"✓ 已刪除分組: {group_data['icon']} {group_data['label']}")

def set_current_workspace_group(group_name):
    """將當前 workspace 加入指定分組"""
    current_ws = get_current_workspace()
    add_to_group(group_name, current_ws)

def interactive_ui():
    """互動式管理介面"""
    try:
        import subprocess
        groups = load_groups()
        current_ws = get_current_workspace()

        # 建立選單選項
        options = []
        options.append("➕ 建立新分組")
        options.append("---")

        for gname, gdata in groups.items():
            ws_list = ", ".join(map(str, sorted(gdata["workspaces"])))
            marker = "●" if current_ws in gdata["workspaces"] else "○"
            options.append(f"{marker} {gdata['icon']} {gdata['label']} [{ws_list}]")

        # 用 rofi/fuzzy 選擇
        choice = subprocess.run(
            ["rofi", "-dmenu", "-i", "-p", "Workspace Groups"],
            input="\n".join(options),
            capture_output=True,
            text=True
        )

        if choice.returncode != 0:
            return

        selected = choice.stdout.strip()

        if selected == "➕ 建立新分組":
            # TODO: 實作新增分組的互動流程
            print("請使用: workspace-group.py create <name> <label> <icon> <color>")
        elif selected.startswith("● ") or selected.startswith("○ "):
            # 點擊分組 → 切換到該分組第一個 workspace
            for gname, gdata in groups.items():
                if f"{gdata['icon']} {gdata['label']}" in selected:
                    switch_to_group(gname)
                    break

    except ImportError:
        print("需要安裝 rofi: sudo pacman -S rofi")
    except FileNotFoundError:
        print("需要安裝 rofi: sudo pacman -S rofi")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]

    # 導航命令
    if cmd == "next-in-group":
        next_in_group()
    elif cmd == "prev-in-group":
        prev_in_group()
    elif cmd == "switch" and len(sys.argv) > 2:
        switch_to_group(sys.argv[2])

    # 查詢命令
    elif cmd == "list":
        list_groups()
    elif cmd == "current-group":
        current_group()

    # 動態管理命令
    elif cmd == "create" and len(sys.argv) >= 6:
        create_group(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif cmd == "add" and len(sys.argv) >= 4:
        add_to_group(sys.argv[2], sys.argv[3])
    elif cmd == "remove" and len(sys.argv) >= 4:
        remove_from_group(sys.argv[2], sys.argv[3])
    elif cmd == "delete" and len(sys.argv) >= 3:
        delete_group(sys.argv[2])
    elif cmd == "set-current" and len(sys.argv) >= 3:
        set_current_workspace_group(sys.argv[2])
    elif cmd == "ui":
        interactive_ui()

    else:
        print(__doc__)
        sys.exit(1)
