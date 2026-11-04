#!/bin/sh
# Batterie des hooks de la V2 (consultation, arrêts, mémoire, fin de tour, blocage). À lancer après toute modification :
#   sh produit/plugin/scripts/tests-v2.sh
ici=$(cd "$(dirname "$0")" && pwd)
proj=$(mktemp -d); data=$(mktemp -d)
export CLAUDE_PROJECT_DIR="$proj" CLAUDE_PLUGIN_ROOT="$(dirname "$ici")" CLAUDE_PLUGIN_DATA="$data"
mkdir -p "$proj/.machine-a-app/memoire"
cat > "$proj/.machine-a-app/etat.json" <<'J'
{
  "phase": 7,
  "technique": "flutter",
  "route": "app",
  "chantier": {"sujet": "notifications de course", "moment": "nouvelle_fonction", "strategie": "ST-01", "etape": 3, "fiches": ["ST-01", "NO-01"]}
}
J
cat > "$proj/.machine-a-app/memoire/gouts.md" <<'J'
- M-0001 · 2026-10-01 · [domaine:notifications] · une course sonne comme une notification, jamais comme un appel · « ça doit pas s'afficher comme un appel »
- M-0002 · 2026-10-01 · [domaine:design] [ecran:accueil] · vert pastel · « je dis vert-pastel »
J
cat > "$proj/.machine-a-app/memoire/plus-tard.md" <<'J'
- M-0003 · 2026-09-20 · [ecran:connexion] · le message d'erreur du mot de passe · quand: phase=7 ecran=connexion · état: en attente
- M-0004 · 2026-09-20 · [ecran:accueil] · l'ombre des cartes · quand: phase=8 · état: en attente
- M-0005 · 2026-09-20 · [ecran:connexion] · déjà fait · quand: phase=7 · état: fait
J
ok=0; ko=0
verifie() {  # $1 = libellé, $2 = attendu (contient | absent | vide), $3 = motif, $4 = sortie
  case "$2" in
    contient) printf '%s' "$4" | grep -q -- "$3" && r=1 || r="" ;;
    absent) printf '%s' "$4" | grep -q -- "$3" && r="" || r=1 ;;
    vide) [ -z "$4" ] && r=1 || r="" ;;
  esac
  if [ -n "$r" ]; then ok=$((ok+1)); printf "  ok      %s\n" "$1"; else ko=$((ko+1)); printf "  ECHEC   %s\n     sortie : %s\n" "$1" "$4"; fi
}
outil() { printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$1" "${2:-{\}}" | sh "$ici/consultation.sh"; }
guide_entree='{"moment":"nouvelle_fonction","domaine":"notifications","situation":"ajouter les notifications","ecran":"connexion","phase":7,"technique":"flutter"}'
sess="$data/sessions/s1"

echo "=== Avant la V2 : rien ne bloque ==="
mkdir -p "$sess"; printf 0 > "$sess/consulter"
verifie "session sans marque v2" vide "" "$(outil Bash '{"command":"ls"}')"

echo "=== Consultation obligatoire ==="
touch "$sess/v2"; printf 0 > "$sess/consulter"
verifie "Bash refusé avant guide" contient '"permissionDecision":"deny"' "$(outil Bash '{"command":"ls"}')"
verifie "la raison nomme guide" contient "consulte d'abord guide" "$(outil Read '{"file_path":"a"}')"
verifie "escalader passe (SOS)" vide "" "$(outil mcp__plugin_machine-a-app_ghostdev__escalader '{}')"
verifie "ToolSearch passe" vide "" "$(outil ToolSearch '{}')"
verifie "guide passe" vide "" "$(outil mcp__plugin_machine-a-app_ghostdev__guide "$guide_entree")"
verifie "guide avec une fausse phase refusé" contient "phase=7" "$(outil mcp__plugin_machine-a-app_ghostdev__guide '{"moment":"repondre","situation":"x","phase":5}')"
verifie "guide avec une fausse technique refusé" contient "technique=flutter" "$(outil mcp__plugin_machine-a-app_ghostdev__guide '{"moment":"repondre","situation":"x","technique":"web"}')"
printf 0 > "$sess/consulter"
outil Bash '{}' >/dev/null; outil Bash '{}' >/dev/null; outil Bash '{}' >/dev/null
verifie "après trois refus, on laisse passer" vide "" "$(outil Bash '{"command":"ls"}')"

echo "=== Après guide : la mémoire ==="
printf 0 > "$sess/consulter"
reponse='"tool_response":[{"type":"text","text":"## Étape en cours\n<fiche id=\"NO-01\" couche=\"savoir-faire\">\n\n<arrets></arrets>"}]'
m=$(printf '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"mcp__plugin_machine-a-app_ghostdev__guide","tool_input":%s,%s}' "$guide_entree" "$reponse" | sh "$ici/memoire.sh")
verifie "drapeau levé" vide "" "$( [ -f "$sess/consulter" ] && echo encore )"
verifie "le goût du domaine sort" contient "M-0001" "$m"
verifie "le goût d'un autre domaine ne sort pas" absent "M-0002" "$m"
verifie "la note plus tard de l'écran connexion en phase 7 sort" contient "M-0003" "$m"
verifie "la note d'une autre phase ne sort pas" absent "M-0004" "$m"
verifie "une note faite ne sort pas" absent "M-0005" "$m"
verifie "le chantier en cours" contient "Chantier en cours : notifications de course · stratégie ST-01 · étape 3" "$m"
verifie "les fiches déjà lues" contient "deja_lues) : NO-01" "$m"
verifie "c'est du JSON de hook" contient '"hookEventName":"PostToolUse","additionalContext":' "$m"
verifie "Bash passe après guide" vide "" "$(outil Bash '{"command":"ls"}')"
verifie "le journal des injections note les numéros" contient "M-0001" "$(cat "$sess/injections.log" 2>/dev/null)"
verifie "le journal ne garde jamais le texte" absent "course sonne" "$(cat "$sess/injections.log" 2>/dev/null)"

echo "=== Une mémoire longue : ce qui est dit est ce qui est noté ==="
cp "$proj/.machine-a-app/memoire/gouts.md" "$proj/gouts.bak"
i=10; while [ $i -le 21 ]; do
  printf -- '- M-00%s · 2026-10-01 · [domaine:notifications] · %s\n' "$i" "$(printf 'une longue préférence sur les notifications de course %.0s' 1 2 3 4)" >> "$proj/.machine-a-app/memoire/gouts.md"
  i=$((i+1))
done
printf 0 > "$sess/consulter"
m=$(printf '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"mcp__plugin_machine-a-app_ghostdev__guide","tool_input":%s,%s}' "$guide_entree" "$reponse" | sh "$ici/memoire.sh")
verifie "mémoire longue : la note plus tard arrivée passe d'abord" contient "M-0003" "$m"
absents=""; for x in $(tail -1 "$sess/injections.log" | grep -o 'M-[0-9]*'); do printf '%s' "$m" | grep -q -- "$x" || absents="$absents $x"; done
verifie "mémoire longue : le journal ne note que ce qui est dit" vide "" "$absents"
verifie "mémoire longue : le chantier reste" contient "Chantier en cours" "$m"
mv "$proj/gouts.bak" "$proj/.machine-a-app/memoire/gouts.md"

echo "=== Ce que Claude Code peut envoyer autrement ==="
printf 0 > "$sess/consulter"
m=$(printf '{"session_id":"s1",%s,"hook_event_name":"PostToolUse","tool_name":"mcp__plugin_machine-a-app_ghostdev__guide","tool_input":{"moment":"nouvelle_fonction","domaine":"notifications","situation":"r\\u00e9glage \\"domaine\\": \\"design\\"","ecran":"Connexion","phase":7}}' "$reponse" | sh "$ici/memoire.sh")
verifie "réponse avant l'entrée, accents échappés : le bon domaine" contient "M-0001" "$m"
verifie "un faux domaine dans la phrase ne compte pas" absent "M-0002" "$m"
verifie "écran en majuscules : la note sort quand même" contient "M-0003" "$m"

echo "=== Relecture : sous-agents, réponses cliquées, route, fin de tour ==="
printf 0 > "$sess/consulter"
verifie "un sous-agent n'est pas arrêté" vide "" "$(printf '{"session_id":"s1","agent_id":"sub1","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"a"}}' | sh "$ici/consultation.sh")"
printf '{"session_id":"s1","agent_id":"sub1","hook_event_name":"PostToolUse","tool_name":"mcp__plugin_machine-a-app_ghostdev__guide","tool_input":%s,%s}' "$guide_entree" "$reponse" | sh "$ici/memoire.sh" >/dev/null
verifie "le guide d'un sous-agent ne lève pas le drapeau de la conversation" vide "" "$( [ -f "$sess/consulter" ] || echo levé )"
rm -f "$sess/consulter"
printf '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"AskUserQuestion","tool_input":{},"tool_response":"oui"}' | sh "$ici/consultation.sh" >/dev/null
verifie "une réponse cliquée rouvre la consultation" vide "" "$( [ -f "$sess/consulter" ] || echo absent )"
verifie "guide avec une autre route refusé" contient "route=app" "$(outil mcp__plugin_machine-a-app_ghostdev__guide '{"moment":"repondre","situation":"x","route":"web"}')"
printf 0 > "$sess/consulter"
verifie "fin de tour : redonner la réponse en entier" contient "redonne ta réponse en entier" "$(printf '{"session_id":"s1","stop_hook_active":false}' | sh "$ici/fin-de-tour.sh")"
rm -f "$sess/consulter"

