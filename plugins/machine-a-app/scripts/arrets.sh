#!/bin/sh
# V2 : une fiche lue par lire_fiche sort des arrêts et entre dans « déjà lues » (navigation, 6.2). Hook PostToolUse sur
# lire_fiche. Les arrêts sont les fiches principales que guide a demandé de lire avant le premier geste qui change
# quelque chose ; consultation.sh refuse ce geste tant qu'il en reste. Seule une fiche vraiment livrée compte (sa
# balise <fiche id=…>), jamais un « aucune fiche » ni un refus de licence. Muet pour un sous-agent. sh seulement.
sh "$(dirname "$0")/actif.sh" || exit 0
. "$(dirname "$0")/chemins.sh"; . "$(dirname "$0")/donnees.sh"
proj=$(ghostdev_chemin "${CLAUDE_PROJECT_DIR:-$PWD}")
[ -f "$proj/.demo/scenario" ] && exit 0
plat=$(cat 2>/dev/null | tr -d '\n\r')
case "$plat" in *'"agent_id"'*) exit 0 ;; esac
sess=$(ghostdev_session "$(ghostdev_champ "$plat" session_id)")
[ -f "$sess/v2" ] || exit 0
id=$(printf '%s' "$plat" | grep -o 'fiche id=[\\"]*[A-Z][A-Z]*-[0-9][0-9]*' | head -1 | grep -o '[A-Z][A-Z]*-[0-9][0-9]*$')
[ -n "$id" ] || exit 0
printf '%s\n' "$id" >> "$sess/lues"
[ -f "$sess/arrets" ] || exit 0
grep -v -x -- "$id" "$sess/arrets" > "$sess/arrets.tmp" 2>/dev/null
if [ -s "$sess/arrets.tmp" ]; then mv "$sess/arrets.tmp" "$sess/arrets"; else rm -f "$sess/arrets.tmp" "$sess/arrets" "$sess/arrets-refus"; fi
exit 0
