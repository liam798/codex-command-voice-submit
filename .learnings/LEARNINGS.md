# Learnings

纠错、经验和知识缺口。

---

## 2026-05-31 Toast 取消窗口设计

- 右侧 Command 长按期间不显示提示，避免打断系统语音输入体验。
- 松开后才显示 `Esc 取消自动发送` Toast，并让默认显示时长跟随 `CCVS_SUBMIT_DELAY_MS`，保证提示覆盖完整可取消窗口。
