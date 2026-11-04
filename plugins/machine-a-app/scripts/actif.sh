#!/bin/sh
# GhostDev est-il actif dans ce dossier ? Oui seulement si on l'a lancé ici une fois :
# le dossier .machine-a-app existe, ou c'est un dossier de démo, ou les réglages du dossier nomment l'agent.
. "$(dirname "$0")/chemins.sh"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
proj=$(ghostdev_chemin "$proj")
[ -d "$proj/.machine-a-app" ] && exit 0
[ -f "$proj/.demo/scenario" ] && exit 0
grep -q '"machine-a-app"' "$proj/.claude/settings.json" 2>/dev/null && exit 0
exit 1