echo "=== Relecture : la mémoire la plus précise d'abord ==="
for i in 10 11 12 13 14 15 16 17 18 19 20 21; do printf -- '- M-00%s · 2026-09-01 · [phase:7] · décision de phase %s\n' "$i" "$i" >> "$proj/.machine-a-app/memoire/decisions.md"; done
printf -- '- M-0099 · 2026-10-02 · [ecran:connexion] · le bouton se lit en blanc sur vert\n' >> "$proj/.machine-a-app/memoire/gouts.md"
printf -- '- M-0098 · 2026-10-02 · [domaine:notifications] · la clé est dans C:\\Users\\moi\\cles\n' > "$proj/.machine-a-app/memoire/faits.md"
printf 0 > "$sess/consulter"
m=$(printf '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"mcp__plugin_machine-a-app_ghostdev__guide","tool_input":%s,%s}' "$guide_entree" "$reponse" | sh "$ici/memoire.sh")
verifie "l'écran passe devant douze décisions de phase" contient "M-0099" "$m"
verifie "un antislash reste du JSON valide" contient "^ok$" "$(printf '%s' "$m" | python3 -c 'import json,sys; json.load(sys.stdin); print("ok")' 2>&1)"
rm -f "$proj/.machine-a-app/memoire/faits.md"

