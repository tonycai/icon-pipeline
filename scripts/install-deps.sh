#!/usr/bin/env bash
# install-deps.sh — install the icon-pipeline toolchain (all open source).
#
#   macOS          : Homebrew
#   Ubuntu/Debian  : apt for ImageMagick / rsvg-convert / jq / CJK fonts,
#                    prebuilt resvg + oxipng from GitHub releases into ~/.local/bin (no cargo needed),
#                    svgo via npm into ~/.local (only if npm is present)
#
# Env: BIN=~/.local/bin (install dir)   CJK_FONTS=1 (apt fonts-noto-cjk for OG images, ~60 MB)
set -euo pipefail

BIN="${BIN:-$HOME/.local/bin}"
CJK_FONTS="${CJK_FONTS:-1}"
say()  { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ "$(uname -s)" == "Darwin" ]]; then
  have brew || { echo "Homebrew not found: https://brew.sh" >&2; exit 1; }
  say "brew install resvg imagemagick oxipng jq svgo"
  brew install resvg imagemagick oxipng jq svgo
  note "OG images: macOS fonts work; for reproducible output set OG_FONT_FILE to a Noto Sans CJK / Source Han Sans file"
  exit 0
fi

have apt-get || { echo "unsupported system: need Homebrew (macOS) or apt (Ubuntu/Debian)" >&2; exit 1; }
SUDO=""; if [[ "$(id -u)" -ne 0 ]]; then SUDO="sudo"; fi
arch=$(uname -m)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$BIN"
export PATH="$BIN:$PATH"

latest_tag() {  # owner/repo -> vX.Y.Z, via the release redirect (no GitHub API rate limit)
  curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/tag/||'
}

pkgs="imagemagick librsvg2-bin jq curl"
if [[ "$CJK_FONTS" == "1" ]]; then pkgs="$pkgs fonts-noto-cjk"; fi
say "apt: $pkgs"
$SUDO apt-get update -qq
# shellcheck disable=SC2086
$SUDO apt-get install -y -qq $pkgs >/dev/null

say "resvg (preferred renderer)"
if have resvg; then note "already installed: resvg $(resvg --version)"
elif [[ "$arch" == "x86_64" ]]; then
  curl -fsSL -o "$tmp/resvg.tgz" https://github.com/linebender/resvg/releases/latest/download/resvg-linux-x86_64.tar.gz
  tar -xzf "$tmp/resvg.tgz" -C "$tmp"
  install -m 755 "$tmp/resvg" "$BIN/resvg"
  note "installed: $BIN/resvg $("$BIN/resvg" --version)"
else
  note "no prebuilt resvg for $arch — skipped; rsvg-convert will be used (fine for everything except OG_FONT_FILE)"
  note "to build it anyway: curl https://sh.rustup.rs -sSf | sh && cargo install resvg"
fi

say "oxipng (lossless PNG optimizer)"
if have oxipng; then note "already installed: $(oxipng --version)"
elif [[ "$arch" == "x86_64" || "$arch" == "aarch64" ]]; then
  tag=$(latest_tag shssoichiro/oxipng); name="oxipng-${tag#v}-$arch-unknown-linux-musl"
  curl -fsSL -o "$tmp/oxipng.tgz" "https://github.com/shssoichiro/oxipng/releases/download/$tag/$name.tar.gz"
  tar -xzf "$tmp/oxipng.tgz" -C "$tmp"
  install -m 755 "$tmp/$name/oxipng" "$BIN/oxipng"
  note "installed: $BIN/oxipng ($("$BIN/oxipng" --version))"
else
  note "no prebuilt oxipng for $arch — skipped (PNGs will not be optimized)"
fi

say "svgo (optional SVG minifier)"
if have svgo; then note "already installed: svgo $(svgo --version)"
elif have npm; then
  npm install -g svgo --prefix "$HOME/.local" --silent
  note "installed: svgo $(svgo --version)"
else
  note "npm not found — skipped (icon.svg is copied unminified; install Node.js to enable)"
fi

case ":$(printf '%s' "${PATH#"$BIN:"}"):" in
  *":$BIN:"*) ;;
  *) echo
     echo "!! $BIN is not on your PATH yet. Add it:"
     echo "   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc" ;;
esac

here="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$here/build-icons.sh" ]]; then echo; bash "$here/build-icons.sh" --deps || true; fi
