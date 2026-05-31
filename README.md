# Codex Voice Auto Send

一个 macOS 本机辅助进程：当前台应用是 Codex / Code X 时，长按指定修饰键后松开，会在短暂延迟后自动发送 `Return`，用于把语音输入完成后的文本发出去。

English: A small macOS helper for Codex / Code X. Hold a configurable modifier key while dictating, release it, and the helper sends `Return` after a short delay. You can press the cancel key before auto-send.

另一台 Mac 的完整安装步骤见 [INSTALL.md](INSTALL.md)。

生成可分发压缩包：

```bash
./package.sh
```

推送 `v*` tag 后，GitHub Actions 会自动构建压缩包并发布 Release。

## 行为

- 默认只监听左侧 `Command` 的按下与松开；可配置为右侧或两侧，也可改用 `Control` / `Option` / `Shift`。
- 默认要求按住至少 `2000ms`。
- 如果按住 `Command` 期间又按了其他普通键，会判定为正常快捷键，不会自动发送。
- 只在前台应用名称或 bundle id 匹配 Codex / Code X 时触发。
- 松开后默认显示短 Toast，并等待 `2000ms` 再发送 `Return`。
- 默认按 `Escape` 可取消本次自动发送：按住触发键期间或松开后的等待窗口内都有效。
- 长按期间不显示提示；松开并确认满足触发条件后才显示短 Toast：`Esc 取消自动发送`，Toast 会自动消失。

## 构建

```bash
cd /Volumes/Disk_APFS/Work/AI/AiDemos/codex-voice-auto-send
make build
```

## 前台试运行

先检查配置和权限：

```bash
.build/codex-voice-auto-send --check
```

如果需要触发一次 macOS 授权提示：

```bash
.build/codex-voice-auto-send --request-permission
```

再启动前台监听：

```bash
CCVS_VERBOSE=1 make run
```

第一次运行时，macOS 可能会弹权限。需要授予：

- 系统设置 -> 隐私与安全性 -> 辅助功能
- 系统设置 -> 隐私与安全性 -> 输入监控

如果是从 Terminal 运行，给 Terminal 授权；如果安装成后台进程，给生成的二进制或对应父进程授权。

## 安装为开机启动

```bash
make install
```

日志位置：

```text
~/Library/Logs/codex-voice-auto-send.log
~/Library/Logs/codex-voice-auto-send.err.log
```

## 配置

安装时可通过环境变量调整：

```bash
CCVS_MIN_HOLD_MS=800 CCVS_SUBMIT_DELAY_MS=500 make install
```

改成按住 `Control` 触发、松开发送 `Tab`：

```bash
CCVS_TRIGGER_MODIFIER=control CCVS_SUBMIT_KEY=tab make install
```

改成右侧 Command 或左右 Command 都触发：

```bash
CCVS_TRIGGER_SIDE=right make install
CCVS_TRIGGER_SIDE=any make install
```

改成按 `Space` 取消，或禁用取消键：

```bash
CCVS_CANCEL_KEY=space make install
CCVS_CANCEL_KEY=none make install
```

配置或关闭提示浮层：

```bash
CCVS_HINT_TEXT='Esc 取消自动发送' make install
CCVS_HINT_DURATION_MS=800 make install
CCVS_SHOW_HINT=0 make install
```

支持多个 App 名称和 bundle id，使用英文逗号分隔：

```bash
CCVS_APP_NAMES='Codex,Code X,Cursor' \
CCVS_BUNDLE_IDS='com.openai.codex,com.todesktop.230313mzl4w4u92,com.todesktop.230313mzl4w4u92' \
make install
```