echo "=== Guide injoignable ==="
printf 0 > "$sess/consulter"
m=$(printf '{"session_id":"s1","hook_event_name":"PostToolUseFailure","tool_name":"mcp__plugin_machine-a-app_ghostdev__guide","tool_input":%s}' "$guide_entree" | sh "$ici/memoire.sh")
verifie "message prudent" contient "injoignable" "$m"
verifie "drapeau levé quand même" vide "" "$( [ -f "$sess/consulter" ] && echo encore )"

echo "=== Fin de tour ==="
printf 0 > "$sess/consulter"
verifie "fin de tour sans consulter : bloquée" contient '"decision":"block"' "$(printf '{"session_id":"s1","stop_hook_active":false}' | sh "$ici/fin-de-tour.sh")"
verifie "deuxième fois : on laisse finir" vide "" "$(printf '{"session_id":"s1","stop_hook_active":true}' | sh "$ici/fin-de-tour.sh")"
verifie "et le drapeau est oublié" vide "" "$( [ -f "$sess/consulter" ] && echo encore )"
verifie "fin de tour après consultation : rien" vide "" "$(printf '{"session_id":"s1","stop_hook_active":false}' | sh "$ici/fin-de-tour.sh")"

echo "=== Navigation : les arrêts, les étapes d'après, le compteur de blocage ==="
garde="mcp__plugin_machine-a-app_ghostdev__guide"
apres_guide() { printf '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":%s,"tool_response":[{"type":"text","text":"%s"}]}' "$garde" "$guide_entree" "$1" | sh "$ici/memoire.sh"; }
rm -f "$sess/consulter" "$sess/lues" "$sess/arrets" "$sess/arrets-refus" "$sess/apres" "$sess/change"
apres_guide 'Type : bug\n\n<arrets>ST-07</arrets>\n\n<apres>bug</apres>' >/dev/null
verifie "le premier geste qui change est refusé tant que la stratégie n'est pas lue" contient 'lis d.abord ST-07' "$(outil Edit '{"file_path":"/p/lib/a.dart"}')"
printf '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"mcp__plugin_machine-a-app_ghostdev__lire_fiche","tool_input":{"id":"ST-07"},"tool_response":[{"type":"text","text":"<fiche id=\\"ST-07\\" couche=\\"strategie\\">"}]}' | sh "$ici/arrets.sh"
verifie "la stratégie lue par lire_fiche : le geste passe" vide "" "$(outil Edit '{"file_path":"/p/lib/a.dart"}')"
# Pendant un SOS en attente de son rapport (même conversation), Bash passe malgré les arrêts, Edit non ; le fichier d'une
# autre conversation est périmé : il tombe, et les arrêts bloquent de nouveau Bash.
printf 'ST-08\n' > "$sess/arrets"; rm -f "$sess/consulter" "$sess/arrets-refus"
printf '42 0 s1' > "$proj/.machine-a-app/sos-en-attente"
verifie "SOS en attente : Bash passe malgré les arrêts" vide "" "$(outil Bash '{"command":"ls"}')"
verifie "SOS en attente : Edit reste refusé" contient '"permissionDecision":"deny"' "$(outil Edit '{"file_path":"/p/lib/a.dart"}')"
printf '42 2 s1' > "$proj/.machine-a-app/sos-en-attente"; rm -f "$sess/arrets-refus"
verifie "pendant le deuxième rappel (compteur à 2) : Bash passe encore" vide "" "$(outil Bash '{"command":"ls"}')"
printf '42 3 s1' > "$proj/.machine-a-app/sos-en-attente"; rm -f "$sess/arrets-refus"
verifie "attente épuisée (compteur à 3) : Bash retombe sous les arrêts" contient '"permissionDecision":"deny"' "$(outil Bash '{"command":"ls"}')"
rm -f "$sess/arrets-refus"
rm -f "$sess/arrets-refus"; printf '42 0 autre-session' > "$proj/.machine-a-app/sos-en-attente"
verifie "SOS d'une autre conversation : Bash refusé de nouveau" contient '"permissionDecision":"deny"' "$(outil Bash '{"command":"ls"}')"
verifie "et son fichier est supprimé" vide "" "$( [ -e "$proj/.machine-a-app/sos-en-attente" ] && echo reste )"
rm -f "$sess/arrets-refus"
printf 'ST-08\n' > "$sess/arrets"
outil Bash '{"command":"x"}' >/dev/null; outil Bash '{"command":"x"}' >/dev/null; outil Bash '{"command":"x"}' >/dev/null
verifie "jamais plus de trois refus par message" vide "" "$(outil Bash '{"command":"x"}')"
printf 0 > "$sess/consulter"
printf '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"type":"bug"},"tool_response":[{"type":"text","text":"Refusé : avant d'\''agir"}]}' "$garde" | sh "$ici/memoire.sh" >/dev/null
verifie "un guide refusé (sans demande ni besoins) laisse la consultation due" vide "" "$( [ -f "$sess/consulter" ] || echo levé )"
rm -f "$sess/consulter"; printf bug > "$sess/apres"; rm -f "$sess/change"
outil Edit '{"file_path":"/p/.machine-a-app/memoire/gouts.md"}' >/dev/null
verifie "écrire dans la mémoire ne compte pas comme un changement" vide "" "$(printf '{"session_id":"s1","stop_hook_active":false}' | sh "$ici/fin-de-tour.sh")"
m=$(apres_guide 'Type : reponse_courte\n\n<arrets></arrets>')
case "$m" in *"fiches ST-01 NO-01"*) ;; *) ko=$((ko+1)); printf "  ECHEC   le chantier rend ses fiches après un oui\n     sortie : %s\n" "$m" ;; esac
outil Edit '{"file_path":"/p/lib/main.dart"}' >/dev/null
s=$(printf '{"session_id":"s1","stop_hook_active":false}' | sh "$ici/fin-de-tour.sh")
verifie "un fichier changé : les étapes d'après rappelées une fois, sans bloquer" contient '"hookEventName":"Stop","additionalContext":"GhostDev, avant de finir' "$s"
verifie "une réponse courte garde les étapes d'après de son chantier" contient "type « bug »" "$s"
rm -f "$sess/echecs" "$sess/arrets"
bl() { printf '{"session_id":"s1","hook_event_name":"%s","tool_name":"Bash","tool_input":{"command":"%s"}%s}' "$1" "$2" "$3" | sh "$ici/blocage.sh"; }
e=',"error":"Exit code 1\nFAILURE: Build failed with an exception.","is_interrupt":false'
for c in 'grep -rn foo lib' 'grep -rn foo lib' 'grep -rn foo lib'; do bl PostToolUseFailure "$c" "$e" >/dev/null; done
verifie "une recherche qui ne trouve rien n'est pas un échec" vide "" "$(cat "$sess/echecs" 2>/dev/null)"
bl PostToolUseFailure 'cd app && flutter build apk --release' "$e" >/dev/null
bl PostToolUseFailure 'flutter build appbundle' "$e" >/dev/null
verifie "troisième échec sur la même chose, quelle que soit la cause : ST-09 et l'escalade" contient 'puis appelle l.outil escalader' "$(bl PostToolUseFailure 'FOO=1 flutter build ipa' "$e")"
verifie "et ST-09 entre dans les arrêts" contient "ST-09" "$(cat "$sess/arrets" 2>/dev/null)"
rm -f "$sess/echecs" "$sess/arrets"
for c in 'flutter analyze' 'cd app && flutter analyze lib' 'npx eslint src'; do bl PostToolUseFailure "$c" "$e" >/dev/null; done
verifie "trois flutter analyze ou eslint en échec ne déclenchent rien" vide "" "$(cat "$sess/echecs" "$sess/arrets" 2>/dev/null)"
bl PostToolUseFailure 'npm run build' "$e" >/dev/null; bl PostToolUseFailure 'npm run test' "$e" >/dev/null; bl PostToolUseFailure 'npm run build' "$e" >/dev/null
verifie "npm run build, npm run test, npm run build : deux choses, jamais trois échecs de la même, pas de ST-09" vide "" "$(cat "$sess/arrets" 2>/dev/null)"
rm -f "$sess/echecs" "$sess/arrets"
bl PostToolUseFailure 'cd \"mon app\" && flutter build ipa' "$e" >/dev/null; bl PostToolUseFailure 'cd \"mon app\" && flutter build ipa' "$e" >/dev/null
verifie "une commande à guillemets échappés compte aussi : ST-09 au troisième échec" contient 'puis appelle l.outil escalader' "$(bl PostToolUseFailure 'cd \"mon app\" && flutter build ipa' "$e")"
rm -f "$sess/echecs" "$sess/arrets" "$sess/apres"


