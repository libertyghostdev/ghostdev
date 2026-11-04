#!/bin/sh
# V2 : la fin d'un tour (spec 4.2, étape 8 ; navigation 6.2). Hook Stop.
# 1. Un tour ne finit pas sans consultation : bloqué une seule fois. Si Claude finit encore sans consulter
#    (stop_hook_active), on laisse finir et on oublie. Jamais de boucle.
# 2. Un tour qui a changé un fichier hors de .machine-a-app/, pour un type qui a des étapes d'après (fonctionnalite,
#    bug, route) : un seul rappel, sans bloquer. additionalContext d'un hook Stop : la conversation continue et l'app
#    l'affiche comme un retour du hook, pas comme une erreur (doc des hooks, « Stop decision control »).
sh "$(dirname "$0")/actif.sh" || exit 0
. "$(dirname "$0")/chemins.sh"; . "$(dirname "$0")/donnees.sh"
proj=$(ghostdev_chemin "${CLAUDE_PROJECT_DIR:-$PWD}")
[ -f "$proj/.demo/scenario" ] && exit 0
plat=$(cat 2>/dev/null | tr -d '\n\r')
sess=$(ghostdev_session "$(ghostdev_champ "$plat" session_id)")
[ -f "$sess/v2" ] || exit 0
relance=""; printf '%s' "$plat" | grep -q '"stop_hook_active" *: *true' && relance=1
f="$sess/consulter"
if [ -f "$f" ]; then
  if [ -n "$relance" ]; then rm -f "$f"; exit 0; fi
  printf '{"decision":"block","reason":"%s"}\n' "$(ghostdev_json "GhostDev : tu n'as pas consulté guide pour ce message. Appelle guide maintenant (type, demande, besoins), puis redonne ta réponse en entier, corrigée si guide change quelque chose : l'app ne montre qu'un résumé du texte écrit avant un appel d'outil.")"
  exit 0
fi
rm -f "$sess/arrets-refus"
if [ -f "$sess/change" ] && [ -s "$sess/apres" ] && [ -z "$relance" ]; then
  t=$(cat "$sess/apres"); rm -f "$sess/change" "$sess/apres"
  printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"%s"}}\n' "$(ghostdev_json "GhostDev, avant de finir : ce tour a changé quelque chose pour une demande de type « $t ». Fais maintenant ses étapes d'après, celles que guide t'a données sous « Après », et celles du tronc commun : vérifier, montrer, noter dans la mémoire. Déjà faites : dis-le en une ligne, avec la preuve.")"
  exit 0
fi
rm -f "$sess/change"
exit 0
