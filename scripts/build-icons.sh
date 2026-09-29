#!/usr/bin/env bash
# build-icons.sh — one SVG in, every icon a product needs out.
#
# Targets (TARGETS="web og ios android", any subset):
#   web      favicon.ico, icon.svg, apple-touch-icon.png, PNG set, PWA maskable, web manifest
#   og       og.png (1200x630) social share image from an SVG template
#   ios      AppIcon.appiconset: single-size 1024 with Any / Dark / Tinted appearances (Xcode 16+)
#   android  adaptive icon (foreground + background + monochrome), legacy + round launchers,
#            notification icon, Play Store 512, 1024 layers for Expo
#
# Open-source toolchain:
#   required : resvg | rsvg-convert | inkscape  (SVG -> PNG), ImageMagick
#   optional : svgo (SVG minify), oxipng (lossless PNG), jq (merge existing manifest)
#
# Compatible with bash 3.2 (macOS default) and newer.
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true   # bash 5.2+: keep '&' literal in ${var//x/y}

readonly VERSION="2.0.0"
PROG="${0##*/}"
readonly PROG

# ---------------------------------------------------------------- defaults
# Precedence: defaults < config file (icons/icon.env) < command-line flags
TARGETS="web"
SRC="icons/source.svg"
SRC_SMALL="icons/source-small.svg"   # optional: simplified artwork for <= SMALL_MAX px
SRC_MONO="icons/source-mono.svg"     # optional: single-colour silhouette (Android themed, iOS tinted, notification)
SRC_DARK="icons/source-dark.svg"     # optional: artwork variant for the iOS dark icon
SMALL_MAX="48"
OUT="public"
ICON_DIR="icons"
PUBLIC_PATH="/"
MANIFEST="manifest.webmanifest"
NAME="My App"
SHORT_NAME=""
THEME_COLOR="#ffffff"
BG_COLOR="#ffffff"
APPLE_SCALE="0.8"
MASKABLE_SCALE="0.7"
PNG_SIZES="16 32 48 64 128 192 256 512 1024"
CACHE_BUST="1"
NATIVE_OUT="icons/native"
IOS_ICONSET_DIR=""
IOS_DARK_BG="#000000"
IOS_APPEARANCES="1"
ANDROID_RES_DIR=""
ANDROID_FG_SCALE="0.54"
ANDROID_MONOCHROME="1"
ANDROID_NOTIFICATION="1"
SITE_URL=""
OG_TITLE=""
OG_SUBTITLE=""
OG_BG_COLOR=""
OG_TEXT_COLOR="#111827"
OG_MUTED_COLOR="#4b5563"
OG_ACCENT_COLOR=""
OG_FONT="Noto Sans CJK SC, Noto Sans CJK JP, Source Han Sans SC, PingFang SC, Hiragino Sans, sans-serif"
OG_FONT_FILE=""
OG_TITLE_SIZE="64"
OG_TEMPLATE="icons/og-template.svg"
BUILD_DIR=".icon-build"
OPTIMIZE_SVG="1"
OPTIMIZE_PNG="1"
UPDATE_MANIFEST="1"
CONFIG="${ICON_CONFIG:-icons/icon.env}"
MODE="build"                         # build | check | deps | clean | preview | print-og-template

CONFIG_KEYS="TARGETS SRC SRC_SMALL SRC_MONO SRC_DARK SMALL_MAX OUT ICON_DIR PUBLIC_PATH MANIFEST NAME \
SHORT_NAME THEME_COLOR BG_COLOR APPLE_SCALE MASKABLE_SCALE PNG_SIZES CACHE_BUST NATIVE_OUT IOS_ICONSET_DIR \
IOS_DARK_BG IOS_APPEARANCES ANDROID_RES_DIR ANDROID_FG_SCALE ANDROID_MONOCHROME ANDROID_NOTIFICATION SITE_URL \
OG_TITLE OG_SUBTITLE OG_BG_COLOR OG_TEXT_COLOR OG_MUTED_COLOR OG_ACCENT_COLOR OG_FONT OG_FONT_FILE \
OG_TITLE_SIZE OG_TEMPLATE BUILD_DIR OPTIMIZE_SVG OPTIMIZE_PNG UPDATE_MANIFEST"
ALL_TARGETS="web og ios android"

# ---------------------------------------------------------------- output helpers
if [[ -t 1 ]]; then
  C_B=$'\033[1m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_D=$'\033[2m'; C_0=$'\033[0m'
else
  C_B=""; C_G=""; C_Y=""; C_R=""; C_D=""; C_0=""
fi
info() { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%s✗ %s%s\n' "$C_R" "$*" "$C_0" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
has_target() { case " $TARGETS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

usage() {
  cat <<EOF
$PROG $VERSION — build every icon a product needs from one SVG

Usage: $PROG [options]

Modes (default: build):
  --check              exit 1 if outputs of TARGETS are missing or out of date (CI / pre-commit)
  --preview-only       render $BUILD_DIR/preview-<name>.png for --src without writing outputs
  --deps               show toolchain status and install hints
  --clean              remove generated files of TARGETS (manifest and real native dirs are kept)
  --print-og-template  print the built-in OG SVG template (to customise as icons/og-template.svg)

Options:
  --config FILE        config file to source (default: icons/icon.env, env ICON_CONFIG)
  --targets "LIST"     any of: $ALL_TARGETS   (default from config: $TARGETS)
  --src FILE           master SVG (default: $SRC)
  --src-small FILE     simplified SVG for <= ${SMALL_MAX}px (used if present)
  --src-mono FILE      single-colour silhouette SVG (used if present)
  --src-dark FILE      iOS dark-appearance artwork (used if present)
  --out DIR            web root to write into (default: $OUT)
  --icon-dir DIR       PNG subdir inside --out (default: $ICON_DIR)
  --public-path PATH   URL prefix of --out (default: $PUBLIC_PATH)
  --site-url URL       absolute origin for og:image, e.g. https://example.com
  --name TEXT          app name (new manifest, default OG title)
  --theme-color HEX    theme colour
  --bg-color HEX       background for opaque icons (apple-touch, maskable, iOS, Android)
  --og-title TEXT      OG title; use \\n for line breaks
  --og-subtitle TEXT   OG subtitle
  --ios-iconset-dir D  write straight into an Xcode AppIcon.appiconset (old files backed up)
  --android-res-dir D  write straight into an Android res/ dir (overwritten files backed up)
  --no-svgo | --no-oxipng | --no-manifest
  -h, --help | -V, --version

All other settings (scales, colours, fonts, sizes) live in icons/icon.env.
EOF
}

# ---------------------------------------------------------------- argument parsing
setflag() { printf -v "F_$1" '%s' "$2"; }
need_arg() { [[ $# -ge 2 ]] || die "option $1 requires a value"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)             MODE="check"; shift ;;
    --preview-only)      MODE="preview"; shift ;;
    --deps)              MODE="deps"; shift ;;
    --clean)             MODE="clean"; shift ;;
    --print-og-template) MODE="print-og-template"; shift ;;
    --config)            need_arg "$@"; CONFIG="$2"; shift 2 ;;
    --targets)           need_arg "$@"; setflag TARGETS "$2"; shift 2 ;;
    --src)               need_arg "$@"; setflag SRC "$2"; shift 2 ;;
    --src-small)         need_arg "$@"; setflag SRC_SMALL "$2"; shift 2 ;;
    --src-mono)          need_arg "$@"; setflag SRC_MONO "$2"; shift 2 ;;
    --src-dark)          need_arg "$@"; setflag SRC_DARK "$2"; shift 2 ;;
    --out)               need_arg "$@"; setflag OUT "$2"; shift 2 ;;
    --icon-dir)          need_arg "$@"; setflag ICON_DIR "$2"; shift 2 ;;
    --public-path)       need_arg "$@"; setflag PUBLIC_PATH "$2"; shift 2 ;;
    --site-url)          need_arg "$@"; setflag SITE_URL "$2"; shift 2 ;;
    --name)              need_arg "$@"; setflag NAME "$2"; shift 2 ;;
    --theme-color)       need_arg "$@"; setflag THEME_COLOR "$2"; shift 2 ;;
    --bg-color)          need_arg "$@"; setflag BG_COLOR "$2"; shift 2 ;;
    --og-title)          need_arg "$@"; setflag OG_TITLE "$2"; shift 2 ;;
    --og-subtitle)       need_arg "$@"; setflag OG_SUBTITLE "$2"; shift 2 ;;
    --ios-iconset-dir)   need_arg "$@"; setflag IOS_ICONSET_DIR "$2"; shift 2 ;;
    --android-res-dir)   need_arg "$@"; setflag ANDROID_RES_DIR "$2"; shift 2 ;;
    --no-svgo)           setflag OPTIMIZE_SVG 0; shift ;;
    --no-oxipng)         setflag OPTIMIZE_PNG 0; shift ;;
    --no-manifest)       setflag UPDATE_MANIFEST 0; shift ;;
    -h|--help)           usage; exit 0 ;;
    -V|--version)        echo "$VERSION"; exit 0 ;;
    *)                   die "unknown option: $1 (see --help)" ;;
  esac
