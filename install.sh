#!/usr/bin/env bash
# Install Claude Dev Workflow Skills into ~/.claude/skills/
#
# Usage:
#   ./install.sh           # interactive
#   ./install.sh en        # install English skills
#   ./install.sh it        # install Italian skills
#   ./install.sh en --force  # overwrite without prompting

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_TARGET="${HOME}/.claude/skills"

# --- Colors ------------------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    C_CYAN=$(tput setaf 6)
    C_GREEN=$(tput setaf 2)
    C_YELLOW=$(tput setaf 3)
    C_RED=$(tput setaf 1)
    C_RESET=$(tput sgr0)
else
    C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi

info()    { printf '%s[INFO]%s  %s\n' "$C_CYAN"   "$C_RESET" "$1"; }
success() { printf '%s[OK]%s    %s\n' "$C_GREEN"  "$C_RESET" "$1"; }
warn()    { printf '%s[WARN]%s  %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
err()     { printf '%s[ERR]%s   %s\n' "$C_RED"    "$C_RESET" "$1" >&2; }

# --- Parse args --------------------------------------------------------------
LANG=""
FORCE=0

for arg in "$@"; do
    case "$arg" in
        en|it)        LANG="$arg" ;;
        --force|-f)   FORCE=1 ;;
        -h|--help)
            sed -n '1,/^set -euo/p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *)
            err "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

# --- Validate repo state -----------------------------------------------------
if [[ ! -d "$REPO_ROOT/en" || ! -d "$REPO_ROOT/it" ]]; then
    err "Repository structure invalid: expected 'en/' and 'it/' folders next to install.sh"
    exit 1
fi

# --- Pick language -----------------------------------------------------------
if [[ -z "$LANG" ]]; then
    echo ""
    echo "Claude Dev Workflow Skills installer"
    echo "===================================="
    echo ""
    echo "  [1] English  (en/)"
    echo "  [2] Italiano (it/)"
    echo ""
    read -r -p "Choose language [1/2]: " choice
    case "$choice" in
        1|en) LANG="en" ;;
        2|it) LANG="it" ;;
        *)
            err "Invalid choice: $choice"
            exit 1
            ;;
    esac
fi

SOURCE_DIR="$REPO_ROOT/$LANG"
info "Installing $LANG skills from $SOURCE_DIR"

# --- Ensure target dir exists ------------------------------------------------
if [[ ! -d "$SKILLS_TARGET" ]]; then
    info "Creating $SKILLS_TARGET"
    mkdir -p "$SKILLS_TARGET"
fi

# --- Copy each skill ---------------------------------------------------------
shopt -s nullglob
skills=("$SOURCE_DIR"/*/)
shopt -u nullglob

if [[ ${#skills[@]} -eq 0 ]]; then
    err "No skills found in $SOURCE_DIR"
    exit 1
fi

installed=0
skipped=0

for skill_path in "${skills[@]}"; do
    skill_name="$(basename "$skill_path")"
    target_path="$SKILLS_TARGET/$skill_name"

    if [[ -e "$target_path" ]]; then
        if [[ $FORCE -eq 1 ]]; then
            warn "Overwriting existing $skill_name"
        else
            echo ""
            warn "$skill_name already exists at $target_path"
            read -r -p "Overwrite? [y/N]: " reply
            if [[ ! "$reply" =~ ^[yY]$ ]]; then
                info "Skipped $skill_name"
                ((skipped++))
                continue
            fi
        fi
        rm -rf "$target_path"
    fi

    cp -R "$skill_path" "$target_path"
    success "Installed $skill_name -> $target_path"
    ((installed++))
done

# --- Summary -----------------------------------------------------------------
echo ""
echo "Done."
echo "  Installed: $installed"
echo "  Skipped:   $skipped"
echo ""
echo "Restart your Claude Code session to load the new skills."
