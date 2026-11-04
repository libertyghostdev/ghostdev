#!/bin/sh
# Rappel discret de la phase en cours, à chaque message de la personne. Le hook reçoit sur stdin un JSON
# avec le message (« prompt ») : si elle a écrit « turbo », la tâche suivante va au sous-agent dessinateur.
sh "$(dirname "$0")/actif.sh" || exit 0   # muet tant que GhostDev n'a pas été lancé dans ce dossier
# Le dossier du plugin est-il entier ? sante.sh le répare en fond s'il manque un fichier. S'il manque lui-même, il
# revient de l'archive du serveur, et la fois suivante fait le reste. Rien n'est jamais dit à la personne.
sante="$(dirname "$0")/sante.sh"
if [ -f "$sante" ]; then sh "$sante" >/dev/null 2>&1
elif [ -z "$GHOSTDEV_EN_REPARATION" ]; then
  (t=$(mktemp -d) && curl -fsS -m 30 "${GHOSTDEV_URL:-https://ghostdev.libertytechlab.com}/plugin/archive.tgz" -o "$t/p.tgz" \
    && tar -xzf "$t/p.tgz" -C "$t" && cp "$t/scripts/sante.sh" "$sante.tmp" && mv -f "$sante.tmp" "$sante"; rm -rf "$t") </dev/null >/dev/null 2>&1 &
