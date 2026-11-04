#!/bin/sh
# V2 : le socle (la voix et le protocole) au début de chaque conversation et après chaque compactage (cahier des
# charges V2, section 8). Un hook à part de demarrage.sh, parce que chaque hook a son propre plafond de 10 000
# caractères : ensemble, le socle et le contexte de démarrage le dépassaient, et Claude n'en recevait qu'un aperçu.
# Muet si le serveur ne sert pas la V2. sh seulement.
sh "$(dirname "$0")/actif.sh" || exit 0
. "$(dirname "$0")/chemins.sh"
proj=$(ghostdev_chemin "${CLAUDE_PROJECT_DIR:-$PWD}")
[ -f "$proj/.demo/scenario" ] && exit 0
[ ! -t 0 ] && cat >/dev/null 2>&1
socle=$(curl -fsS -m 4 "${GHOSTDEV_URL:-https://ghostdev.libertytechlab.com}/socle" 2>/dev/null)
[ -n "$socle" ] || exit 0
echo "<ghostdev-socle>"
printf '%s\n' "$socle"
echo "</ghostdev-socle>"
