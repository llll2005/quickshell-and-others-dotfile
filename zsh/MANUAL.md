# 終端機速查

在終端機打 `manual` 打開這份。設定檔：`~/.zshrc`、`~/.config/zsh/`（prompt.zsh、tools.zsh）、
`~/.config/kitty/kitty.conf`。配色都跟著 Quickshell 的主題（`qs ipc call theme set <名稱>`
換主題，開著的終端機在下一個提示符就換色）。

## 跳目錄：zoxide

| 指令 | 作用 |
|---|---|
| `z foo` | 跳到最常去、名字含 foo 的目錄（`z foo bar` 可給多個關鍵字） |
| `zi` | 用 fzf 從去過的目錄裡挑 |
| `z -` | 回上一個目錄 |

它從你 `cd` 過的地方學，用一陣子才會準。

## 找檔案：fzf

| 按鍵 | 作用 |
|---|---|
| `Ctrl+T` | 在游標處插入檔案路徑（右邊預覽內容） |
| `Alt+C` | 跳進底下的某個目錄（預覽目錄樹） |
| `Tab` | 補全清單也是 fzf（fzf-tab）；`<` `>` 切換群組 |
| `vim **<Tab>` | 就地模糊補全路徑 |

## 歷史：atuin

| 按鍵 / 指令 | 作用 |
|---|---|
| `Ctrl+R` | 全螢幕搜尋歷史（模糊比對）。再按 `Ctrl+R` 切換範圍：全部 → 這台機器 → 這個 shell → 這個目錄 |
| `↵` / `Tab` | 放到命令列（還可以改），不直接執行；`Esc` 離開 |
| `↑` `↓` | 照舊：找以目前輸入開頭的歷史 |
| `atuin stats` | 最常用的指令 |
| `atuin search --exit 1 docker` | 找失敗過、含 docker 的指令 |

它也記下每個指令的耗時、結束碼、目錄。只存在本機，不同步。
**第一次裝好後跑一次** `atuin import zsh`，把舊的歷史匯進去。

## Git：delta

| 指令 | 作用 |
|---|---|
| `git diff` / `git show` / `git log -p` | 自動經過 delta：語法高亮、行號、字詞層級的差異 |
| 在 delta 裡 `n` / `N` | 跳到下一個 / 上一個檔案 |
| `git -c delta.side-by-side=true diff` | 左右對照 |
| `delta a.txt b.txt` | 比較兩個檔案 |

## 找不到指令：pkgfile

打了沒裝的指令，會告訴你哪個套件有它（例如 `in extra/htop   pacman -S htop`）。

| 指令 | 作用 |
|---|---|
| `pkgfile 檔名` | 哪個套件有這個檔案 |
| `pkgfile -l 套件` | 列出套件裡的檔案 |

資料庫由 `pkgfile-update.timer` 每天更新。

## ssh：kitten ssh

在 kitty 裡 `ssh`（還有用到 ssh 的別名）會變成 `kitten ssh`：遠端自動有 kitty 的 terminfo
與 shell 整合，不會再出現 unknown terminal。密碼、金鑰密語、「要不要信任這台主機」都在虛空
畫面裡問。

## kitty 快捷鍵

| 按鍵 | 作用 |
|---|---|
| `Ctrl+Shift+Z` / `Ctrl+Shift+X` | 跳到上一個 / 下一個指令的提示符 |
| `Ctrl+Shift+G` | 複製上一個指令的輸出 |
| `Ctrl+Shift+H` | 用 pager 打開整個捲動紀錄；`Ctrl+Shift+/` 直接搜尋 |
| `Ctrl+Shift+E` | 用鍵盤選畫面上的網址打開 |
| `Ctrl+Shift+P` 再按 `F` | 把畫面上的某個路徑插入命令列 |
| `Ctrl+Shift+F3` | 指令面板：kitty 所有動作 |
| `Ctrl+=` / `Ctrl+-` / `Ctrl+Backspace` | 字放大 / 縮小 / 還原 |

往回捲時右邊會出現細捲軸，可以拖。

## 提示符

```
◆ ~/.config/quickshell   main ↑1 ●2 ✚1 …3   ◇ ml   2.4s   ✕ 1
▸
```

◆ 失敗時變紅 · 路徑（只留最後三層）· git 分支、領先 ↑ / 落後 ↓、已暫存 ●、已修改 ✚、未追蹤 …
（在背景讀，大的 repo 也不會卡）· conda / venv 環境 · 上個指令的耗時（2 秒以上）· 結束碼。

輸入完的指令會縮成一行 `▸ 指令`，捲動紀錄就是一串指令和它們的輸出。

花 10 秒以上的指令，如果結束時你在別的視窗，HUD 會跳出 DONE / FAILED 卡片，點它回到終端機。

## 虛空：密碼與確認

- sudo、ssh、git 的密碼，gpg 的密語，都在同一個黑底畫面輸入；在 kitty 裡標題是兩倍大。
  沒有終端機的時候（例如 GUI 程式裡的 git）改由 Quickshell 在螢幕上問。
- `pacman` / `sudo pacman` 的交易在虛空裡跑，問題變成卡片，結束時印出 COMPLETED / FAILED。
- 自己的腳本也能用：

| 指令 | 作用 |
|---|---|
| `voidbox confirm "要刪掉嗎？"` | YES / NO（預設 NO）；選 YES 時結束碼 0 |
| `voidbox choose 標題 選項1 選項2 …` | 編號清單，印出選到的那個；選項可以寫成 `名稱<Tab>說明` |
| `dl URL [檔名]` | 下載（選 aria2 多線程或 curl） |
| `gclone REPO [目錄]` | git clone 加進度條 |
| `gsnap` | 搜尋 snapper 的快照，印出還原指令 |

## 其他

- 啟動約 0.03 秒：外掛在第一個提示符出現後才載入；conda 第一次打 `conda` 才載入。
- 換主題時終端機配色跟著換；不想要就在設定面板（SUPER+ALT+S）的 LOOK 頁關掉
  「終端機跟著主題」，kitty 會回到 kitty.conf 自己的配色。
