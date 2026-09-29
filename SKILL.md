---
name: icon-pipeline
description: 为项目设计并生成全套图标与分享图：从一个 source.svg 产出网站 favicon/PWA 图标、iOS AppIcon（含 Dark/Tinted）、Android 自适应图标（含 monochrome、通知图标、Play Store 图标）和 OG 社交分享图（og.png），并接入项目。只要用户提到 icon、图标、favicon、app icon、应用图标、PWA、apple-touch-icon、adaptive icon、通知图标、OG 图、OGP、社交分享图、twitter card、アイコン，或要为新项目制作/更换图标、检查图标是否过期，就使用本 skill——即使用户没有点名它。
argument-hint: "[path/to/source.svg]"
---

# Icon Pipeline

一个 SVG 生成产品需要的所有图标。工具链全部开源：resvg（或 rsvg-convert / inkscape）+ ImageMagick，可选 svgo、oxipng、jq。

本 skill 目录记作 `$SKILL`：个人安装在 `~/.claude/skills/icon-pipeline/`，项目级安装在 `.claude/skills/icon-pipeline/`。

| Target | 产出 | 细节参考 |
|---|---|---|
| `web` | favicon.ico、icon.svg、apple-touch-icon、PNG 集、PWA maskable、manifest | 本文 |
| `og` | og.png（1200×630）+ og/twitter meta 标签 | `$SKILL/references/og.md` |
| `ios` | AppIcon.appiconset：1024 单尺寸，Any / Dark / Tinted 三种外观 | `$SKILL/references/native.md` |
| `android` | 自适应图标（前景/背景/monochrome）、传统与圆形图标、通知图标、Play Store 512 | `$SKILL/references/native.md` |

处理 og、ios 或 android 之前，先读对应的参考文件。

## 工作流程

### 1. 检查工具链

项目已接入时运行 `make icons-deps`，否则运行 `bash $SKILL/scripts/build-icons.sh --deps`。缺少必需工具时把安装命令告诉用户，由用户决定；不要自行 sudo 安装系统包。

### 2. 接入项目（每个项目一次）

```bash
bash $SKILL/scripts/init-project.sh            # 可加 --out DIR --name "App" --example
```

它会自动识别 Web 根目录、Flutter web、Xcode 的 `AppIcon.appiconset`（Capacitor / React Native / Flutter / Tauri）、Android `res/` 和 Expo，把结果写进 `icons/icon.env` 的 `TARGETS`、`IOS_ICONSET_DIR`、`ANDROID_RES_DIR`。脚本会被 vendor 进项目，并更新 `.gitignore` 和 `Makefile`，重复运行是安全的。

之后读一遍 `icons/icon.env`，确认识别结果，并按品牌设置 `NAME`、`THEME_COLOR`、`BG_COLOR`；如果有 og target，还要设置 `SITE_URL`。skill 升级后运行 `init-project.sh --force` 同步项目内的脚本。

**覆盖提醒**：配置了 `IOS_ICONSET_DIR` 或 `ANDROID_RES_DIR` 时，构建会直接写入原生工程。旧文件会备份到 `.icon-build/backup/<时间>/`，但首次构建前仍要告诉用户。

### 3. 准备源文件

| 文件 | 必需 | 用途 |
|---|---|---|
| `icons/source.svg` | 是 | 主图形 |
| `icons/source-small.svg` | 否 | 48px 及以下的简化版（favicon） |
| `icons/source-mono.svg` | 否 | 单色剪影，用于 Android 主题图标、通知图标、iOS Tinted；缺省时由 source.svg 的轮廓自动生成 |
| `icons/source-dark.svg` | 否 | iOS 深色外观专用配色 |

- **用户已提供 SVG**：对照下方设计规范检查。
- **需要你来设计**：在 `icons/drafts/` 下写 2–3 个方向，逐个运行 `make icons-preview SVG=icons/drafts/<名字>.svg`，查看 `.icon-build/preview-<名字>.png` 比较后给用户选择。
- **用户只有位图 Logo**：用 vtracer 或 potrace 矢量化后清理，或按原图重绘成几何 SVG；两种做法都先和用户确认。

### 4. 构建

```bash
make icons                          # 构建 TARGETS 中的全部 target
make icons-web | icons-og | icons-ios | icons-android   # 只构建单个 target
make icons ICON_ARGS="--bg-color #0f172a"                # 临时覆盖参数
```

### 5. 视觉检查（必做，不要跳过）

用 Read 工具逐张查看构建输出末尾列出的预览图。

