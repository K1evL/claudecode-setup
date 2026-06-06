# ClaudeCode 一键环境配置器

一键安装 Claude Code 运行环境，自动配置 Node.js、npm、cc-switch，让你开箱即用。

## 快速开始

### 1. 运行安装程序

```
双击 ClaudeCode-Setup.exe → 点击"以管理员身份运行"
等待 2-5 分钟，自动完成全部安装
```

### 2. 打开命令行

```
Windows + R → 输入 cmd → 回车
```

### 3. 设置 API Key

```cmd
claude set-key YOUR_API_KEY
```

### 4. 启动 Claude Code

```cmd
claude
```

---

## 获取 API Key

Claude Code 支持多种 AI 模型，下面以 **DeepSeek** 为例说明如何获取 API Key。

### DeepSeek API Key

1. 打开 https://platform.deepseek.com/
2. 注册账号并登录
3. 点击左侧 **API Keys**
4. 点击 **Create API Key**
5. 复制生成的 Key（以 `sk-` 开头）

### 配置到 cc-switch

cc-switch 是模型切换工具，安装完成后在桌面就有快捷方式。

#### 方式一：桌面应用配置

1. 双击桌面 **CC-Switch** 图标
2. 点击 **Add Provider**
3. 选择 **DeepSeek**
4. 在 API Key 栏粘贴刚才复制的 Key
5. 点击 **Save**

#### 方式二：命令行配置

```cmd
cc-switch config set provider deepseek
cc-switch config set api_key sk-your-key-here
```

#### 切换模型

在 cc-switch 桌面应用中选择模型，或在命令行运行：

```cmd
cc-switch switch deepseek-chat
```

### 其他模型 API Key

| 模型 | 官网 | 说明 |
|------|------|------|
| **DeepSeek** | https://platform.deepseek.com/ | 性价比高，推荐首选 |
| **OpenAI** | https://platform.openai.com/api-keys | 需海外支付方式 |
| **Anthropic Claude** | https://console.anthropic.com/ | Claude Code 原生模型 |
| **Gemini** | https://aistudio.google.com/ | Google 免费额度 |

---

## 验证报告

安装完成后会输出验证报告，所有项显示 ✅ 即表示环境就绪：

```
╔════════════════════════════════════════════════════════╗
║         ClaudeCode 环境配置报告                        ║
╠════════════════════════════════════════════════════════╣
║ [✅] Node.js                    v20.18.0               ║
║ [✅] npm                        v10.8.2                ║
║ [✅] npm prefix                 C:\Users\xxx\npm-global║
║ [✅] claude-code CLI            2.1.165                ║
║ [✅] cc-switch                  桌面应用               ║
║ [✅] PATH - Node.js             C:\nodejs              ║
║ [✅] PATH - npm-global          C:\Users\xxx\npm-global║
╚════════════════════════════════════════════════════════╝
```

---

## 卸载

再次运行安装程序，选择卸载模式即可一键清理全部组件。

---

## 系统要求

- Windows 10 / Windows 11（64 位）
- 管理员权限（安装时需要）
- 网络连接（自动下载所需组件）

## 安装内容

| 组件 | 版本 | 说明 |
|------|------|------|
| Node.js | >= 18.x LTS | JavaScript 运行环境 |
| npm | >= 9.x | Node.js 包管理器 |
| cc-switch | 最新版 | 模型切换桌面应用 |
| claude-code CLI | 最新版 | Claude Code 命令行工具 |

## 常见问题

### Q: 安装后 `claude` 命令找不到？

新开一个 **cmd** 窗口（Windows + R → cmd），不要用 PowerShell。

### Q: 下载很慢或卡住？

安装程序会自动切换国内镜像源加速，如果网络环境特殊，可以手动下载 cc-switch：
https://github.com/farion1231/cc-switch/releases

### Q: 如何更新 cc-switch？

重新运行安装程序即可自动更新到最新版。

---

## 项目地址

https://github.com/K1evL/claudecode-setup
