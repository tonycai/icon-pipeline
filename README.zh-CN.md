[English](README.md) | 简体中文

# icon-pipeline

从一个 `source.svg` 一条命令生成产品需要的全部图标，并以 Claude Code skill 形式提供。工具链全部开源。

| Target | 产出 |
|---|---|
| `web` | favicon.ico、icon.svg、apple-touch-icon、PNG 集、PWA maskable、manifest |
| `og` | og.png 社交分享图（1200×630，支持中文和日文）及 meta 标签 |
| `ios` | AppIcon.appiconset（1024 单尺寸，Any / Dark / Tinted） |
| `android` | 自适应图标（含 monochrome）、传统与圆形图标、通知图标、Play Store 512、Expo 用的 1024 图层 |

## 安装

任选一种方式，把 skill 放到 `~/.claude/skills/icon-pipeline`。

**方式一：git clone 到 skills 目录**（之后用 `git pull` 升级）

```bash
git clone https://github.com/tonycai/icon-pipeline.git ~/.claude/skills/icon-pipeline
```

**方式二：clone 到任意目录，再软链接到 skills 目录**（适合把仓库放在自己的工作区里）

```bash
git clone https://github.com/tonycai/icon-pipeline.git ~/workspace/icon-pipeline   # 目录可自选
mkdir -p ~/.claude/skills
ln -s ~/workspace/icon-pipeline ~/.claude/skills/icon-pipeline
```

**方式三：下载 zip**（从 [Releases](https://github.com/tonycai/icon-pipeline/releases) 页面下载）

```bash
mkdir -p ~/.claude/skills
unzip icon-pipeline-v2.0.0.zip -d ~/.claude/skills/
chmod +x ~/.claude/skills/icon-pipeline/scripts/*.sh
```

然后安装工具链并检查：

```bash
brew install resvg imagemagick oxipng jq svgo                  # macOS
bash ~/.claude/skills/icon-pipeline/scripts/install-deps.sh    # Ubuntu/Debian：下载预编译二进制，不需要 cargo

bash ~/.claude/skills/icon-pipeline/scripts/build-icons.sh --deps
```

OG 图如果包含中文或日文，建议下载 Noto Sans CJK 或思源黑体（SIL OFL 授权），然后在 `icons/icon.env` 的 `OG_FONT_FILE` 中指定。

## 在 Claude Code 中使用

直接用自然语言描述需求即可，例如"给这个项目做一套图标"、"加上 iOS 和 Android 图标"、"做一张分享图"，Claude 会自动加载这个 skill。也可以手动输入 `/icon-pipeline`。

## 不经过 Claude 手动使用

```bash
cd your-project
bash ~/.claude/skills/icon-pipeline/scripts/init-project.sh   # 自动识别 web / iOS / Android / Expo
make icons            # 或者只构建一部分：make icons-web / icons-og / icons-ios / icons-android
make icons-check      # 在 CI 中检查图标是否过期
```

## 目录结构

```
icon-pipeline/
├── SKILL.md                 工作流程与设计规范（Claude 读取）
├── references/
│   ├── native.md            iOS / Android 各框架接入清单
│   └── og.md                OG 模板、字体、验证方法
├── scripts/
│   ├── build-icons.sh       主流水线（兼容 bash 3.2）
│   ├── init-project.sh      接入项目并自动识别配置
│   └── install-deps.sh      安装工具链（Homebrew，或 apt + 预编译二进制）
├── templates/
│   ├── icons.mk             make 目标
│   └── icon.env             配置模板
├── assets/
│   └── example-source.svg   示例图标
└── .github/workflows/ci.yml CI：shellcheck + 全 target 冒烟测试
```

## 许可证

[MIT](LICENSE)
