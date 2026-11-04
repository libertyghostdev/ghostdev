#!/bin/sh
# Un SOS attend son diagnostic de lab (un seul SOS, celui de lab : produit/docs/v2-arbre/tickets-sos/
# cahier-des-charges.md, section 3). Le 2026-10-01, chez une acheteuse, un ticket est resté à « sos » seul pendant que
# le modèle cherchait la panne : rien ne l'obligeait à le compléter.
#   sh sos-attente.sh ouvert   hook PostToolUse sur escalader : le ticket qu'il vient d'ouvrir attend son rapport
#                              (le mot « SOS » écrit l'attente lui-même, par phase.sh). Un escalader qui complète le
#                              ticket en attente (suite_de) compte comme le rapport ; un ticket déjà en attente garde
#                              son compteur.
# Le fichier sos-en-attente tient « ticket fois session » : une autre conversation ignore et supprime celui d'une
# conversation précédente (sinon un vieux SOS retiendrait GhostDev et laisserait Bash échapper aux arrêts).
#   sh sos-attente.sh fait     hook PostToolUse sur rapport : le diagnostic est parti, on oublie le ticket.
#   sh sos-attente.sh stop     hook Stop : tant que le ticket attend, GhostDev ne finit pas son tour. Deux fois
#                              au plus (le compteur passe à 3 à l'épuisement), puis on lâche : jamais de boucle, et le serveur prévient Anas à 10 minutes.
sh "$(dirname "$0")/actif.sh" || exit 0
. "$(dirname "$0")/chemins.sh"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
proj=$(ghostdev_chemin "$proj")
f="$proj/.machine-a-app/sos-en-attente"
. "$(dirname "$0")/donnees.sh"
entree=""; [ ! -t 0 ] && entree=$(cat 2>/dev/null)
sid=$(ghostdev_champ "$(printf '%s' "$entree" | tr -d '\n\r')" session_id | tr -cd 'A-Za-z0-9_-'); [ -n "$sid" ] || sid=sans-session
case "$1" in
  ouvert)
    # Le numéro se lit dans la réponse de l'outil (« Ticket #42 créé »), jamais dans la demande, qui peut en citer un autre.
    t=$(printf '%s' "$entree" | tr -d '\n\r' | sed -n 's/.*"tool_response"//p' | grep -o 'Ticket #[0-9][0-9]*' | head -1 | tr -cd '0-9')
    [ -n "$t" ] && [ -d "$proj/.machine-a-app" ] || exit 0
    suite=$(printf '%s' "$entree" | tr -d '\n\r' | sed -n 's/.*"tool_input"\(.*\)"tool_response".*/\1/p' | grep -o '"suite_de" *: *[0-9][0-9]*' | head -1 | tr -cd '0-9')
    avant=""; [ -s "$f" ] && avant=$(cut -d' ' -f1 "$f")
    if [ -n "$suite" ] && [ "$suite" = "$avant" ]; then rm -f "$f"; exit 0; fi
    # Le même ticket, dans la même conversation : le compteur continue, il ne repart pas de zéro.
    if [ "$t" = "$avant" ] && [ "$(cut -d' ' -f3 "$f")" = "$sid" ]; then exit 0; fi
    printf '%s 0 %s' "$t" "$sid" > "$f"
    exit 0;;
  fait) rm -f "$f"; exit 0;;
  stop)
    [ -s "$f" ] || exit 0
    if [ "$(cut -d' ' -f3 "$f")" != "$sid" ]; then rm -f "$f"; exit 0; fi
    t=$(cut -d' ' -f1 "$f"); fois=$(cut -d' ' -f2 "$f"); fois=${fois:-0}
    # Le plafond atteint, le fichier reste (épuisé) : un escalader sur le même ticket ne remet pas le compteur à zéro.
    # Le deuxième rappel donné, le compteur passe à 3 : consultation.sh rend alors Bash aux arrêts (il le laisse
    # passer tant que le compteur est sous 3, donc pendant tout le deuxième rappel).
    if [ "$fois" -ge 3 ]; then exit 0; fi
    if [ "$fois" -ge 2 ]; then printf '%s 3 %s' "$t" "$sid" > "$f"; exit 0; fi
    printf '%s %s %s' "$t" "$((fois + 1))" "$sid" > "$f"
    printf '{"decision":"block","reason":"Le SOS #%s attend toujours son diagnostic de lab. Avant de finir : methode_diagnostic, en lecture seule (ou, si rien de cassé, le rapport court), puis rapport avec ticket=%s, langue et resume. Puis termine ton message."}\n' "$t" "$t"
    exit 0;;
esac
exit 0
