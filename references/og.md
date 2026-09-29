# OG 社交分享图参考

## 生成物

- `$OUT/og.png`：1200×630，适用于 Facebook、LinkedIn、X、LINE、Slack、Discord、微信等平台的链接预览。
- `.icon-build/og.svg`：替换占位符后的中间 SVG，排查问题时查看。
- head 片段中的标签：`og:image`、`og:image:width`、`og:image:height`、`og:image:alt`、`twitter:card`（summary_large_image）和 `twitter:image`。

`og:title`、`og:description` 和 `og:url` 因页面而异，本流水线不生成，需要在页面模板或框架的 metadata 中设置。

## 关键设置（icons/icon.env）

| 键 | 说明 |
|---|---|
| `SITE_URL` | 站点源地址，如 `https://example.com`。大多数爬虫要求 `og:image` 是绝对 URL，未设置时会警告 |
| `OG_TITLE` | 默认等于 NAME。用 `\n` 手动换行，如 `"第一行\n第二行"`（模板不会自动折行） |
| `OG_SUBTITLE` | 副标题，字号为标题的一半，同样支持 `\n` |
| `OG_TITLE_SIZE` | 标题字号，默认 64 |
| `OG_BG_COLOR` / `OG_TEXT_COLOR` / `OG_MUTED_COLOR` / `OG_ACCENT_COLOR` | 背景、标题、副标题、底部色条的颜色 |
| `OG_FONT` | font-family 列表 |
| `OG_FONT_FILE` | 指定字体文件（需要 resvg），可保证各机器渲染结果一致 |
| `OG_TEMPLATE` | 自定义模板路径，文件存在时启用 |

默认模板的文字区域宽约 680px。按 64px 字号估算，每行大约能放 10 个汉字或假名、20 个左右的拉丁字母。超出时手动加 `\n`，或调小 `OG_TITLE_SIZE`。

## 字体（中文 / 日文）

- 推荐开源字体 Noto Sans CJK 或 Source Han Sans（思源黑体），均为 SIL OFL 授权，可商用。建议放进 `icons/fonts/`，并在 `OG_FONT_FILE` 中指定，这样换机器、上 CI 结果都一样。
- 同一个汉字在日文字形（JP）和简体中文字形（SC）中写法不同，比如「骨」「直」。面向日本用户的产品用 JP 版字体，面向中国用户的用 SC 版。
- 渲染器报告找不到字体时会警告，此时图中可能出现方块字（□）。解决方法是安装上述字体或设置 `OG_FONT_FILE`。
- macOS 系统字体（PingFang、Hiragino）也能渲染，但它们的授权并不面向"把字形嵌入图片后再发布"的用途。商用场景优先使用 OFL 字体。

## 自定义模板

```bash
bash scripts/build-icons.sh --print-og-template > icons/og-template.svg
```

占位符：

| 占位符 | 替换为 |
|---|---|
| `{{BG}}` `{{TEXT}}` `{{MUTED}}` `{{ACCENT}}` | 对应颜色 |
| `{{FONT}}` | OG_FONT |
| `{{ICON}}` | source.svg 渲染成的 512px PNG（data URI），用于 `<image href="{{ICON}}">` |
| `{{TEXT_BLOCK}}` | 标题加副标题的 `<text>` 元素，以 y=0 为中心垂直居中，x=0 左对齐 |

用 `<g transform="translate(X,Y)">` 放置 `{{TEXT_BLOCK}}`；需要居中对齐时，在 `<g>` 上加 `text-anchor="middle"`。

模板中可以直接写品牌元素（背景图形、网址等），但不要引用外部图片，否则渲染器取不到。

## 视觉检查要点

1. 标题没有溢出右边界，折行位置自然（不要把一个词拆开）。
2. 文字与背景对比度足够。深色背景要同时改 `OG_TEXT_COLOR` 和 `OG_MUTED_COLOR`。
3. 不同平台会裁切：X 和 LINE 的小卡片可能只显示中间部分。关键内容放在中央，四周各留约 60px。
4. 没有方块字。

## 上线后验证

- 各平台的分享调试工具（如 Facebook Sharing Debugger、LinkedIn Post Inspector）可以抓取页面并刷新缓存。
- 平台缓存很顽固。head 片段里的 `?v=<hash>` 会在图片变化时自动改变 URL，从而触发重新抓取。

## 范围之外

本流水线生成的是全站默认 OG 图。博客文章等"每页一张"的动态 OG 图，建议在应用内按页生成（例如各框架的 OG 图片路由），可以复用本流水线产出的图标和配色。
