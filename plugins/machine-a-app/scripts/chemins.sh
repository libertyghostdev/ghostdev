#!/bin/sh
# Chemins portables. Sur Windows, Claude Code donne des chemins « C:\Users\… » ; dans Git Bash on les
# convertit en « /c/Users/… » avec cygpath quand il existe. Sur Mac et Linux, rien ne change.
ghostdev_chemin() {
  case "$1" in
    *\\*|[A-Za-z]:*) if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1" 2>/dev/null || printf '%s' "$1"; else printf '%s' "$1" | tr '\\' '/'; fi ;;
    *) printf '%s' "$1" ;;
  esac
}