echo "=== Démarrage, message, geste : avec un serveur local ==="
srv=$(mktemp -d); mkdir -p "$srv/arbre/fiche"
printf '%s\n' "Tu tutoies la personne. Une étape à la fois." > "$srv/socle"
printf '[\n {"id": "ST-02", "sur": "outil", "niveau": "rappel", "phases": "7", "motif": "androidpublisher"}\n]\n' > "$srv/arbre/declencheurs.json"
printf '%s\n' "### ST-02 · Avant un envoi à un store" "**Le but :** un envoi qui ne relance pas un examen." > "$srv/arbre/fiche/ST-02"
mkdir -p "$srv/contenu"; printf '{"commit": "neuf"}' > "$srv/contenu/version"
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
( cd "$srv" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 ) & serveur=$!
sleep 1
export GHOSTDEV_URL="http://127.0.0.1:$port" GHOSTDEV_SANS_MAJ=1
rm -f "$sess/v2"
d=$(printf '{"session_id":"s1","source":"startup"}' | sh "$ici/demarrage.sh")
verifie "le socle a son propre hook : pas dans demarrage.sh" absent "<ghostdev-socle>" "$d"
verifie "en V2, le démarrage ne renvoie à aucun outil de la V1" absent "chercher_playbook\|contenu_phase" "$d"
mkdir -p "$proj/.machine-a-app/reflexion"; printf 'le prix : 9 euros\n' > "$proj/.machine-a-app/reflexion/prix.md"
r=$(printf '{"session_id":"s1","source":"startup"}' | sh "$ici/demarrage.sh")
verifie "en V2, une réflexion rangée va dans la mémoire" contient "memoire/decisions.md" "$r"
verifie "en V2, plus de « Décidé » de la V1" absent "Décidé" "$r"
rm -rf "$proj/.machine-a-app/reflexion"
verifie "socle.sh donne le socle" contient "<ghostdev-socle>" "$(printf '{"session_id":"s1","source":"startup"}' | sh "$ici/socle.sh")"
verifie "la session est marquée v2" vide "" "$( [ -f "$sess/v2" ] || echo absente )"
verifie "le chantier en cours au démarrage" contient "Chantier en cours : notifications de course" "$d"
verifie "plus de decisions.md en V2" absent "decisions.md, les 20" "$d"
rm -f "$proj/.machine-a-app/v2-en-attente"
d=$(sh "$ici/demarrage.sh" </dev/null)
verifie "lancé par lancer.sh : le socle est dans la sortie" contient "<ghostdev-socle>" "$d"
verifie "lancé par lancer.sh : la V2 attend la session" vide "" "$( [ -f "$proj/.machine-a-app/v2-en-attente" ] || echo absente )"
p=$(printf '{"session_id":"s2","prompt":"bonjour"}' | sh "$ici/phase.sh")
verifie "le premier message adopte la V2" vide "" "$( [ -f "$data/sessions/s2/v2" ] || echo absente )"
verifie "et rouvre la consultation" contient "consulte guide avant ta réponse" "$p"
printf 'ST-01\n' > "$sess/lues"
d=$(printf '{"session_id":"s1","source":"compact"}' | sh "$ici/demarrage.sh")
verifie "après un compactage : les fiches du chantier à relire" contient "fiches du chantier (ST-01 NO-01)" "$d"
verifie "après un compactage : la liste des lues est vidée" vide "" "$( [ -f "$sess/lues" ] && echo encore )"
printf '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"mcp__plugin_machine-a-app_ghostdev__guide","tool_input":%s,%s}' "$guide_entree" "$reponse" | sh "$ici/memoire.sh" >/dev/null
verifie "après un compactage, le journal le dit" contient "après compactage · .*M-0003" "$(tail -1 "$sess/injections.log" 2>/dev/null)"
verifie "pas de rappel de consignes en V2" absent "rappelle consignes" "$d"
rm -rf "$proj/.machine-a-app/memoire.bak"; mv "$proj/.machine-a-app/memoire" "$proj/.machine-a-app/memoire.bak"
printf '# Décisions\n- vert pastel\n' > "$proj/.machine-a-app/decisions.md"
verifie "passage à la V2 annoncé" contient 'lire_fiche(\"ME-01\")\|lire_fiche("ME-01")' "$(printf '{"session_id":"s1","source":"startup"}' | sh "$ici/demarrage.sh")"
mv "$proj/.machine-a-app/memoire.bak" "$proj/.machine-a-app/memoire"; rm -f "$proj/.machine-a-app/decisions.md"
rm -f "$sess/consulter"
p=$(printf '{"session_id":"s1","prompt":"ajoute les notifications"}' | sh "$ici/phase.sh")
verifie "le message rouvre la consultation" vide "" "$( [ -f "$sess/consulter" ] || echo absent )"
verifie "le rappel V2" contient "consulte guide avant ta réponse" "$p"
printf 'ancien' > "$proj/.machine-a-app/contenu.version"; printf 'GP-01\n' > "$sess/lues"
p=$(printf '{"session_id":"s1","prompt":"et maintenant ?"}' | sh "$ici/phase.sh")
verifie "contenu changé : deja_lues vide" contient "passe deja_lues vide" "$p"
verifie "contenu changé : la liste des lues est vidée" vide "" "$( [ -f "$sess/lues" ] && echo encore )"
rm -f "$sess/consulter"
f=$(printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"curl https://androidpublisher.googleapis.com/x"}}' | sh "$ici/fiches.sh")
verifie "un geste connu apporte sa fiche" contient "ST-02 · Avant un envoi" "$f"
verifie "sans jamais bloquer" absent '"deny"' "$f"
f=$(printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"curl https://androidpublisher.googleapis.com/x"}}' | sh "$ici/fiches.sh")
verifie "une seule fois par demi-heure" vide "" "$f"
printf '[\n {"id": "AS-02", "sur": "outil", "niveau": "rappel", "phases": "", "motif": "altool"},\n {"id": "ST-06", "sur": "outil", "niveau": "rappel", "phases": "", "motif": "altool"}\n]\n' > "$srv/arbre/declencheurs.json"
{ printf '### AS-02 · App Store : une mise à jour\n'; head -c 6000 /dev/zero | tr '\0' a; } > "$srv/arbre/fiche/AS-02"
{ printf '### ST-06 · Avant un envoi\n'; head -c 6000 /dev/zero | tr '\0' b; } > "$srv/arbre/fiche/ST-06"
rm -rf "$proj/.machine-a-app/fiches"
f=$(printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"xcrun altool --upload-app"}}' | sh "$ici/fiches.sh")
verifie "deux fiches pour un geste : celle qui ne tient pas dans le hook est nommée" contient "Aussi pour ce geste, à lire par lire_fiche : ST-06." "$f"
rm -f "$sess/v2"
printf '{"session_id":"s1","source":"startup"}' | GHOSTDEV_URL="http://127.0.0.1:9" sh "$ici/demarrage.sh" >/dev/null
verifie "serveur sans socle : la session reste comme avant" vide "" "$( [ -f "$sess/v2" ] && echo marquee )"
kill "$serveur" 2>/dev/null; rm -rf "$srv"

echo "=== Dossier de démo : muet ==="
mkdir -p "$proj/.demo"; touch "$proj/.demo/scenario"; printf 0 > "$sess/consulter"
verifie "démo : rien ne bloque" vide "" "$(outil Bash '{"command":"ls"}')"
rm -rf "$proj/.demo"

echo; echo "$ok ok, $ko échec(s)"
rm -rf "$proj" "$data"
[ "$ko" = 0 ]
