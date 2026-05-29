# Codex Command Voice Submit

一个 macOS 本机辅助进程：当前台应用是 Codex / Code X 时，长按 `Command` 后松开，会在短暂延迟后自动发送 `Return`，用于把语音输入完成后的文本发出去。

另一台 Mac 的完整安装步骤见 [INSTALL.md](INSTALL.md)。

生成可分发压缩包：

```bash
./package.sh
```

## 行为

- 默认监听 `Command` 的按下与松开，也可配置为 `Control` / `Option` / `Shift`。
- 默认要求按住至少 `650ms`。
- 如果按住 `Command` 期间又按了其他普通键，会判定为正常快捷键，不会自动发送。
- 只在前台应用名称或 bundle id 匹配 Codex / Code X 时触发。
- 松开后默认等待 `900ms` 再发送 `Return`，给语音输入一点落字时间。

## 构建

```bash
cd /Volumes/Disk_APFS/Work/AI/AiDemos/codex-command-voice-submit
make build
```

## 前台试运行

先检查配置和权限：

```bash
.build/codex-command-voice-submit --check
```

如果需要触发一次 macOS 授权提示：

```bash
.build/codex-command-voice-submit --request-permission
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
~/Library/Logs/codex-command-voice-submit.log
~/Library/Logs/codex-command-voice-submit.err.log
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

支持多个 App 名称和 bundle id，使用英文逗号分隔：

```bash
CCVS_APP_NAMES='Codex,Code X,Cursor' \
CCVS_BUNDLE_IDS='com.openai.codex,com.todesktop.230313mzl4w4u92,com.todesktop.230313mzl4w4u92' \
make install
```

可用配置：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `CCVS_MIN_HOLD_MS` | `650` | Command 按住多久才触发 |
| `CCVS_SUBMIT_DELAY_MS` | `900` | 松开后等待多久再发送 Return |
| `CCVS_TRIGGER_MODIFIER` | `command` | 触发修饰键，可选 `command` / `control` / `option` / `shift` |
| `CCVS_SUBMIT_KEY` | `return` | 自动发送的按键，可选 `return` / `tab` / `space` / `escape` |
| `CCVS_APP_NAMES` | `Codex,Code X,CodeX` | 前台应用名称匹配，逗号分隔 |
| `CCVS_BUNDLE_IDS` | `com.openai.codex,com.openai.chatgpt` | 前台应用 bundle id 匹配，逗号分隔 |
| `CCVS_VERBOSE` | `0` | 是否输出调试日志 |
| `CCVS_DRY_RUN` | `0` | 只打印动作，不真实发送 Return |

## 卸载

```bash
make uninstall
```
