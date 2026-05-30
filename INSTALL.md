# 在另一台 Mac 安装 Codex Command Voice Submit

这个工具用于：当前台应用是 Codex / Code X 时，长按 `Command` 语音输入，松开后自动按 `Return` 发送。

## 适用环境

- macOS
- 已安装 Xcode Command Line Tools
- 当前用户有权限开启「辅助功能」和「输入监控」

## 1. 准备源码

推荐把分发包发给别人：

```text
codex-command-voice-submit-<version>.tar.gz
```

对方解压：

```bash
tar -xzf codex-command-voice-submit-<version>.tar.gz
cd codex-command-voice-submit-<version>
```

也可以把整个源码目录复制到另一台 Mac：

```text
codex-command-voice-submit/
```

目录里至少需要这些文件：

```text
Sources/main.swift
Makefile
install.sh
uninstall.sh
README.md
INSTALL.md
package.sh
```

如果要用命令复制，可以在原电脑打包：

```bash
cd /Volumes/Disk_APFS/Work/AI/AiDemos
tar -czf codex-command-voice-submit.tar.gz codex-command-voice-submit
```

在目标电脑解压：

```bash
tar -xzf codex-command-voice-submit.tar.gz
cd codex-command-voice-submit
```

## 1.1 生成分发包

在原电脑上执行：

```bash
cd /Volumes/Disk_APFS/Work/AI/AiDemos/codex-command-voice-submit
./package.sh
```

生成结果会输出类似：

```text
/Volumes/Disk_APFS/Work/AI/AiDemos/codex-command-voice-submit/dist/codex-command-voice-submit-20260529-183000.tar.gz
```

也可以指定版本名：

```bash
./package.sh v1.0.0
```

生成：

```text
dist/codex-command-voice-submit-v1.0.0.tar.gz
```

## 2. 安装编译工具

目标电脑如果没有 `swiftc`，先安装 Xcode Command Line Tools：

```bash
xcode-select --install
```

检查：

```bash
swiftc --version
```

## 3. 编译

```bash
cd codex-command-voice-submit
make build
```

成功后会生成：

```text
.build/codex-command-voice-submit
```

## 4. 安装为后台启动

```bash
make install
```

安装后会写入：

```text
~/.local/bin/codex-command-voice-submit
~/Library/LaunchAgents/com.local.codex-command-voice-submit.plist
```

## 5. 授权 macOS 权限

打开系统设置：

```bash
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
```

在下面两个位置授权：

- 系统设置 -> 隐私与安全性 -> 辅助功能
- 系统设置 -> 隐私与安全性 -> 输入监控

如果列表里出现 `codex-command-voice-submit`，打开它；如果没有出现，可以先运行一次：

```bash
~/.local/bin/codex-command-voice-submit --request-permission
```

然后回到系统设置查看。必要时也给 `Terminal` 授权。

## 6. 重启后台进程

授权后执行：

```bash
make install
```

或者手动重启：

```bash
launchctl unload ~/Library/LaunchAgents/com.local.codex-command-voice-submit.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.local.codex-command-voice-submit.plist
```

## 7. 验证

检查后台进程：

```bash
launchctl list | grep codex-command-voice-submit
```

看到类似输出表示已运行：

```text
12345   0   com.local.codex-command-voice-submit
```

检查配置：

```bash
~/.local/bin/codex-command-voice-submit --check
```

如果从终端运行仍显示：

```text
accessibilityTrusted=false
```

但 `launchctl list` 里后台进程状态是 `0` 且没有反复退出，通常表示后台进程已经可用，只是当前 Terminal 没被授权。

查看日志：

```bash
tail -80 ~/Library/Logs/codex-command-voice-submit.err.log
tail -80 ~/Library/Logs/codex-command-voice-submit.log
```

## 8. 使用

1. 打开 Codex / Code X。
2. 聚焦输入框。
3. 长按左侧 `Command` 进行语音输入。
4. 松开 `Command`。
5. 工具会默认等待 `900ms`，然后自动发送 `Return`。

如果识别过程中说错了，或者松开后想取消本次自动发送，按 `Escape`。取消键在两种时机都有效：

