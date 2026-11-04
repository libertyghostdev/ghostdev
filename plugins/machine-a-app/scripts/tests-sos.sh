#!/bin/sh
# Essais du mot « SOS » de bout en bout, contre un serveur GhostDev local (jamais la production) :
#   cd produit/serveur && GHOSTDEV_PLAYBOOK_LOCAL=$(mktemp -d) GHOSTDEV_DATA_DIR=$(mktemp -d) GHOSTDEV_ADMIN_TOKEN=adm \
#     ../banc/.travail/venv/bin/python -m uvicorn app:app --host 127.0.0.1 --port 8765     (dans un autre terminal)
#   GHOSTDEV_URL=http://127.0.0.1:8765 GHOSTDEV_ADMIN_TOKEN=adm sh produit/plugin/scripts/tests-sos.sh
# Ce qu'ils gardent : la clé trouvée quel que soit le dossier de données, le ticket qui naît avec ses trois derniers
# messages, le diagnostic de lab demandé dans le même tour (un seul SOS, celui de lab, depuis le 2026-10-03),
# GhostDev retenu tant que le rapport n'est pas parti (deux fois au plus), le ticket ouvert par escalader qui attend
# aussi son rapport, et le ticket rattaché à la personne par son ordinateur quand la clé n'arrive pas.
ici=$(cd "$(dirname "$0")" && pwd)
url="${GHOSTDEV_URL:?mets GHOSTDEV_URL vers un serveur local}"
adm="${GHOSTDEV_ADMIN_TOKEN:?mets GHOSTDEV_ADMIN_TOKEN}"
case "$url" in *ghostdev.libertytechlab.com*) echo "Jamais contre la production."; exit 1;; esac
ok=0; ko=0
verifie() { if [ "$1" = 0 ]; then ok=$((ok+1)); echo "  ok      $2"; else ko=$((ko+1)); echo "  ECHEC   $2"; fi; }
contient() { printf '%s' "$1" | grep -q -- "$2"; }

racine=$(mktemp -d)
export HOME="$racine/maison" CLAUDE_PLUGIN_DATA="$racine/donnees-vides" CLAUDE_PROJECT_DIR="$racine/projet"
export CLAUDE_PLUGIN_ROOT="$(dirname "$ici")" GHOSTDEV_URL="$url"
unset CLAUDE_CONFIG_DIR
mkdir -p "$CLAUDE_PLUGIN_DATA" "$CLAUDE_PROJECT_DIR/.machine-a-app" "$HOME/.claude/plugins/data/machine-a-app-autre"
cle=$(curl -fsS -X POST -H "Authorization: Bearer $adm" -H 'Content-Type: application/json' \
  -d '{"nom":"Essai SOS","email":"essai@exemple.fr"}' "$url/admin/licences" | sed -n 's/.*"cle": *"\([^"]*\)".*/\1/p')
[ -n "$cle" ] || { echo "Le serveur local ne crée pas de licence : est-il lancé ?"; exit 1; }
printf '%s\n' "$cle" > "$HOME/.claude/plugins/data/machine-a-app-autre/licence"

echo "=== La clé et la version partent dans l'en-tête ==="
e=$(sh "$ici/entetes.sh")
contient "$e" "Bearer $cle"; verifie $? "clé trouvée hors du dossier de données du plugin"
contient "$e" '"X-GhostDev-Plugin":"[0-9]'; verifie $? "version du plugin dans l'en-tête"

echo "=== Le SOS naît avec ses derniers messages ==="
tp="$racine/transcript.jsonl"
{
  echo '{"type":"user","message":{"role":"user","content":"premier message, trop ancien"}}'
  echo '{"type":"user","message":{"role":"user","content":"les notifications ne sonnent pas sur iPhone"}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Je regarde."}]}}'
  echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"sortie d outil"}]}}'
  echo '{"type":"user","message":{"role":"user","content":"j ai fait tout ce qu il m a dit"}}'
  echo '{"type":"user","message":{"role":"user","content":"toujours rien"}}'
} > "$tp"
entree=$(printf '{"session_id":"s","transcript_path":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"SOS"}' "$tp" "$CLAUDE_PROJECT_DIR")
sortie=$(printf '%s' "$entree" | sh "$ici/phase.sh")
t=$(printf '%s' "$sortie" | sed -n 's/.*ticket #\([0-9][0-9]*\).*/\1/p' | head -1)
[ -n "$t" ]; verifie $? "ticket ouvert par le hook (#$t)"
[ -s "$CLAUDE_PROJECT_DIR/.machine-a-app/sos-en-attente" ]; verifie $? "ticket noté en attente du diagnostic"
contient "$sortie" "rapport avec ticket=$t"; verifie $? "le message demande le diagnostic de lab du ticket #$t"
fiche=$(curl -fsS -H "Authorization: Bearer $adm" "$url/admin/tickets/$t?prendre=0")
contient "$fiche" "Essai SOS"; verifie $? "ticket au nom de la personne"
for m in "ne sonnent pas" "tout ce qu il m a dit" "toujours rien"; do contient "$fiche" "$m"; verifie $? "message gardé : $m"; done
! contient "$fiche" "trop ancien"; verifie $? "quatrième message en arrière : écarté"
! contient "$fiche" "Je regarde"; verifie $? "réponse de Claude : écartée"
! contient "$fiche" "sortie d outil"; verifie $? "sortie d'outil : écartée"