done

if [[ -f "$CONFIG" ]]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi
for k in $CONFIG_KEYS; do
  f="F_$k"
  if declare -p "$f" >/dev/null 2>&1; then printf -v "$k" '%s' "${!f}"; fi
done
[[ -n "$SHORT_NAME" ]]      || SHORT_NAME="$NAME"
[[ -n "$OG_TITLE" ]]        || OG_TITLE="$NAME"
[[ -n "$OG_BG_COLOR" ]]     || OG_BG_COLOR="$BG_COLOR"
[[ -n "$OG_ACCENT_COLOR" ]] || OG_ACCENT_COLOR="$THEME_COLOR"
# shellcheck disable=SC2086,SC2116
TARGETS=$(echo $TARGETS)   # normalise whitespace
for t in $TARGETS; do
  case " $ALL_TARGETS " in *" $t "*) ;; *) die "unknown target '$t' (valid: $ALL_TARGETS)" ;; esac
done
ICON_SUB="${ICON_DIR:+${ICON_DIR%/}/}"
URL_BASE="${PUBLIC_PATH%/}"
ICON_OUT="${OUT%/}${ICON_SUB:+/${ICON_SUB%/}}"
IOS_DIR="${IOS_ICONSET_DIR:-$NATIVE_OUT/ios/AppIcon.appiconset}"
ANDROID_STAGE="$NATIVE_OUT/android"
ANDROID_RES="${ANDROID_RES_DIR:-$ANDROID_STAGE/res}"
DENSITIES="mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4"

# ---------------------------------------------------------------- toolchain
RENDERER=""; IM=""; SVGO=""; OXIPNG=""; JQ=""
detect_tools() {
  local r
  for r in resvg rsvg-convert inkscape; do
    if have "$r"; then RENDERER="$r"; break; fi
  done
  if have magick; then IM="magick"
  elif have convert && convert -version 2>/dev/null | grep -q ImageMagick; then IM="convert"
  fi
  if have svgo; then SVGO="svgo"; fi
  if have oxipng; then OXIPNG="oxipng"; fi
  if have jq; then JQ="jq"; fi
  return 0
}

install_hints() {
  cat <<'EOF'
Install (all open source) — easiest, macOS or Ubuntu/Debian, no cargo needed:
  bash ~/.claude/skills/icon-pipeline/scripts/install-deps.sh
Manual:
  macOS   : brew install resvg imagemagick oxipng jq svgo
  Ubuntu  : sudo apt install imagemagick librsvg2-bin jq fonts-noto-cjk
            resvg / oxipng: prebuilt binaries from their GitHub releases (install-deps.sh does this)
            svgo (optional): npm i -g svgo
  OG fonts: Noto Sans CJK / Source Han Sans (SIL OFL) — set OG_FONT_FILE for reproducible output
EOF
}

require_tools() {
  [[ -n "$RENDERER" ]] || { install_hints >&2; die "no SVG renderer found (need resvg, rsvg-convert or inkscape)"; }
  [[ -n "$IM" ]]       || { install_hints >&2; die "ImageMagick not found (need 'magick' or 'convert')"; }
  return 0
}

deps() {
  detect_tools
  local status=0
  info "Toolchain status"
  if [[ -n "$RENDERER" ]]; then ok "renderer   : $RENDERER"; else warn "renderer   : MISSING (resvg / rsvg-convert / inkscape)"; status=1; fi
  if [[ -n "$IM" ]];       then ok "imagemagick: $IM";       else warn "imagemagick: MISSING"; status=1; fi
  if [[ -n "$SVGO" ]];     then ok "svgo       : yes";       else warn "svgo       : not found (icon.svg copied unminified)"; fi
  if [[ -n "$OXIPNG" ]];   then ok "oxipng     : yes";       else warn "oxipng     : not found (PNGs not optimized)"; fi
  if [[ -n "$JQ" ]];       then ok "jq         : yes";       else warn "jq         : not found (existing manifests are not merged)"; fi
  [[ "$RENDERER" == "resvg" ]] || printf '  %sresvg is the recommended renderer (most accurate; needed for OG_FONT_FILE)%s\n' "$C_D" "$C_0"
  echo; install_hints
  return "$status"
}

