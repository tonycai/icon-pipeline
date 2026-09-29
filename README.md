English | [简体中文](README.zh-CN.md)

# icon-pipeline

Generate every icon a product needs from a single `source.svg` with one command, packaged as a Claude Code skill. The toolchain is entirely open source.

| Target | Output |
|---|---|
| `web` | favicon.ico, icon.svg, apple-touch-icon, PNG set, PWA maskable icons, manifest |
| `og` | og.png social share image (1200×630, CJK text supported) plus meta tags |
| `ios` | AppIcon.appiconset (single-size 1024, Any / Dark / Tinted) |
| `android` | Adaptive icon (with monochrome), legacy and round launchers, notification icon, Play Store 512, 1024 layers for Expo |

## Installation

Pick one of the following to put the skill at `~/.claude/skills/icon-pipeline`.

**Option 1: git clone into the skills directory** (upgrade later with `git pull`)

```bash
git clone https://github.com/tonycai/icon-pipeline.git ~/.claude/skills/icon-pipeline
```

**Option 2: clone anywhere, then symlink into the skills directory** (handy if you keep repos in your own workspace)

```bash
git clone https://github.com/tonycai/icon-pipeline.git ~/workspace/icon-pipeline   # any directory works
mkdir -p ~/.claude/skills
ln -s ~/workspace/icon-pipeline ~/.claude/skills/icon-pipeline
```

**Option 3: download the zip** (from the [Releases](https://github.com/tonycai/icon-pipeline/releases) page)

```bash
mkdir -p ~/.claude/skills
unzip icon-pipeline-v2.0.0.zip -d ~/.claude/skills/
chmod +x ~/.claude/skills/icon-pipeline/scripts/*.sh
```

Then install the toolchain and check it:

```bash
brew install resvg imagemagick oxipng jq svgo                  # macOS
# Ubuntu: sudo apt install imagemagick jq librsvg2-bin && cargo install resvg oxipng && npm i -g svgo

bash ~/.claude/skills/icon-pipeline/scripts/build-icons.sh --deps
```

If your OG image contains Chinese or Japanese text, download Noto Sans CJK or Source Han Sans (SIL OFL licensed) and point `OG_FONT_FILE` in `icons/icon.env` at it.

## Using it in Claude Code

Just describe what you need in plain language, e.g. "make an icon set for this project", "add iOS and Android icons" or "make a social share image", and Claude loads the skill automatically. You can also type `/icon-pipeline`.

## Using it without Claude

```bash
cd your-project
bash ~/.claude/skills/icon-pipeline/scripts/init-project.sh   # auto-detects web / iOS / Android / Expo
make icons            # or build just one part: make icons-web / icons-og / icons-ios / icons-android
make icons-check      # fail in CI when icons are out of date
```

## Directory layout

```
icon-pipeline/
├── SKILL.md                 workflow and design rules (read by Claude)
├── references/
│   ├── native.md            iOS / Android integration checklist per framework
│   └── og.md                OG template, fonts, verification
├── scripts/
│   ├── build-icons.sh       the pipeline (bash 3.2 compatible)
│   └── init-project.sh      vendors the pipeline into a project, auto-detects settings
├── templates/
│   ├── icons.mk             make targets
│   └── icon.env             settings template
├── assets/
│   └── example-source.svg   example icon
└── .github/workflows/ci.yml CI: shellcheck + smoke test of every target
```

## License

[MIT](LICENSE)