echo "=== GhostDev ne finit pas son tour sans le diagnostic ==="
stop() { printf '{"session_id":"%s","hook_event_name":"Stop"}' "${1:-s}" | sh "$ici/sos-attente.sh" stop; }
s1=$(stop); contient "$s1" '"decision":"block"'; verifie $? "premier arrêt : retenu"
contient "$s1" "rapport avec ticket=$t"; verifie $? "il sait quel ticket attend son rapport"
s2=$(stop); contient "$s2" '"decision":"block"'; verifie $? "deuxième arrêt : retenu"
s3=$(stop); [ -z "$s3" ]; verifie $? "troisième arrêt : lâché, jamais de boucle"
[ "$(cut -d' ' -f2 "$CLAUDE_PROJECT_DIR/.machine-a-app/sos-en-attente")" = 3 ]; verifie $? "attente épuisée après deux essais (le fichier reste, le compteur ne repart pas)"
printf '%s' "$entree" | sh "$ici/phase.sh" >/dev/null
sh "$ici/sos-attente.sh" fait </dev/null
s4=$(stop); [ -z "$s4" ]; verifie $? "après rapport : plus rien ne retient"

echo "=== Un ticket ouvert par escalader attend aussi son rapport ==="
post='{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"mcp__plugin_machine-a-app_ghostdev__escalader","tool_input":{"probleme":"le build casse comme au Ticket #3"},"tool_response":[{"type":"text","text":"Ticket #42 créé. Anas est prévenu."}]}'
printf '%s' "$post" | sh "$ici/sos-attente.sh" ouvert
[ "$(cat "$CLAUDE_PROJECT_DIR/.machine-a-app/sos-en-attente" 2>/dev/null)" = "42 0 s" ]; verifie $? "le numéro lu dans la réponse d'escalader, pas dans sa demande"
sh "$ici/sos-attente.sh" fait </dev/null

echo "=== Le plafond tient : six arrêts, un escalader entre chaque, deux rappels au plus ==="
printf '%s' "$post" | sh "$ici/sos-attente.sh" ouvert
bloques=0
for i in 1 2 3 4 5 6; do
  r=$(stop); contient "$r" '"decision":"block"' && bloques=$((bloques+1))
  # escalader rappelé sur le même ticket (le plugin d'avant, ou le modèle qui insiste) : le compteur ne repart pas de zéro.
  printf '%s' "$post" | sh "$ici/sos-attente.sh" ouvert
done
[ "$bloques" = 2 ]; verifie $? "deux rappels au plus malgré les escalader ($bloques)"
echo "=== Un escalader qui complète le ticket en attente compte comme le rapport ==="
printf '%s' "$post" | sh "$ici/sos-attente.sh" ouvert
suite='{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"mcp__x__escalader","tool_input":{"probleme":"x","suite_de":42},"tool_response":[{"type":"text","text":"Ticket #42 complété."}]}'
printf '%s' "$suite" | sh "$ici/sos-attente.sh" ouvert
[ ! -e "$CLAUDE_PROJECT_DIR/.machine-a-app/sos-en-attente" ]; verifie $? "suite_de sur le ticket en attente : plus d'attente"
echo "=== Le SOS d'une autre conversation ne retient pas celle-ci ==="
printf '%s' "$post" | sh "$ici/sos-attente.sh" ouvert
r=$(stop autre-session); [ -z "$r" ]; verifie $? "une autre conversation n'est pas retenue"
[ ! -e "$CLAUDE_PROJECT_DIR/.machine-a-app/sos-en-attente" ]; verifie $? "et le vieux fichier est supprimé"

echo "=== Sans clé, le ticket retrouve la personne par son ordinateur ==="
rm -f "$HOME/.claude/plugins/data/machine-a-app-autre/licence"
sleep 1
n=$(curl -fsS -X POST -H 'Content-Type: text/plain' --data-binary '"SOS sans clé"}' "$url/sos?phase=7" | sed -n 's/.*"ticket": *\([0-9][0-9]*\).*/\1/p')
fiche=$(curl -fsS -H "Authorization: Bearer $adm" "$url/admin/tickets/$n?prendre=0")
# Moins de dix minutes après le premier SOS : il s'ajoute à son ticket, qui est bien le sien.
contient "$fiche" '"nom": *"Essai SOS"'; verifie $? "SOS sans clé rattaché à la personne (#$n)"

echo "=== Le mot écrit par elle, jamais celui d'un texte collé (ticket 36) ==="
# Sans réseau : un SOS reconnu se voit à la consigne de repli « Mot-clé SOS reçu : appelle l'outil escalader ».
colle=$(printf 'Voici la transcription de la séance, le client parle de ses écrans. %.0s' 1 2 3 4 5 6 7)
mot() { printf '{"session_id":"s6","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$CLAUDE_PROJECT_DIR" "$1" \
  | GHOSTDEV_URL=http://127.0.0.1:9 sh "$ici/phase.sh" | grep -c "Mot-clé SOS"; }
rm -f "$CLAUDE_PROJECT_DIR/.machine-a-app/sos-en-attente"
[ "$(mot "${colle} Le client dit : SOS, je suis perdu. ${colle}")" = 0 ]; verifie $? "SOS au milieu d'un texte collé : ignoré"
[ "$(mot "${colle}${colle}\\nSOS")" = 1 ]; verifie $? "texte collé, puis SOS écrit à la fin : reconnu"
[ "$(mot 'le build casse encore\nSOS')" = 1 ]; verifie $? "SOS sur sa propre ligne : reconnu"

echo "=== Hors d'un dossier GhostDev : muet ==="
rm -rf "$CLAUDE_PROJECT_DIR/.machine-a-app"
s5=$(printf '%s' "$entree" | sh "$ici/phase.sh"; sh "$ici/sos-attente.sh" stop </dev/null); [ -z "$s5" ]; verifie $? "aucun ticket, aucun blocage"

rm -rf "$racine"
echo; echo "$ok réussis, $ko en échec"
[ "$ko" = 0 ]