fi
. "$(dirname "$0")/chemins.sh"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
proj=$(ghostdev_chemin "$proj")
# En démo, le moteur du dossier dicte chaque geste : un rappel de phase ou de decisions.md le contredirait.
[ -f "$proj/.demo/scenario" ] && exit 0
entree=""; [ ! -t 0 ] && entree=$(cat 2>/dev/null)
# V2 : la session est-elle servie par l'arbre ? (demarrage.sh pose le fichier « v2 » de la session). Si oui, chaque
# message rouvre l'obligation de consulter guide avant le premier geste ; consultation.sh et fin-de-tour.sh la tiennent.
. "$(dirname "$0")/donnees.sh"
sess=$(ghostdev_session "$(ghostdev_champ "$(printf '%s' "$entree" | tr -d '\n\r')" session_id)")
# « lance GhostDev » passe par lancer.sh, qui n'a pas de session : la V2 attend dans le dossier, et ce premier
# message de la conversation l'adopte.
if [ ! -f "$sess/v2" ] && [ -f "$proj/.machine-a-app/v2-en-attente" ]; then rm -f "$proj/.machine-a-app/v2-en-attente"; touch "$sess/v2"; fi
v2=""; if [ -f "$sess/v2" ]; then v2=1; printf 0 > "$sess/consulter"; fi
f="$proj/.machine-a-app/etat.json"
n=""; [ -s "$f" ] && n=$(sed -n 's/.*"phase": *\([0-9][0-9]*\).*/\1/p' "$f" | head -1)
# Les deux mots-clés, cherchés dans son message seulement (le champ prompt, pas le chemin du dossier).
message=$(printf '%s' "$entree" | sed -n 's/.*"prompt" *: *//p')
url="${GHOSTDEV_URL:-https://ghostdev.libertytechlab.com}"
# « SOS » : elle demande de l'aide. Un client a perdu douze heures sans jamais oser le demander, et un autre
# a écrit « SOS » deux fois sans que le modèle escalade (2026-09-25). Le mot ne dépend donc plus du modèle :
# ce script ouvre lui-même le ticket et prévient Anas, puis le modèle fait le diagnostic de lab et l'envoie par rapport.
# Le mot ne compte que là où elle l'écrit elle-même : un message court, ou le début ou la fin d'un long message.
# Un texte collé (une transcription, un journal) le porte au milieu : le ticket 36 est parti pour rien. Les retours à
# la ligne arrivent écrits « \n » dans le JSON : ils deviennent des espaces, sinon le « n » colle au mot.
zone=$(printf '%s' "$message" | sed 's/\\n/ /g')
if [ ${#zone} -gt 400 ]; then zone="$(printf '%s' "$zone" | head -c 120) $(printf '%s' "$zone" | tail -c 120)"; fi
if printf '%s' "$zone" | grep -qi -E "(^|[^[:alpha:]])(sos|au secours|escalade|appelle anas|previens anas|prévi(e|è)ns anas)([^[:alpha:]]|\$)"; then
  entetes=$(sh "$(dirname "$0")/entetes.sh" 2>/dev/null)
  cle=$(printf '%s' "$entetes" | sed -n 's/.*"Bearer \([^"]*\)".*/\1/p')
  v=$(printf '%s' "$entetes" | sed -n 's/.*"X-GhostDev-Plugin":"\([^"]*\)".*/\1/p')
  # Ses derniers messages partent avec le SOS (décidé par Anas le 2026-10-01) : le ticket ne naît plus vide
  # quand le modèle tarde à le compléter. On envoie les dernières lignes « user » du transcript ; le serveur
  # n'en garde que ses trois derniers messages à elle, sans réponses de Claude ni sorties d'outils, et masque
  # les clés, emails et numéros de carte.
  tp=$(printf '%s' "$entree" | sed -n 's/.*"transcript_path" *: *"\([^"]*\)".*/\1/p' | sed 's/\\\\/\\/g')
  tp=$(ghostdev_chemin "$tp")
  derniers=""
  [ -n "$tp" ] && [ -f "$tp" ] && derniers=$(grep '"type": *"user"' "$tp" 2>/dev/null | grep -v '"tool_result"' | tail -n 12 | tail -c 60000)
  t=$( { printf '%s' "$message"; [ -n "$derniers" ] && printf '\n<<<GHOSTDEV-DERNIERS>>>\n%s' "$derniers"; } \
      | curl -fsS -m 4 -X POST -H "Authorization: Bearer $cle" -H "X-GhostDev-Plugin: $v" -H 'Content-Type: text/plain' \
      --data-binary @- "$url/sos?phase=$n" 2>/dev/null | sed -n 's/.*"ticket": *\([0-9][0-9]*\).*/\1/p')
  if [ -n "$t" ]; then
    # Le ticket attend le diagnostic de lab : sos-attente.sh empêche GhostDev de finir son tour sans l'avoir envoyé.
    mkdir -p "$proj/.machine-a-app" 2>/dev/null && printf '%s 0 %s' "$t" "$(basename "$sess")" > "$proj/.machine-a-app/sos-en-attente"
    g=""; [ -n "$v2" ] && g="consulte guide, comme à chaque message, puis "
    echo "Mot-clé SOS reçu. Anas est déjà prévenu : le ticket #$t est parti tout seul avec son message et ses derniers messages ; n'appelle pas escalader. Dans ce même tour, dans l'ordre. 1. Dis-lui en une phrase, dans sa langue, sans question : « Je préviens Anas, et je lui prépare un dossier complet pour qu'il trouve vite. Je regarde sans rien toucher, ça prend quelques minutes. » 2. ${g}appelle methode_diagnostic et fais le diagnostic de lab, en lecture seule. 3. Envoie-le par l'outil rapport avec ticket=$t, langue (la sienne) et resume (sa demande en une phrase de tous les jours, sans mot technique : elle part dans ses mails). 4. Reprends sur autre chose, sans retoucher la chose bloquée avant la réponse d'Anas."
  else
    echo "Mot-clé SOS reçu : appelle l'outil escalader maintenant avec la chose bloquée en une ligne, sans lui demander son accord et sans une question de plus. Sa réponse te donne la suite : le diagnostic de lab, dans ce même tour."
  fi
  exit 0
fi
if [ -n "$v2" ]; then
  echo "GhostDev : consulte guide avant ta réponse et avant ton premier geste. Ce que la personne vient d'apporter de nouveau (une décision, un goût, un refus, un « plus tard », sa façon de travailler) va dans .machine-a-app/memoire/, dans ce même tour."
else
[ -n "$n" ] && echo "Rappel GhostDev : phase $n en cours. Une seule étape à la fois. Ce qu'elle vient de dire aimer, refuser ou décider va dans decisions.md avant ta réponse, et tu le dis en une ligne. Si elle a écrit « turbo », la tâche suivante va au sous-agent dessinateur."
fi
# « turbo » : cerveau fort.
if printf '%s' "$message" | grep -qi -E '(^|[^[:alpha:]])turbo([^[:alpha:]]|$)'; then
  echo "Mot-clé turbo reçu : confie la prochaine tâche au dessinateur."
fi
# Le contenu du serveur a-t-il changé depuis le dernier message ? Si oui, la machine relit avant de répondre.
vu="$proj/.machine-a-app/contenu.version"
# Le même appel porte la clé : s'il y a une demande de diagnostic de lab d'Anas, le serveur la joint, une seule fois.
ent=$(sh "$(dirname "$0")/entetes.sh" 2>/dev/null)
ck=$(printf '%s' "$ent" | sed -n 's/.*"Bearer \([^"]*\)".*/\1/p')
v=$(printf '%s' "$ent" | sed -n 's/.*"X-GhostDev-Plugin":"\([^"]*\)".*/\1/p')
reponse=$(curl -fsS -m 2 -H "Authorization: Bearer $ck" -H "X-GhostDev-Plugin: $v" "$url/contenu/version" 2>/dev/null)
distante=$(printf '%s' "$reponse" | sed -n 's/.*"commit": *"\([^"]*\)".*/\1/p')
diag=$(printf '%s' "$reponse" | sed -n 's/.*"diagnostic": *"\(.*\)"}$/\1/p' | sed 's/\\n/ /g; s/\\"/"/g')
[ -n "$diag" ] && echo "GhostDev, demande d'Anas : $diag"
if [ -n "$distante" ]; then
  if [ -s "$vu" ] && [ "$(cat "$vu")" != "$distante" ] && [ -n "$v2" ]; then
    rm -f "$sess/lues"
    echo "GhostDev : le contenu du serveur a changé (Anas vient de l'améliorer). À ta prochaine consultation de guide, passe deja_lues vide : les fiches te reviennent à jour."
  elif [ -s "$vu" ] && [ "$(cat "$vu")" != "$distante" ]; then
    echo "GhostDev : le contenu du serveur a changé (Anas vient de l'améliorer). Avant de répondre, rappelle l'outil consignes et contenu_phase de la phase en cours, puis continue avec la version à jour, sans le dire à la personne autrement qu'en une phrase."
  fi
  printf '%s' "$distante" > "$vu"
fi
exit 0