可用配置：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `CCVS_MIN_HOLD_MS` | `2000` | Command 按住多久才触发 |
| `CCVS_SUBMIT_DELAY_MS` | `2000` | 松开后等待多久再发送 Return |
| `CCVS_TRIGGER_MODIFIER` | `command` | 触发修饰键，可选 `command` / `control` / `option` / `shift` |
| `CCVS_TRIGGER_SIDE` | `left` | 触发键侧，可选 `left` / `right` / `any` |
| `CCVS_SUBMIT_KEY` | `return` | 自动发送的按键，可选 `return` / `tab` / `space` / `escape` |
| `CCVS_CANCEL_KEY` | `escape` | 取消本次自动发送的按键，可选 `return` / `tab` / `space` / `escape` / `none` |
| `CCVS_SHOW_HINT` | `1` | 是否显示取消提示浮层 |
| `CCVS_HINT_TEXT` | `Esc 取消自动发送` | 自定义提示文案 |
| `CCVS_HINT_DURATION_MS` | 跟随 `CCVS_SUBMIT_DELAY_MS` | Toast 提示显示多久后自动隐藏 |
| `CCVS_APP_NAMES` | `Codex,Code X,CodeX` | 前台应用名称匹配，逗号分隔 |
| `CCVS_BUNDLE_IDS` | `com.openai.codex,com.openai.chatgpt` | 前台应用 bundle id 匹配，逗号分隔 |
| `CCVS_VERBOSE` | `0` | 是否输出调试日志 |
| `CCVS_DRY_RUN` | `0` | 只打印动作，不真实发送 Return |

## 卸载

```bash
make uninstall
```

## English

Codex Voice Auto Send is a local macOS helper for voice input in Codex / Code X. When the frontmost app matches Codex / Code X, hold a configured modifier key, release it after dictation, and the helper automatically sends `Return` after a short delay.

Full installation instructions for another Mac are available in [INSTALL.md](INSTALL.md).

### Behavior

- The trigger modifier defaults to `Command`; the trigger side can be `left`, `right`, or `any`.
- The installed local configuration currently uses the right `Command` key.
- The modifier must be held by itself for at least `2000ms` by default.
- If another normal key is pressed while holding the modifier, the gesture is treated as a normal shortcut and will not auto-send.
- The frontmost app must match the configured app names or bundle identifiers.
- After release, the helper shows a short toast and waits `2000ms` by default before sending `Return`.
- Press `Escape` while holding the trigger key, or during the post-release delay, to cancel auto-send.
- No hint is shown while holding the trigger key. A short toast appears only after release when the gesture is eligible to auto-send. The default hint is `Esc 取消自动发送`, and the toast duration follows `CCVS_SUBMIT_DELAY_MS`.

### Quick Start

```bash
make build
make install
```

macOS permissions are required:

- System Settings -> Privacy & Security -> Accessibility
- System Settings -> Privacy & Security -> Input Monitoring

Check configuration and permission state:

```bash
~/.local/bin/codex-voice-auto-send --check
```

### Configuration

Set environment variables when installing:

```bash
CCVS_TRIGGER_SIDE=right CCVS_MIN_HOLD_MS=2000 make install
```

Common options:

| Variable | Default | Description |
| --- | --- | --- |
| `CCVS_MIN_HOLD_MS` | `2000` | Minimum hold duration before the gesture can trigger |
| `CCVS_SUBMIT_DELAY_MS` | `2000` | Delay after release before sending `Return` |
| `CCVS_TRIGGER_MODIFIER` | `command` | Trigger modifier: `command`, `control`, `option`, or `shift` |
| `CCVS_TRIGGER_SIDE` | `left` | Trigger side: `left`, `right`, or `any` |
| `CCVS_SUBMIT_KEY` | `return` | Key to auto-send: `return`, `tab`, `space`, or `escape` |
| `CCVS_CANCEL_KEY` | `escape` | Key used to cancel auto-send; set to `none` to disable |
| `CCVS_SHOW_HINT` | `1` | Whether to show the toast hint |
| `CCVS_HINT_TEXT` | `Esc 取消自动发送` | Custom hint text |
| `CCVS_HINT_DURATION_MS` | follows `CCVS_SUBMIT_DELAY_MS` | Toast auto-hide duration |
| `CCVS_APP_NAMES` | `Codex,Code X,CodeX` | Comma-separated frontmost app name patterns |
| `CCVS_BUNDLE_IDS` | `com.openai.codex,com.openai.chatgpt` | Comma-separated bundle id patterns |
