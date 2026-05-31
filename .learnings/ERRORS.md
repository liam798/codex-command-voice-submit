# Errors

命令失败、集成异常与排障记录。

---

## 2026-05-31 macOS 辅助功能授权

- 重新编译并覆盖 `/Users/liam/.local/bin/codex-voice-auto-send` 后，macOS TCC 可能让 LaunchAgent 退出，表现为 `last exit code = 2`。
- 处理方式是从系统设置的辅助功能列表删除旧项，再重新添加同一个二进制路径，随后重启 LaunchAgent 并以 `launchctl print` 的 `state = running` 作为最终验证。
