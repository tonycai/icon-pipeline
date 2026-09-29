#!/usr/bin/env bash
# init-project.sh — vendor the icon pipeline into a project (safe to re-run).
#
# Creates (only if absent, unless --force):
#   scripts/build-icons.sh   the pipeline (vendored so CI and teammates don't need the skill)
#   icons.mk                 make targets: icons, icons-{web,og,ios,android}, icons-check/preview/clean/deps
#   icons/icon.env           per-project settings; TARGETS and native dirs are auto-detected
#                            (web root, Flutter web, Xcode AppIcon.appiconset, Android res/, Expo)
# Also: adds ".icon-build/" to .gitignore and "include icons.mk" to the Makefile.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="."
FORCE=0
EXAMPLE=0
OPT_OUT=""
OPT_NAME=""

usage() {
  cat <<EOF
Usage: init-project.sh [--dir PROJECT] [--out WEBROOT] [--name APPNAME] [--example] [--force]

  --dir DIR     project root (default: current directory)
  --out DIR     web root that serves static files (default: auto-detect, e.g. public/ or static/)
  --name TEXT   app name written to icons/icon.env (default: package.json name or folder name)
  --example     copy an example icons/source.svg if none exists
  --force       overwrite scripts/build-icons.sh and icons.mk with the skill's versions
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     PROJECT="$2"; shift 2 ;;
    --out)     OPT_OUT="$2"; shift 2 ;;
    --name)    OPT_NAME="$2"; shift 2 ;;
    --example) EXAMPLE=1; shift ;;
    --force)   FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

cd "$PROJECT"
say() { printf '  %s\n' "$*"; }

detect_out() {
  if [[ -n "$OPT_OUT" ]]; then echo "$OPT_OUT"; return; fi
  if [[ -f pubspec.yaml && -d web ]]; then echo "web"; return; fi                 # Flutter web
  if [[ -f svelte.config.js || -f svelte.config.ts ]]; then echo "static"; return; fi
  if [[ -f hugo.toml || -f hugo.yaml || ( -f config.toml && -d layouts ) ]]; then echo "static"; return; fi
  if [[ -d public ]]; then echo "public"; return; fi
  if [[ -d static ]]; then echo "static"; return; fi
  echo "public"
}

has_web() {
  [[ -n "$OPT_OUT" || -d public || -d static || -f index.html || ( -f pubspec.yaml && -d web ) ]]
}

detect_name() {
  if [[ -n "$OPT_NAME" ]]; then echo "$OPT_NAME"; return; fi
  if [[ -f package.json ]] && command -v jq >/dev/null 2>&1; then
    local n; n=$(jq -r '.name // empty' package.json 2>/dev/null || true)
    if [[ -n "$n" ]]; then echo "$n"; return; fi
  fi
  basename "$(pwd)"
}

# Xcode app icon sets: Capacitor/Flutter/Tauri (Assets.xcassets), React Native (Images.xcassets), native
detect_iconset() {
  local found n
  found=$(find . -maxdepth 7 -type d -name AppIcon.appiconset -path '*.xcassets/*' \
    -not -path '*/node_modules/*' -not -path '*/Pods/*' -not -path '*/build/*' \
    -not -path '*/DerivedData/*' -not -path './.git/*' -not -path './icons/*' 2>/dev/null | sed 's|^\./||')
  n=$(printf '%s' "$found" | grep -c . || true)
  if [[ "$n" -eq 1 ]]; then echo "$found"
  elif [[ "$n" -gt 1 ]]; then
    printf '%s\n' "$found" | sed 's/^/      candidate: /' >&2
    say "! several AppIcon.appiconset dirs found — set IOS_ICONSET_DIR in icons/icon.env yourself" >&2
  fi
}

detect_android_res() {
  local d
  for d in android/app/src/main/res src-tauri/gen/android/app/src/main/res app/src/main/res; do
    if [[ -d "$d" ]]; then echo "$d"; return; fi
  done
}