# ---------------------------------------------------------------- SVG helpers
svg_viewbox_wh() {  # prints "W H" of the first viewBox, nothing if absent
  local vb
  vb=$(tr '\n\r\t' '   ' < "$1" | grep -oE "viewBox=[\"'][^\"']*[\"']" | head -1 \
       | sed -E "s/^viewBox=[\"']//; s/[\"']\$//" | tr ',' ' ') || true
  if [[ -n "$vb" ]]; then echo "$vb" | awk '{print $3, $4}'; fi
}

validate_svg() {
  local f="$1" wh w h
  [[ -f "$f" ]] || die "source not found: $f"
  grep -q '<svg' "$f" || die "not an SVG file: $f"
  wh=$(svg_viewbox_wh "$f")
  if [[ -z "$wh" ]]; then
    warn "$f: no viewBox — add one (e.g. viewBox=\"0 0 512 512\") so it scales correctly"
  else
    read -r w h <<<"$wh"
    if ! awk -v w="$w" -v h="$h" 'BEGIN { d = w - h; if (d < 0) d = -d; exit !(d <= w * 0.001) }'; then
      warn "$f: viewBox is ${w}x${h}; icons should be square (artwork will be distorted)"
    fi
  fi
  if grep -q '<text' "$f"; then
    warn "$f: contains <text> — convert text to paths (fonts differ across machines/renderers)"
  fi
  if grep -qE "<image[^>]*href=[\"'](https?:|/)" "$f"; then
    warn "$f: external <image> reference — embed it or remove it"
  fi
  return 0
}

xml_escape() {
  local s="$1"
  s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; s=${s//\"/&quot;}
  printf '%s' "$s"
}
json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

# ---------------------------------------------------------------- rendering primitives
TMPN=0
tmpfile() { TMPN=$((TMPN + 1)); echo "$TMP/t$TMPN.$1"; }

render_wh() {  # render_wh SVG W H OUT.png [extra renderer args...]
  local svg="$1" w="$2" h="$3" out="$4"; shift 4
  case "$RENDERER" in
    resvg)        resvg -w "$w" -h "$h" "$@" "$svg" "$out" ;;
    rsvg-convert) rsvg-convert -w "$w" -h "$h" -o "$out" "$svg" ;;
    inkscape)     inkscape "$svg" --export-type=png --export-width="$w" \
                    --export-height="$h" --export-filename="$out" >/dev/null 2>&1 ;;
  esac
}
render() { render_wh "$1" "$2" "$2" "$3"; }

scaled() { awk -v s="$1" -v k="$2" 'BEGIN { v = int(s * k + 0.5); if (v > s) v = s; if (v < 1) v = 1; print v }'; }

# place SVG SIZE SCALE BG OUT [RECOLOR]
#   Renders artwork at SIZE*SCALE centred on a SIZExSIZE canvas.
#   BG "none" keeps transparency; any colour produces an opaque RGB image (no alpha channel).
#   RECOLOR turns the artwork into a flat silhouette of that colour (alpha preserved).
place() {
  local svg="$1" size="$2" scale="$3" bg="$4" out="$5" color="${6:-}" art
  art=$(tmpfile png)
  render "$svg" "$(scaled "$size" "$scale")" "$art"
  if [[ -n "$color" ]]; then "$IM" "$art" -fill "$color" -colorize 100 "$art"; fi
  if [[ "$bg" == "none" ]]; then
    "$IM" -size "${size}x${size}" xc:none "$art" -gravity center -composite "$out"
  else
    "$IM" -size "${size}x${size}" "xc:$bg" "$art" -gravity center -composite -alpha off "$out"
  fi
}

mask() {  # mask IN SIZE circle|round:RADIUS OUT   (resize, then clip)
  local in="$1" s="$2" shape="$3" out="$4" c draw
  c=$(awk -v s="$s" 'BEGIN { printf "%.1f", (s - 1) / 2 }')
  case "$shape" in
    circle)  draw="circle $c,$c $c,0.5" ;;
    round:*) draw="roundrectangle 0,0 $((s - 1)),$((s - 1)) ${shape#round:},${shape#round:}" ;;
  esac
  "$IM" "$in" -resize "${s}x${s}" \( -size "${s}x${s}" xc:black -fill white -draw "$draw" \) \
    -alpha off -compose CopyOpacity -composite "$out"
}

small_or_main() {
  if [[ -n "$SMALL_FILE" && "$1" -le "$SMALL_MAX" ]]; then echo "$SMALL_FILE"; else echo "$SRC"; fi
}

normalized_sizes() {
  local s
  for s in $PNG_SIZES 192 512; do
    [[ "$s" =~ ^[0-9]+$ ]] || die "invalid size in PNG_SIZES: '$s'"
    echo "$s"
  done | sort -n | uniq | tr '\n' ' '
}

track_png() { printf '%s\n' "$@" >> "$TMP/pngs.txt"; }

# install NEW DEST — move a finished temp file into place; when writing into a real
# native project dir, keep a copy of any file that is about to change.
BACKUP_ROOT=""
install_out() {
  local new="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  # optimise before comparing, so an identical rebuild is recognised as "unchanged"
  if [[ "$new" == *.png && "$OPTIMIZE_PNG" == "1" && -n "$OXIPNG" ]]; then
    oxipng -o 4 --strip safe -q "$new" 2>/dev/null || true
  fi
  if [[ -n "$BACKUP_ROOT" && -f "$dest" ]] && ! cmp -s "$new" "$dest"; then
    mkdir -p "$BACKUP_ROOT/$(dirname "$dest")"
    cp "$dest" "$BACKUP_ROOT/$dest"
    BACKED_UP=1
  fi
  mv "$new" "$dest"
}

# ---------------------------------------------------------------- hashing / stamps
sha256() { if have sha256sum; then sha256sum | awk '{print $1}'; else shasum -a 256 | awk '{print $1}'; fi; }

input_hash() {
  local k f
  {
    for f in "$SRC" "$SRC_SMALL" "$SRC_MONO" "$SRC_DARK" "$OG_TEMPLATE"; do
      if [[ -f "$f" ]]; then printf '== %s\n' "$f"; cat "$f"; fi
    done
    echo "$VERSION"
    for k in $CONFIG_KEYS; do
      [[ "$k" == "TARGETS" ]] || printf '%s=%s\n' "$k" "${!k}"
    done
  } | sha256
}

stamp_file() { echo "$(dirname "$SRC")/.icon-stamp"; }

update_stamp() {  # update_stamp "targets built"
  local f h t pat
  f=$(stamp_file); h=$(input_hash); pat=$(echo "$1" | sed 's/ *$//; s/ /|/g')
  {
    if [[ -f "$f" ]]; then grep -E '^[a-z]+ ' "$f" | grep -vE "^($pat) " || true; fi   # drops v1 single-hash lines
    for t in $1; do echo "$t $h"; done
  } > "$TMP/stamp"
  cat "$TMP/stamp" > "$f"
}

