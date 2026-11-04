#!/bin/sh
# V2 : GhostDev consulté à chaque message (produit/docs/v2-arbre/cahier-des-charges.md, 4.2 et 4.5). Hook
# PreToolUse sur tous les outils. Tant que guide n'a pas été appelé depuis le dernier message de la personne, un
# autre geste est refusé avec la raison. Puis, tant qu'une fiche principale demandée par guide n'est pas lue (les
# arrêts, navigation 6.2), le premier geste qui change quelque chose (Edit, Write, MultiEdit, NotebookEdit, Bash) est
# refusé ; lire le code reste permis. Trois refus au plus de chaque sorte, puis on laisse passer : jamais une session
# bloquée par ce garde-fou. Avant guide lui-même : la phase, la technique et la route comparées à etat.json.
# Un fichier écrit hors de .machine-a-app/ marque le tour comme « a changé quelque chose » (fin-de-tour.sh).
# Rien ne se passe si la session n'est pas en V2 (le fichier « v2 » de la session, posé par demarrage.sh).
sh "$(dirname "$0")/actif.sh" || exit 0
. "$(dirname "$0")/chemins.sh"; . "$(dirname "$0")/donnees.sh"
proj=$(ghostdev_chemin "${CLAUDE_PROJECT_DIR:-$PWD}")
[ -f "$proj/.demo/scenario" ] && exit 0
plat=$(cat 2>/dev/null | tr -d '\n\r')
sess=$(ghostdev_session "$(ghostdev_champ "$plat" session_id)")
[ -f "$sess/v2" ] || exit 0
# Un sous-agent (le dessinateur) travaille pour la conversation : il n'a pas à consulter, et ses gestes ne consomment
# pas les refus de la conversation. agent_id n'existe que dans un sous-agent (doc des hooks).
case "$plat" in *'"agent_id"'*) exit 0 ;; esac
# Une réponse cliquée (AskUserQuestion) revient comme un résultat d'outil, pas comme un message : c'est pourtant la
# personne qui parle, donc la consultation se rouvre (décision V2-7). Branché en PostToolUse sur AskUserQuestion.
if [ "$(ghostdev_champ "$plat" hook_event_name)" = PostToolUse ]; then printf 0 > "$sess/consulter"; exit 0; fi
outil=$(ghostdev_champ "$plat" tool_name)
refuser() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(ghostdev_json "$1")"
  exit 0
}
case "$outil" in
  mcp__*__guide)
    e=$(tr -d '\n\r' 2>/dev/null < "$proj/.machine-a-app/etat.json")
    [ -n "$e" ] || exit 0
    ph=$(ghostdev_nombre "$e" phase); te=$(ghostdev_champ "$e" technique | tr 'A-Z' 'a-z')
    ph_in=$(ghostdev_nombre "$plat" phase); te_in=$(ghostdev_champ "$plat" technique | tr 'A-Z' 'a-z')
    if [ -n "$ph" ] && [ -n "$ph_in" ] && [ "$ph_in" != "-1" ] && [ "$ph" != "$ph_in" ]; then
      refuser "GhostDev : la phase passée à guide ($ph_in) n'est pas celle de etat.json ($ph). Rappelle guide avec phase=$ph."
    fi
    if [ -n "$te" ] && [ -n "$te_in" ] && [ "$te" != "$te_in" ]; then
      refuser "GhostDev : la technique passée à guide ($te_in) n'est pas celle de etat.json ($te). Rappelle guide avec technique=$te."
    fi
    ro=$(ghostdev_champ "$e" route | tr 'A-Z' 'a-z'); ro_in=$(ghostdev_champ "$plat" route | tr 'A-Z' 'a-z')
    if [ -n "$ro" ] && [ -n "$ro_in" ] && [ "$ro" != "$ro_in" ]; then
      refuser "GhostDev : la route passée à guide ($ro_in) n'est pas celle de etat.json ($ro). Rappelle guide avec route=$ro."
    fi
    exit 0 ;;
  mcp__*__lire_fiche|mcp__*__parcourir|mcp__*__chercher|mcp__*__escalader|mcp__*__tickets|mcp__*__methode_diagnostic|mcp__*__rapport|ToolSearch) exit 0 ;;
esac
f="$sess/consulter"
if [ -f "$f" ]; then
  n=$(cat "$f" 2>/dev/null); n=${n:-0}
  if [ "$n" -ge 3 ]; then rm -f "$f"; else
    printf '%s' "$((n + 1))" > "$f"
    refuser "GhostDev : consulte d'abord guide (type, demande, besoins), puis refais ce geste. C'est à chaque message de la personne."
  fi
fi
case "$outil" in Edit|Write|MultiEdit|NotebookEdit|Bash) ;; *) exit 0 ;; esac
# Pendant un SOS (sos-en-attente posé par phase.sh), les arrêts ne bloquent pas Bash : le diagnostic de lab est en
# lecture seule et en a besoin. Edit, Write, MultiEdit et NotebookEdit restent soumis aux arrêts.
# Le fichier porte « ticket fois session » : celui d'une autre conversation est périmé, on le supprime.
sos=""
if [ "$outil" = Bash ] && [ -s "$proj/.machine-a-app/sos-en-attente" ]; then
  fois=$(cut -d' ' -f2 "$proj/.machine-a-app/sos-en-attente")
  if [ "$(cut -d' ' -f3 "$proj/.machine-a-app/sos-en-attente")" = "$(basename "$sess")" ]; then [ "${fois:-0}" -lt 3 ] && sos=1
  else rm -f "$proj/.machine-a-app/sos-en-attente"; fi
fi
if [ -s "$sess/arrets" ] && [ -z "$sos" ]; then
  n=$(cat "$sess/arrets-refus" 2>/dev/null); n=${n:-0}
  if [ "$n" -ge 3 ]; then rm -f "$sess/arrets" "$sess/arrets-refus"; else
    printf '%s' "$((n + 1))" > "$sess/arrets-refus"
    ids=$(tr '\n' ' ' < "$sess/arrets" | sed 's/ *$//'); premiere=${ids%% *}
    refuser "GhostDev : lis d'abord $ids (lire_fiche(\"$premiere\")), la stratégie de ton type de demande, puis refais ce geste. Lire le code reste permis : Read, Grep, Glob."
  fi
fi
case "$outil" in
  Bash) ;;
  *) case "$(ghostdev_champ "$plat" file_path)$(ghostdev_champ "$plat" notebook_path)" in
       *.machine-a-app*) ;;
       *) : > "$sess/change" ;;
     esac ;;
esac
exit 0