install_file() {  # install_file SRC DEST MODE
  local src="$1" dest="$2" mode="$3"
  if [[ -f "$dest" && "$FORCE" -ne 1 ]]; then
    if cmp -s "$src" "$dest"; then say "= $dest (up to date)"
    else say "~ $dest exists and differs (kept; use --force to update)"; fi
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  chmod "$mode" "$dest"
  say "+ $dest"
}

echo "==> Installing icon pipeline into $(pwd)"
install_file "$SKILL_DIR/scripts/build-icons.sh" "scripts/build-icons.sh" 755
install_file "$SKILL_DIR/templates/icons.mk" "icons.mk" 644

if [[ -f icons/icon.env ]]; then
  say "= icons/icon.env (kept)"
else
  mkdir -p icons
  out_dir=$(detect_out)
  app_name=$(detect_name | sed 's/[\\"$`]//g')
  iconset=$(detect_iconset)
  android_res=$(detect_android_res)
  targets=""
  if has_web; then targets="web og"; fi
  is_expo=0
  if [[ -f app.json ]] && grep -q '"expo"' app.json; then is_expo=1; fi
  if [[ -n "$iconset" || "$is_expo" -eq 1 ]]; then targets="$targets ios"; fi
  if [[ -n "$android_res" || "$is_expo" -eq 1 ]]; then targets="$targets android"; fi
  targets="${targets# }"
  [[ -n "$targets" ]] || targets="web og"
  manifest="manifest.webmanifest"
  if [[ "$out_dir" == "web" && -f web/manifest.json ]]; then manifest="manifest.json"; fi
  sed -e "s|^TARGETS=.*|TARGETS=\"$targets\"|" \
      -e "s|^OUT=\"[^\"]*\"|OUT=\"$out_dir\"|" \
      -e "s|^MANIFEST=\"[^\"]*\"|MANIFEST=\"$manifest\"|" \
      -e "s|^NAME=.*|NAME=\"$app_name\"|" \
      -e "s|^SHORT_NAME=.*|SHORT_NAME=\"$app_name\"|" \
      -e "s|^IOS_ICONSET_DIR=\"\"|IOS_ICONSET_DIR=\"$iconset\"|" \
      -e "s|^ANDROID_RES_DIR=\"\"|ANDROID_RES_DIR=\"$android_res\"|" \
      "$SKILL_DIR/templates/icon.env" > icons/icon.env
  say "+ icons/icon.env (TARGETS=\"$targets\", OUT=$out_dir, NAME=$app_name)"
  if [[ -n "$iconset" ]]; then say "    iOS icon set    : $iconset (written in place, old files backed up)"; fi
  if [[ -n "$android_res" ]]; then say "    Android res dir : $android_res (written in place, changed files backed up)"; fi
fi

if [[ "$EXAMPLE" -eq 1 && ! -f icons/source.svg ]]; then
  cp "$SKILL_DIR/assets/example-source.svg" icons/source.svg
  say "+ icons/source.svg (example — replace with your own design)"
fi

if [[ ! -f .gitignore ]] || ! grep -qxF '.icon-build/' .gitignore; then
  printf '.icon-build/\n' >> .gitignore
  say "+ .gitignore: .icon-build/"
fi

if [[ -f Makefile ]]; then
  if grep -qE '^-?include[[:space:]]+icons\.mk' Makefile; then
    say "= Makefile already includes icons.mk"
  else
    printf '\ninclude icons.mk\n' >> Makefile
    say "+ Makefile: include icons.mk"
  fi
else
  printf 'include icons.mk\n' > Makefile
  say "+ Makefile (new, includes icons.mk)"
fi

if [[ -f package.json ]]; then
  say "tip: for npm users add  \"icons\": \"bash scripts/build-icons.sh\"  to package.json scripts"
fi

echo "==> Done. Next: put your artwork in icons/source.svg, then run: make icons"