- 仍按住触发键时
- 松开触发键后的 `900ms` 等待窗口内

默认会显示一个轻量浮层提示：

```text
按 Escape 取消自动发送
```

默认保护逻辑：

- `Command` 必须按住至少 `2000ms`。
- 按住期间如果按了其他普通键，不会自动发送。
- 只有当前台应用名称或 bundle id 匹配 Codex / Code X 时才触发。

## 9. 调整参数

安装时可调整阈值：

```bash
CCVS_MIN_HOLD_MS=800 CCVS_SUBMIT_DELAY_MS=500 make install
```

也可以配置触发修饰键和自动发送键：

```bash
CCVS_TRIGGER_MODIFIER=control CCVS_SUBMIT_KEY=tab make install
```

配置触发键的左右侧：

```bash
CCVS_TRIGGER_SIDE=left make install
CCVS_TRIGGER_SIDE=right make install
CCVS_TRIGGER_SIDE=any make install
```

配置取消键，或禁用取消：

```bash
CCVS_CANCEL_KEY=space make install
CCVS_CANCEL_KEY=none make install
```

配置或关闭提示浮层：

```bash
CCVS_HINT_TEXT='按 Escape 取消自动发送' make install
CCVS_SHOW_HINT=0 make install
```

支持多个 App 平台，名称和 bundle id 都用英文逗号分隔：

```bash
CCVS_APP_NAMES='Codex,Code X,Cursor' \
CCVS_BUNDLE_IDS='com.openai.codex,com.openai.chatgpt,com.todesktop.230313mzl4w4u92' \
make install
```

常用变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `CCVS_MIN_HOLD_MS` | `2000` | Command 按住多久才触发 |
| `CCVS_SUBMIT_DELAY_MS` | `900` | 松开后等待多久再发送 Return |
| `CCVS_TRIGGER_MODIFIER` | `command` | 触发修饰键，可选 `command` / `control` / `option` / `shift` |
| `CCVS_TRIGGER_SIDE` | `left` | 触发键侧，可选 `left` / `right` / `any` |
| `CCVS_SUBMIT_KEY` | `return` | 自动发送的按键，可选 `return` / `tab` / `space` / `escape` |
| `CCVS_CANCEL_KEY` | `escape` | 取消本次自动发送的按键，可选 `return` / `tab` / `space` / `escape` / `none` |
| `CCVS_SHOW_HINT` | `1` | 是否显示取消提示浮层 |
| `CCVS_HINT_TEXT` | `按 Escape 取消自动发送` | 自定义提示文案 |
| `CCVS_APP_NAMES` | `Codex,Code X,CodeX` | 前台应用名称匹配，逗号分隔 |
| `CCVS_BUNDLE_IDS` | `com.openai.codex,com.openai.chatgpt` | 前台应用 bundle id 匹配，逗号分隔 |
| `CCVS_VERBOSE` | `0` | 是否输出调试日志 |
| `CCVS_DRY_RUN` | `0` | 只打印动作，不真实发送 Return |

## 10. 卸载

```bash
make uninstall
```

或手动删除：

```bash
launchctl unload ~/Library/LaunchAgents/com.local.codex-command-voice-submit.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.local.codex-command-voice-submit.plist
rm -f ~/.local/bin/codex-command-voice-submit
```

## 11. 常见问题

### 松开 Command 没反应

先看后台是否运行：

```bash
launchctl list | grep codex-command-voice-submit
```

再看错误日志：

```bash
tail -80 ~/Library/Logs/codex-command-voice-submit.err.log
```

如果看到「需要授予辅助功能权限」，回到系统设置授权后重新 `make install`。

### 正常快捷键会不会被误发送

一般不会。按住 `Command` 期间只要检测到其他普通键，就会跳过自动发送。

### 目标电脑上的 Codex 名称不一样

重新安装时指定应用名或 bundle id：

```bash
CCVS_APP_NAMES='Codex,Code X,Your App Name' make install
```

或：

```bash
CCVS_BUNDLE_IDS='com.openai.codex,你的.bundle.id' make install
```