**`.icon-build/preview.png`（web）**
- 第 1 行白底、第 2 行深色底：16 / 32 / 48 px 原尺寸，接着是同样三个尺寸的像素级放大
- 第 3 行：apple-touch-icon、icon-192、maskable 圆形遮罩、maskable 80% 安全区遮罩

**`.icon-build/preview-native.png`（ios / android）**
- iOS 行：Any、Dark、Tinted（模拟染色后的效果）
- Android 行：自适应圆形、自适应圆角方形、传统 ic_launcher、主题图标（monochrome）、深色状态栏上的通知图标

**`public/og.png`**：直接查看。

检查项与修正方式：

| 问题 | 修正 |
|---|---|
| 16px 糊、细节丢失 | 新建 `source-small.svg`（去掉次要细节，线条加粗到 ≥ 48） |
| 深色背景（标签栏、iOS Dark）对比度不足 | 调整颜色，或提供 `source-dark.svg` / `IOS_DARK_BG` |
| monochrome、通知图标、Tinted 成了一团实心块 | 提供 `source-mono.svg`，用镂空表达内部结构 |
| 边距过大或过小，或被遮罩裁切 | 调整 `APPLE_SCALE`、`MASKABLE_SCALE`、`ANDROID_FG_SCALE` |
| OG 文字溢出、折行难看、方块字（□） | 见 `references/og.md` |

每次修改后重新构建并再看一次。迭代到满意（或约 3 轮）后，把预览结果和剩余问题如实告诉用户。

### 6. 接入

- **web / og**：读取 `.icon-build/head-snippet.html` 插入 `<head>`。插入前先移除旧的 icon、manifest、theme-color、og:image、twitter:image 标签。链接里的 `?v=<hash>` 用来刷新浏览器缓存，保留即可。
- **ios / android**：按 `references/native.md` 中对应框架的清单检查工程配置。

| 框架 | OUT | head 接入位置 |
|---|---|---|
| Vite / React / Vue / 纯 HTML | `public` | `index.html` |
| Next.js App Router | `public` | `app/layout.tsx` 的 `metadata`（icons、manifest、openGraph），`themeColor` 放在 `viewport` 导出中；删除默认的 `app/favicon.ico` |
| Nuxt | `public` | `nuxt.config` 的 `app.head` |
| SvelteKit | `static` | `src/app.html` |
| Astro | `public` | 布局组件 `<head>` |
| Hugo | `static` | head partial |
| Flutter web | `web` | `web/index.html`（manifest.json 会被自动更新） |

### 7. 验证与收尾

- 运行 `make icons-check`，必须通过。它按 target 比较源文件和设置的哈希，不依赖时间戳，在全新 clone 的 CI 环境里也可靠；建议加入 CI 或 pre-commit。
- 告诉用户哪些文件应提交：`icons/` 下的源文件、`icon.env`、`.icon-stamp`，以及生成的图标、manifest 和原生资源。`.icon-build/` 已被 gitignore。

## SVG 设计规范

- **画布**：正方形 viewBox，推荐 `0 0 512 512`，四周留约 5–8% 边距。
- **笔画粗细**：在 512 网格上，线宽和最小图形 ≥ 32（在 16px 下约 1 像素）。
- **文字**：一律转成路径（`<text>` 依赖本机字体，脚本检测到会警告）。
- **禁用项**：不引用外部图片；颜色不超过 3 种；避免细微渐变、阴影和滤镜。
- **背景**：默认透明。若设计自带底色（例如圆角方块），把 `APPLE_SCALE`、`MASKABLE_SCALE` 设为 1.0，并把关键图形保持在中央 80% 内。
- **iOS 圆角与阴影**：不要自己画圆角或阴影。系统会加遮罩（iOS 26 还会自动加 Liquid Glass 效果），自带圆角会出现"图中图"。
- **单色剪影**：必须能只靠形状辨认，内部结构用镂空（透明）表达，不能靠颜色区分。

## 命令速查

```bash
make icons / icons-web / icons-og / icons-ios / icons-android
make icons-preview SVG=icons/drafts/a.svg    # 只预览草稿，不写入输出
make icons-check                             # CI 用
make icons-clean                             # 删除生成物（manifest、备份和真实原生目录保留）
make icons-deps
bash scripts/build-icons.sh --help
bash scripts/build-icons.sh --print-og-template > icons/og-template.svg
```

## 注意事项

- 生成物不要手动编辑；需要改动时修改源文件或 `icon.env`，然后重新构建。
- `icon.env` 会被 shell 直接 source 执行，只写 `KEY="value"` 形式的赋值。
- 相同输入重复构建不会产生新的备份；只有内容真正改变的原生文件才会被备份。