# ---------------------------------------------------------------- expected outputs
outputs_web() {
  local s
  echo "$OUT/favicon.ico"; echo "$OUT/icon.svg"; echo "$OUT/apple-touch-icon.png"
  for s in $(normalized_sizes); do echo "$ICON_OUT/icon-$s.png"; done
  echo "$ICON_OUT/icon-maskable-192.png"; echo "$ICON_OUT/icon-maskable-512.png"
}
outputs_og() { echo "$OUT/og.png"; }
outputs_ios() {
  echo "$IOS_DIR/Contents.json"; echo "$IOS_DIR/AppIcon.png"
  if [[ "$IOS_APPEARANCES" == "1" ]]; then echo "$IOS_DIR/AppIcon-Dark.png"; echo "$IOS_DIR/AppIcon-Tinted.png"; fi
}
outputs_android_res() {
  local d
  for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
    echo "$ANDROID_RES/mipmap-$d/ic_launcher.png"
    echo "$ANDROID_RES/mipmap-$d/ic_launcher_round.png"
    echo "$ANDROID_RES/mipmap-$d/ic_launcher_foreground.png"
    if [[ "$ANDROID_MONOCHROME" == "1" ]]; then echo "$ANDROID_RES/mipmap-$d/ic_launcher_monochrome.png"; fi
    if [[ "$ANDROID_NOTIFICATION" == "1" ]]; then echo "$ANDROID_RES/drawable-$d/ic_stat_notification.png"; fi
  done
  echo "$ANDROID_RES/mipmap-anydpi-v26/ic_launcher.xml"
  echo "$ANDROID_RES/mipmap-anydpi-v26/ic_launcher_round.xml"
  echo "$ANDROID_RES/values/ic_launcher_background.xml"
}
outputs_android_stage() {
  echo "$ANDROID_STAGE/play-store-512.png"
  echo "$ANDROID_STAGE/adaptive-foreground-1024.png"
  if [[ "$ANDROID_MONOCHROME" == "1" ]]; then echo "$ANDROID_STAGE/adaptive-monochrome-1024.png"; fi
}
outputs_android() { outputs_android_res; outputs_android_stage; }

# ---------------------------------------------------------------- optimization
optimize_svg() {  # optimize_svg IN OUT
  local in="$1" out="$2"
  if [[ "$OPTIMIZE_SVG" == "1" && -n "$SVGO" ]]; then
    if svgo --multipass -q -i "$in" -o "$out" >/dev/null 2>&1; then
      if [[ -z "$(svg_viewbox_wh "$in")" || -n "$(svg_viewbox_wh "$out")" ]]; then
        ok "icon.svg ($(wc -c < "$in" | tr -d ' ') → $(wc -c < "$out" | tr -d ' ') bytes, svgo)"
        return 0
      fi
      warn "svgo removed viewBox; using unminified SVG"
    else
      warn "svgo failed; using unminified SVG"
    fi
  fi
  cp "$in" "$out"
  ok "icon.svg (copied)"
}

optimize_pngs() {
  [[ "$OPTIMIZE_PNG" == "1" && -n "$OXIPNG" && -s "$TMP/pngs.txt" ]] || return 0
  if tr '\n' '\0' < "$TMP/pngs.txt" | xargs -0 oxipng -o 4 --strip safe -q; then
    ok "PNGs optimized (oxipng, $(wc -l < "$TMP/pngs.txt" | tr -d ' ') files)"
  else
    warn "oxipng failed; some PNGs left unoptimized"
  fi
}

