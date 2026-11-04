#!/bin/sh
# Le dossier des données du plugin, le dossier de la session en cours, et la lecture d'un champ JSON sans jq.
# À sourcer après chemins.sh. sh seulement : jamais python, jamais node, jamais jq.
ghostdev_donnees() {
  d=$(ghostdev_chemin "${CLAUDE_PLUGIN_DATA:-}")
  [ -n "$d" ] || d="$HOME/.claude/plugins/data/machine-a-app-skills-dir"
  printf '%s' "$d"
}
# $1 = l'identifiant de session du hook ; rend le dossier de cette session, créé au besoin.
ghostdev_session() {
  s=$(printf '%s' "$1" | tr -cd 'A-Za-z0-9_-'); [ -n "$s" ] || s=sans-session
  d="$(ghostdev_donnees)/sessions/$s"
  mkdir -p "$d" 2>/dev/null
  printf '%s' "$d"
}
# $1 = du JSON sur une ligne, $2 = un nom de champ texte : sa première valeur.
ghostdev_champ() {
  printf '%s' "$1" | grep -o "\"$2\" *: *\"[^\"]*\"" | head -1 | sed 's/^[^:]*: *"//; s/"$//'
}
# $1 = du JSON sur une ligne, $2 = un nom de champ nombre : sa première valeur (signe compris).
ghostdev_nombre() {
  printf '%s' "$1" | grep -o "\"$2\" *: *-\{0,1\}[0-9][0-9]*" | head -1 | sed 's/^[^:]*: *//'
}
# Le texte de $1 en chaîne JSON (sans les guillemets autour) : barres, guillemets, tabulations, retours à la ligne.
ghostdev_json() {
  printf '%s' "$1" | awk 'BEGIN{ORS=""} {gsub(/\\/,"&&"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,""); if (NR>1) printf "\\n"; printf "%s", $0}'
}