# ---------------------------------------------------------------- target: web
icons_json() {
  local p="$URL_BASE/$ICON_SUB"
  cat <<EOF
[
  { "src": "${p}icon-192.png", "sizes": "192x192", "type": "image/png" },
  { "src": "${p}icon-512.png", "sizes": "512x512", "type": "image/png" },
  { "src": "${p}icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
  { "src": "${p}icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
]
EOF
}

update_manifest() {
  [[ "$UPDATE_MANIFEST" == "1" ]] || return 0
  local mf="$OUT/$MANIFEST" icons
  icons=$(icons_json)
  if [[ -f "$mf" ]]; then
    if [[ -n "$JQ" ]]; then
      jq --argjson icons "$icons" --arg tc "$THEME_COLOR" --arg bg "$BG_COLOR" \
        '.icons = $icons | .theme_color //= $tc | .background_color //= $bg' "$mf" > "$TMP/manifest.json" \
        || die "could not parse $mf as JSON"
      cat "$TMP/manifest.json" > "$mf"
      ok "$MANIFEST: icons[] updated, other fields kept"
    else
      printf '%s\n' "$icons" > "$BUILD_DIR/manifest-icons.json"
      warn "jq not found: $mf left unchanged — merge $BUILD_DIR/manifest-icons.json into its \"icons\" field"
    fi
  else
    cat > "$mf" <<EOF
{
  "name": "$(json_escape "$NAME")",
  "short_name": "$(json_escape "$SHORT_NAME")",
  "start_url": "${URL_BASE}/",
  "display": "standalone",
  "theme_color": "$(json_escape "$THEME_COLOR")",
  "background_color": "$(json_escape "$BG_COLOR")",
  "icons": $(icons_json | sed '1!s/^/  /')
}
EOF
    ok "$MANIFEST created"
  fi
}

build_web() {
  local s
  mkdir -p "$OUT" "$ICON_OUT"
  for s in $(normalized_sizes); do
    render "$(small_or_main "$s")" "$s" "$ICON_OUT/icon-$s.png"
    track_png "$ICON_OUT/icon-$s.png"
  done
  ok "PNG set: $(normalized_sizes | sed 's/ *$//; s/ /, /g') px → $ICON_OUT/"

  for s in 16 32 48; do render "$(small_or_main "$s")" "$s" "$TMP/ico-$s.png"; done
  "$IM" "$TMP/ico-16.png" "$TMP/ico-32.png" "$TMP/ico-48.png" "$OUT/favicon.ico"
  ok "favicon.ico (16, 32, 48)"

  optimize_svg "${SMALL_FILE:-$SRC}" "$OUT/icon.svg"

  place "$SRC" 180 "$APPLE_SCALE" "$BG_COLOR" "$OUT/apple-touch-icon.png"
  track_png "$OUT/apple-touch-icon.png"
  ok "apple-touch-icon.png (180, scale $APPLE_SCALE on $BG_COLOR)"

  for s in 192 512; do
    place "$SRC" "$s" "$MASKABLE_SCALE" "$BG_COLOR" "$ICON_OUT/icon-maskable-$s.png"
    track_png "$ICON_OUT/icon-maskable-$s.png"
  done
  ok "maskable icons (192, 512, scale $MASKABLE_SCALE on $BG_COLOR)"

  update_manifest
  make_preview_web "$TMP/ico-16.png" "$TMP/ico-32.png" "$TMP/ico-48.png" "$OUT/apple-touch-icon.png" \
    "$ICON_OUT/icon-192.png" "$ICON_OUT/icon-maskable-192.png" "$BUILD_DIR/preview.png"
  ok "preview → $BUILD_DIR/preview.png"
}

# ---------------------------------------------------------------- target: og
og_default_template() {
  cat <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <!-- Placeholders: {{BG}} {{TEXT}} {{MUTED}} {{ACCENT}} {{FONT}} {{ICON}} {{TEXT_BLOCK}}
       {{TEXT_BLOCK}} is title + subtitle, vertically centred on y=0: place it with a translate(). -->
  <rect width="1200" height="630" fill="{{BG}}"/>
  <rect x="0" y="606" width="1200" height="24" fill="{{ACCENT}}"/>
  <image x="96" y="175" width="280" height="280" href="{{ICON}}"/>
  <g transform="translate(440,315)" font-family="{{FONT}}">{{TEXT_BLOCK}}</g>
</svg>
EOF
}

og_text_block() {  # title/subtitle -> <text> elements centred on y=0
  local title="${OG_TITLE//\\n/$'\n'}" sub="${OG_SUBTITLE//\\n/$'\n'}" ts="$OG_TITLE_SIZE"
  local nt=0 ns=0 line i y
  while IFS= read -r line; do nt=$((nt + 1)); done <<<"$title"
  if [[ -n "$sub" ]]; then while IFS= read -r line; do ns=$((ns + 1)); done <<<"$sub"; fi
  i=0
  while IFS= read -r line; do
    y=$(awk -v ts="$ts" -v nt="$nt" -v ns="$ns" -v i="$i" 'BEGIN {
      lt = ts * 1.2; ss = int(ts * 0.5 + 0.5); ls = ss * 1.4; gap = (ns > 0) ? ts * 0.45 : 0
      h = nt * lt + gap + ns * ls; printf "%.1f", -h / 2 + i * lt + ts * 0.92 }')
    printf '<text x="0" y="%s" font-size="%s" font-weight="700" fill="%s">%s</text>' \
      "$y" "$ts" "$OG_TEXT_COLOR" "$(xml_escape "$line")"
    i=$((i + 1))
  done <<<"$title"
  if [[ -n "$sub" ]]; then
    i=0
    while IFS= read -r line; do
      y=$(awk -v ts="$ts" -v nt="$nt" -v ns="$ns" -v i="$i" 'BEGIN {
        lt = ts * 1.2; ss = int(ts * 0.5 + 0.5); ls = ss * 1.4; gap = ts * 0.45
        h = nt * lt + gap + ns * ls; printf "%.1f", -h / 2 + nt * lt + gap + i * ls + ss * 0.92 }')
      printf '<text x="0" y="%s" font-size="%s" fill="%s">%s</text>' \
        "$y" "$(awk -v ts="$ts" 'BEGIN { print int(ts * 0.5 + 0.5) }')" "$OG_MUTED_COLOR" "$(xml_escape "$line")"
      i=$((i + 1))
    done <<<"$sub"
  fi
}

build_og() {
  local tpl icon block svg="$TMP/og.svg" log="$TMP/og.log"
  mkdir -p "$OUT"
  if [[ -f "$OG_TEMPLATE" ]]; then tpl=$(cat "$OG_TEMPLATE"); else tpl=$(og_default_template); fi
  render "$SRC" 512 "$TMP/og-icon.png"
  icon="data:image/png;base64,$(base64 < "$TMP/og-icon.png" | tr -d '\n')"
  block=$(og_text_block)
  tpl=${tpl//\{\{BG\}\}/$OG_BG_COLOR}
  tpl=${tpl//\{\{TEXT\}\}/$OG_TEXT_COLOR}
  tpl=${tpl//\{\{MUTED\}\}/$OG_MUTED_COLOR}
  tpl=${tpl//\{\{ACCENT\}\}/$OG_ACCENT_COLOR}
  tpl=${tpl//\{\{FONT\}\}/$(xml_escape "$OG_FONT")}
  tpl=${tpl//\{\{ICON\}\}/$icon}
  tpl=${tpl//\{\{TEXT_BLOCK\}\}/$block}
  printf '%s\n' "$tpl" > "$svg"
  cp "$svg" "$BUILD_DIR/og.svg"

  local font_args=""
  if [[ -n "$OG_FONT_FILE" ]]; then
    [[ -f "$OG_FONT_FILE" ]] || die "OG_FONT_FILE not found: $OG_FONT_FILE"
    if [[ "$RENDERER" == "resvg" ]]; then font_args="yes"; else warn "OG_FONT_FILE needs resvg; $RENDERER uses system fonts"; fi
  fi
  if [[ -n "$font_args" ]]; then
    render_wh "$svg" 1200 630 "$OUT/og.png" --use-font-file "$OG_FONT_FILE" 2>"$log" || { cat "$log" >&2; die "OG render failed"; }
  else
    render_wh "$svg" 1200 630 "$OUT/og.png" 2>"$log" || { cat "$log" >&2; die "OG render failed"; }
  fi
  if grep -qi "no match" "$log"; then
    warn "some OG fonts were not found — text may use a fallback font or show tofu (□)."
    warn "install Noto Sans CJK / Source Han Sans or set OG_FONT_FILE in icons/icon.env"
  fi
  track_png "$OUT/og.png"
  ok "og.png (1200x630)${OG_FONT_FILE:+ font: $OG_FONT_FILE}  — check it: $OUT/og.png"
  if [[ -z "$SITE_URL" ]]; then
    warn "SITE_URL not set: og:image must be an absolute URL for most crawlers (set SITE_URL in icon.env)"
  fi
}

# ---------------------------------------------------------------- target: ios
ios_contents_json() {
  if [[ "$IOS_APPEARANCES" == "1" ]]; then
    cat <<'EOF'
{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "AppIcon-Dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
      "filename" : "AppIcon-Tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
  else
    cat <<'EOF'
{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
  fi
}

build_ios() {
  local f
  ios_contents_json > "$TMP/Contents.json"
  if [[ -n "$IOS_ICONSET_DIR" ]]; then
    BACKUP_ROOT="$BUILD_DIR/backup/$RUN_ID"
    # switching an existing (legacy multi-size) icon set: move every old file aside first
    if [[ -f "$IOS_DIR/Contents.json" ]] && ! cmp -s "$TMP/Contents.json" "$IOS_DIR/Contents.json"; then
      mkdir -p "$BACKUP_ROOT/$IOS_DIR"
      for f in "$IOS_DIR"/*; do
        if [[ -f "$f" ]]; then mv "$f" "$BACKUP_ROOT/$IOS_DIR/"; fi
      done
      BACKED_UP=1
      warn "previous $IOS_DIR contents moved to $BACKUP_ROOT/$IOS_DIR/"
    fi
  fi
  mkdir -p "$IOS_DIR"
  place "$SRC" 1024 "$APPLE_SCALE" "$BG_COLOR" "$TMP/ios-any.png"
  install_out "$TMP/ios-any.png" "$IOS_DIR/AppIcon.png"
  if [[ "$IOS_APPEARANCES" == "1" ]]; then
    place "${DARK_FILE:-$SRC}" 1024 "$APPLE_SCALE" "$IOS_DARK_BG" "$TMP/ios-dark.png"
    install_out "$TMP/ios-dark.png" "$IOS_DIR/AppIcon-Dark.png"
    place "$MONO_FILE" 1024 "$APPLE_SCALE" "#000000" "$TMP/ios-tinted.png" "#ffffff"
    install_out "$TMP/ios-tinted.png" "$IOS_DIR/AppIcon-Tinted.png"
  fi
  install_out "$TMP/Contents.json" "$IOS_DIR/Contents.json"
  BACKUP_ROOT=""
  ok "iOS AppIcon.appiconset (1024: any$([[ "$IOS_APPEARANCES" == "1" ]] && echo ", dark, tinted")) → $IOS_DIR/"
}

# ---------------------------------------------------------------- target: android
android_xml_adaptive() {
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">'
  echo '    <background android:drawable="@color/ic_launcher_background"/>'
  echo '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>'
  if [[ "$ANDROID_MONOCHROME" == "1" ]]; then
    echo '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>'
  fi
  echo '</adaptive-icon>'
}

build_android() {
  local entry d m fg ln nt t
  if [[ -n "$ANDROID_RES_DIR" ]]; then BACKUP_ROOT="$BUILD_DIR/backup/$RUN_ID"; fi
  mkdir -p "$ANDROID_RES" "$ANDROID_STAGE"

  # master composite of what launchers show: background + foreground (108dp), visible centre 72dp
  place "$SRC" 432 "$ANDROID_FG_SCALE" none "$TMP/and-fg-432.png"
  "$IM" -size 432x432 "xc:$BG_COLOR" "$TMP/and-fg-432.png" -composite \
    -gravity center -crop 288x288+0+0 +repage -alpha off "$TMP/and-visible-288.png"
  place "$MONO_FILE" 432 "$ANDROID_FG_SCALE" none "$TMP/and-mono-432.png" "#ffffff"

  for entry in $DENSITIES; do
    d="${entry%%:*}"; m="${entry#*:}"
    fg=$(awk -v m="$m" 'BEGIN { print int(108 * m) }')
    ln=$(awk -v m="$m" 'BEGIN { print int(48 * m) }')
    nt=$(awk -v m="$m" 'BEGIN { print int(24 * m) }')

    t=$(tmpfile png); place "$SRC" "$fg" "$ANDROID_FG_SCALE" none "$t"
    install_out "$t" "$ANDROID_RES/mipmap-$d/ic_launcher_foreground.png"
    t=$(tmpfile png); mask "$TMP/and-visible-288.png" "$ln" "round:$(awk -v s="$ln" 'BEGIN { print int(s * 0.16) }')" "$t"
    install_out "$t" "$ANDROID_RES/mipmap-$d/ic_launcher.png"
    t=$(tmpfile png); mask "$TMP/and-visible-288.png" "$ln" circle "$t"
    install_out "$t" "$ANDROID_RES/mipmap-$d/ic_launcher_round.png"
    if [[ "$ANDROID_MONOCHROME" == "1" ]]; then
      t=$(tmpfile png); place "$MONO_FILE" "$fg" "$ANDROID_FG_SCALE" none "$t" "#ffffff"
      install_out "$t" "$ANDROID_RES/mipmap-$d/ic_launcher_monochrome.png"
    fi
    if [[ "$ANDROID_NOTIFICATION" == "1" ]]; then
      t=$(tmpfile png); place "$MONO_FILE" "$nt" 0.83 none "$t" "#ffffff"
      install_out "$t" "$ANDROID_RES/drawable-$d/ic_stat_notification.png"
    fi
  done

  t=$(tmpfile xml); android_xml_adaptive > "$t"; install_out "$t" "$ANDROID_RES/mipmap-anydpi-v26/ic_launcher.xml"
  t=$(tmpfile xml); android_xml_adaptive > "$t"; install_out "$t" "$ANDROID_RES/mipmap-anydpi-v26/ic_launcher_round.xml"
  t=$(tmpfile xml)
  printf '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">%s</color>\n</resources>\n' \
    "$BG_COLOR" > "$t"
  install_out "$t" "$ANDROID_RES/values/ic_launcher_background.xml"
  BACKUP_ROOT=""
  # a second definition (e.g. values/colors.xml from flutter_launcher_icons) breaks the Gradle build
  for t in "$ANDROID_RES"/values*/*.xml; do
    if [[ -f "$t" && "$t" != "$ANDROID_RES/values/ic_launcher_background.xml" ]] \
       && grep -q 'name="ic_launcher_background"' "$t"; then
      warn "duplicate colour resource ic_launcher_background in $t — remove it there (build will fail otherwise)"
    fi
  done

  # staging extras: Play Console upload + 1024 layers (Expo adaptiveIcon)
  place "$SRC" 512 "$APPLE_SCALE" "$BG_COLOR" "$TMP/play.png"
  "$IM" "$TMP/play.png" -alpha set -define png:color-type=6 "$ANDROID_STAGE/play-store-512.png"   # Play wants 32-bit PNG
  place "$SRC" 1024 "$ANDROID_FG_SCALE" none "$ANDROID_STAGE/adaptive-foreground-1024.png"
  track_png "$ANDROID_STAGE/adaptive-foreground-1024.png"
  if [[ "$ANDROID_MONOCHROME" == "1" ]]; then
    place "$MONO_FILE" 1024 "$ANDROID_FG_SCALE" none "$ANDROID_STAGE/adaptive-monochrome-1024.png" "#ffffff"
    track_png "$ANDROID_STAGE/adaptive-monochrome-1024.png"
  fi
  ok "Android adaptive + legacy + round$([[ "$ANDROID_MONOCHROME" == "1" ]] && echo " + monochrome")$([[ "$ANDROID_NOTIFICATION" == "1" ]] && echo " + notification") → $ANDROID_RES/"
  ok "Android extras (play-store-512, adaptive 1024 layers) → $ANDROID_STAGE/"
}

# ---------------------------------------------------------------- head snippet
write_head_snippet() {
  local v="" og_url
  if [[ "$CACHE_BUST" == "1" ]]; then v="?v=$(input_hash | cut -c1-8)"; fi
  {
    if [[ -f "$OUT/favicon.ico" ]]; then
      echo "<link rel=\"icon\" href=\"$URL_BASE/favicon.ico$v\" sizes=\"32x32\">"
      echo "<link rel=\"icon\" href=\"$URL_BASE/icon.svg$v\" type=\"image/svg+xml\">"
      echo "<link rel=\"apple-touch-icon\" href=\"$URL_BASE/apple-touch-icon.png$v\">"
      if [[ -f "$OUT/$MANIFEST" ]]; then echo "<link rel=\"manifest\" href=\"$URL_BASE/$MANIFEST\">"; fi
      echo "<meta name=\"theme-color\" content=\"$THEME_COLOR\">"
    fi
    if [[ -f "$OUT/og.png" ]]; then
      og_url="${SITE_URL%/}$URL_BASE/og.png$v"
      echo "<meta property=\"og:image\" content=\"$og_url\">"
      echo "<meta property=\"og:image:width\" content=\"1200\">"
      echo "<meta property=\"og:image:height\" content=\"630\">"
      echo "<meta property=\"og:image:alt\" content=\"$(xml_escape "${OG_TITLE//\\n/ }")\">"
      echo "<meta name=\"twitter:card\" content=\"summary_large_image\">"
      echo "<meta name=\"twitter:image\" content=\"$og_url\">"
    fi
  } > "$BUILD_DIR/head-snippet.html"
}

# ---------------------------------------------------------------- previews
# preview.png (web)        row 1 light / row 2 dark: 16 32 48 at 1:1 | the same enlarged (nearest neighbour)
#                          row 3 grey: apple-touch-icon | icon-192 | maskable in 100% circle | maskable in 80% safe zone
make_preview_web() {
  local p16="$1" p32="$2" p48="$3" papple="$4" p192="$5" pmask="$6" out="$7"
  local d="$TMP/pv-web" bg s img z i tiles
  mkdir -p "$d"
  i=0
  for bg in "#ffffff" "#1f2328"; do
    i=$((i + 1)); tiles=""
    for s in 16 32 48; do
      case "$s" in 16) img="$p16" ;; 32) img="$p32" ;; *) img="$p48" ;; esac
      "$IM" -size 152x152 "xc:$bg" "$img" -gravity center -composite "$d/r$i-a$s.png"
      tiles="$tiles $d/r$i-a$s.png"
    done
    for s in 16 32 48; do
      case "$s" in 16) img="$p16" ;; 32) img="$p32" ;; *) img="$p48" ;; esac
      z=$((s * (144 / s)))
      "$IM" -size 152x152 "xc:$bg" \( "$img" -filter point -resize "${z}x${z}" \) \
        -gravity center -composite "$d/r$i-z$s.png"
      tiles="$tiles $d/r$i-z$s.png"
    done
    # shellcheck disable=SC2086
    "$IM" $tiles +append "$d/row$i.png"
  done
  mask "$pmask" 192 circle "$d/mask100.png"
  "$IM" "$pmask" \( -size 192x192 xc:black -fill white -draw "circle 96,96 96,19" \) \
    -alpha off -compose CopyOpacity -composite "$d/mask80.png"
  tiles=""
  for img in "$papple" "$p192" "$d/mask100.png" "$d/mask80.png"; do
    "$IM" -size 228x228 "xc:#d0d7de" "$img" -gravity center -composite "$d/t$(basename "$img")"
    tiles="$tiles $d/t$(basename "$img")"
  done
  # shellcheck disable=SC2086
  "$IM" $tiles +append "$d/row3.png"
  "$IM" "$d/row1.png" "$d/row2.png" "$d/row3.png" -background "#8c959f" -gravity center -append \
    -bordercolor "#8c959f" -border 8 "$out"
}

# preview-native.png       iOS row    : Any | Dark | Tinted            (squircle-ish mask, 180px)
#                          Android row: adaptive circle | adaptive rounded square | legacy ic_launcher |
#                                       themed (monochrome, Material You style) | notification on dark bar
make_preview_native() {
  local out="$1" d="$TMP/pv-native" tiles="" rows="" img
  mkdir -p "$d"
  tile() {  # tile IMG BG NAME
    "$IM" -size 220x220 "xc:$2" "$1" -gravity center -composite "$d/$3.png"
    tiles="$tiles $d/$3.png"
  }
  if has_target ios; then
    tiles=""
    mask "$IOS_DIR/AppIcon.png" 180 round:40 "$d/ios-any.png";  tile "$d/ios-any.png" "#e5e5ea" ios1
    if [[ -f "$IOS_DIR/AppIcon-Dark.png" ]]; then
      mask "$IOS_DIR/AppIcon-Dark.png" 180 round:40 "$d/ios-dark.png"; tile "$d/ios-dark.png" "#1c1c1e" ios2
      "$IM" "$IOS_DIR/AppIcon-Tinted.png" \( -size 1024x1024 xc:"#e0b3ff" \) -compose Multiply -composite \
        "$d/ios-tint-src.png"
      mask "$d/ios-tint-src.png" 180 round:40 "$d/ios-tinted.png"; tile "$d/ios-tinted.png" "#1c1c1e" ios3
    fi
    # shellcheck disable=SC2086
    "$IM" $tiles +append "$d/row-ios.png"; rows="$rows $d/row-ios.png"
  fi
  if has_target android; then
    tiles=""
    mask "$TMP/and-visible-288.png" 180 circle "$d/and-circle.png";      tile "$d/and-circle.png" "#f1f3f4" and1
    mask "$TMP/and-visible-288.png" 180 round:45 "$d/and-round.png";     tile "$d/and-round.png" "#f1f3f4" and2
    tile "$ANDROID_RES/mipmap-xxxhdpi/ic_launcher.png" "#f1f3f4" and3
    if [[ "$ANDROID_MONOCHROME" == "1" ]]; then
      "$IM" "$TMP/and-mono-432.png" -fill "#0b57d0" -colorize 100 "$d/mono-col.png"
      "$IM" -size 432x432 xc:"#d3e3fd" "$d/mono-col.png" -composite -gravity center -crop 288x288+0+0 +repage \
        -alpha off "$d/themed-288.png"
      mask "$d/themed-288.png" 180 circle "$d/and-themed.png";           tile "$d/and-themed.png" "#f1f3f4" and4
    fi
    if [[ "$ANDROID_NOTIFICATION" == "1" ]]; then
      img="$ANDROID_RES/drawable-xxxhdpi/ic_stat_notification.png"
      "$IM" -size 220x220 xc:"#202124" "$img" -gravity center -composite "$d/and5.png"; tiles="$tiles $d/and5.png"
    fi
    # shellcheck disable=SC2086
    "$IM" $tiles +append "$d/row-and.png"; rows="$rows $d/row-and.png"
  fi
  if [[ -n "$rows" ]]; then
    # shellcheck disable=SC2086
    "$IM" $rows -background "#8c959f" -gravity west -append -bordercolor "#8c959f" -border 8 "$out"
    ok "native preview → $out"
  fi
}

# ---------------------------------------------------------------- modes
setup_common() {
  detect_tools
  require_tools
  validate_svg "$SRC"
  SMALL_FILE=""; MONO_FILE="$SRC"; DARK_FILE=""
  if [[ -n "$SRC_SMALL" && -f "$SRC_SMALL" ]]; then validate_svg "$SRC_SMALL"; SMALL_FILE="$SRC_SMALL"; fi
  if [[ -n "$SRC_MONO" && -f "$SRC_MONO" ]]; then validate_svg "$SRC_MONO"; MONO_FILE="$SRC_MONO"; fi
  if [[ -n "$SRC_DARK" && -f "$SRC_DARK" ]]; then validate_svg "$SRC_DARK"; DARK_FILE="$SRC_DARK"; fi
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/icons.XXXXXX")
  trap 'rm -rf "$TMP"' EXIT
  : > "$TMP/pngs.txt"
  RUN_ID=$(date +%Y%m%d-%H%M%S)
  BACKED_UP=0
  mkdir -p "$BUILD_DIR"
}

build() {
  setup_common
  local t
  info "Building [$TARGETS] from $SRC  ($RENDERER + $IM)"
  if [[ -n "$SMALL_FILE$DARK_FILE" || "$MONO_FILE" != "$SRC" ]]; then
    printf '  %svariants: %s%s%s%s\n' "$C_D" "${SMALL_FILE:+small=$SMALL_FILE }" \
      "$([[ "$MONO_FILE" != "$SRC" ]] && echo "mono=$MONO_FILE ")" "${DARK_FILE:+dark=$DARK_FILE}" "$C_0"
  fi
  for t in $ALL_TARGETS; do
    if has_target "$t"; then
      info "$t"
      "build_$t"
    fi
  done
  optimize_pngs
  if has_target web || has_target og; then write_head_snippet; fi
  if has_target ios || has_target android; then make_preview_native "$BUILD_DIR/preview-native.png"; fi
  update_stamp "$TARGETS"

  if [[ "$BACKED_UP" == "1" ]]; then warn "replaced native files were backed up to $BUILD_DIR/backup/$RUN_ID/"; fi
  if [[ -s "$BUILD_DIR/head-snippet.html" ]] && { has_target web || has_target og; }; then
    echo
    info "Add to <head> (also saved to $BUILD_DIR/head-snippet.html):"
    sed 's/^/    /' "$BUILD_DIR/head-snippet.html"
  fi
  echo
  info "Next: inspect the previews:"
  if has_target web; then echo "    $BUILD_DIR/preview.png"; fi
  if has_target ios || has_target android; then echo "    $BUILD_DIR/preview-native.png"; fi
  if has_target og; then echo "    $OUT/og.png"; fi
}

preview_only() {
  setup_common
  local name s
  name=$(basename "$SRC" .svg)
  for s in 16 32 48; do render "$(small_or_main "$s")" "$s" "$TMP/p-$s.png"; done
  render "$SRC" 192 "$TMP/p-192.png"
  place "$SRC" 180 "$APPLE_SCALE" "$BG_COLOR" "$TMP/p-apple.png"
  place "$SRC" 192 "$MASKABLE_SCALE" "$BG_COLOR" "$TMP/p-mask.png"
  make_preview_web "$TMP/p-16.png" "$TMP/p-32.png" "$TMP/p-48.png" "$TMP/p-apple.png" \
    "$TMP/p-192.png" "$TMP/p-mask.png" "$BUILD_DIR/preview-$name.png"
  ok "preview → $BUILD_DIR/preview-$name.png"
}

check() {
  [[ -f "$SRC" ]] || die "source not found: $SRC"
  local bad=0 f t h stamp line
  for t in $TARGETS; do
    while IFS= read -r f; do
      if [[ -n "$f" && ! -f "$f" ]]; then warn "$t: missing $f"; bad=1; fi
    done <<EOF
$("outputs_$t")
EOF
  done
  stamp=$(stamp_file); h=$(input_hash)
  for t in $TARGETS; do
    line=""
    if [[ -f "$stamp" ]]; then line=$(grep "^$t " "$stamp" | head -1 | cut -d' ' -f2 || true); fi
    if [[ -z "$line" ]]; then warn "$t: never built with this pipeline"; bad=1
    elif [[ "$line" != "$h" ]]; then warn "$t: sources or settings changed since last build"; bad=1; fi
  done
  if [[ "$bad" -ne 0 ]]; then die "icons out of date — run: make icons"; fi
  ok "icons up to date [$TARGETS]"
}

clean() {
  local f t n=0
  for t in $TARGETS; do
    case "$t" in
      ios)     [[ -z "$IOS_ICONSET_DIR" ]] || { warn "ios: $IOS_DIR is a real project dir — not cleaned"; continue; } ;;
      android) [[ -z "$ANDROID_RES_DIR" ]] || { warn "android: $ANDROID_RES is a real project dir — res not cleaned"; } ;;
    esac
    while IFS= read -r f; do
      if [[ -n "$f" && -f "$f" ]]; then rm -f "$f"; n=$((n + 1)); fi
    done <<EOF
$(if [[ "$t" == "android" && -n "$ANDROID_RES_DIR" ]]; then outputs_android_stage; else "outputs_$t"; fi)
EOF
  done
  if [[ -n "$ICON_SUB" ]]; then rmdir "$ICON_OUT" 2>/dev/null || true; fi
  if [[ -d "$NATIVE_OUT" ]]; then find "$NATIVE_OUT" -type d -empty -delete 2>/dev/null || true; fi
  rm -f "$BUILD_DIR/preview.png" "$BUILD_DIR/preview-native.png" "$BUILD_DIR/head-snippet.html" "$BUILD_DIR/og.svg"
  f=$(stamp_file)
  if [[ -f "$f" ]]; then
    grep -vE "^(${TARGETS// /|}) " "$f" > "$f.tmp" || true
    if [[ -s "$f.tmp" ]]; then mv "$f.tmp" "$f"; else rm -f "$f.tmp" "$f"; fi
  fi
  ok "removed $n generated files [$TARGETS] (manifest, backups and real native dirs kept)"
}

case "$MODE" in
  build)             build ;;
  preview)           preview_only ;;
  check)             check ;;
  deps)              deps ;;
  clean)             clean ;;
  print-og-template) og_default_template ;;
esac
