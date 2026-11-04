#!/bin/sh
# V2 : après guide, la mémoire du projet qui va avec la demande (spec 6.4). Hooks PostToolUse et PostToolUseFailure
# sur guide. Un itinéraire reçu (sa ligne <arrets>) lève le drapeau de consultation, note les fiches livrées et le
# sommaire (la liste « déjà lues »), range les arrêts (les fiches principales à lire avant le premier geste qui change
# quelque chose) et le type qui a des étapes d'après (navigation, 6.2) ; un refus de guide laisse le drapeau. Puis sort
# de .machine-a-app/memoire/ les lignes actives du domaine, de l'écran et de la phase, les notes « plus tard » dont le
# moment est arrivé, et le chantier en cours. Quinze lignes et 2 000 caractères au plus. Rien de la mémoire ne part
# au serveur. sh seulement.
sh "$(dirname "$0")/actif.sh" || exit 0
. "$(dirname "$0")/chemins.sh"; . "$(dirname "$0")/donnees.sh"
proj=$(ghostdev_chemin "${CLAUDE_PROJECT_DIR:-$PWD}")
[ -f "$proj/.demo/scenario" ] && exit 0
set -f   # les étiquettes [écran:…] ne sont jamais des motifs de fichiers
plat=$(cat 2>/dev/null | tr -d '\n\r')
sess=$(ghostdev_session "$(ghostdev_champ "$plat" session_id)")
# Le guide d'un sous-agent ne compte pas pour la conversation : ni drapeau levé, ni fiche notée comme lue.
sous_agent=""; case "$plat" in *'"agent_id"'*) sous_agent=1 ;; esac
dire() {
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$(ghostdev_champ "$plat" hook_event_name)" "$(ghostdev_json "$1")"
  exit 0
}
if [ "$(ghostdev_champ "$plat" hook_event_name)" = PostToolUseFailure ]; then
  [ -n "$sous_agent" ] || rm -f "$sess/consulter"
  dire "GhostDev est injoignable pour ce message. Continue prudemment avec ce que tu sais, sans affirmer ce que tu n'as pas vérifié, et reconsulte au message suivant."
fi
# Un refus de guide (sans demande ni besoins, un type inconnu) n'a pas de ligne <arrets> : le drapeau reste posé, et
# consultation.sh refuse encore les gestes jusqu'au bon appel, trois fois au plus.
case "$plat" in *"<arrets>"*) ;; *) exit 0 ;; esac
if [ -z "$sous_agent" ]; then
  rm -f "$sess/consulter"
  printf '%s' "$plat" | grep -o 'fiche id=[\\"]*[A-Z][A-Z]*-[0-9][0-9]*' | grep -o '[A-Z][A-Z]*-[0-9][0-9]*$' >> "$sess/lues"
  case "$plat" in *"<sommaire>"*) printf 'sommaire\n' >> "$sess/lues" ;; esac
  # Les arrêts, moins ce qui est déjà lu depuis le dernier compactage : consultation.sh les tient (navigation 6.2).
  : > "$sess/arrets.tmp"
  for id in $(printf '%s' "$plat" | sed -n 's/.*<arrets>\([^<]*\)<\/arrets>.*/\1/p'); do
    grep -q -x -- "$id" "$sess/lues" 2>/dev/null || printf '%s\n' "$id" >> "$sess/arrets.tmp"
  done
  if [ -s "$sess/arrets.tmp" ]; then mv "$sess/arrets.tmp" "$sess/arrets"; else rm -f "$sess/arrets.tmp" "$sess/arrets"; fi
  rm -f "$sess/arrets-refus"
  # Le type qui a des étapes d'après (fin-de-tour.sh les rappelle une fois). Une réponse courte n'a pas de ligne
  # <apres> : le chantier garde celles de sa demande.
  case "$plat" in
    *"<apres>"*)
      ap=$(printf '%s' "$plat" | sed -n 's/.*<apres>\([a-z_]*\)<\/apres>.*/\1/p')
      if [ -n "$ap" ]; then printf '%s' "$ap" > "$sess/apres"; else rm -f "$sess/apres"; fi ;;
  esac
fi
d=$(ghostdev_champ "$plat" domaine); p=$(ghostdev_nombre "$plat" phase)
ec=$(ghostdev_champ "$plat" ecran | tr 'A-Z' 'a-z')
[ "$d" = aucun ] && d=""; [ "$p" = "-1" ] && p=""
mem="$proj/.machine-a-app/memoire"
# Le plus précis d'abord (l'écran, puis le domaine, puis la phase), et dans chacun le plus récent d'abord : les
# fichiers ne font que grandir par la fin. Sans cet ordre, douze décisions de phase cachaient le goût de l'écran.
porteuses() {
  for t in decisions gouts sujets ecarts faits; do
    [ -s "$mem/$t.md" ] && grep -E '^- M-[0-9]+ ' "$mem/$t.md" | grep -i -F -- "$1"
  done | sed -n '1!G;h;$p'
}
lignes=""
if [ -d "$mem" ]; then
  lignes=$( { [ -n "$ec" ] && porteuses "[ecran:$ec]"; [ -n "$d" ] && porteuses "[domaine:$d]"; [ -n "$p" ] && porteuses "[phase:$p]"; } | awk '!vu[$2]++')
fi
# Une note « plus tard » ressort quand chaque condition de son « quand: » est vraie maintenant.
dues=""
if [ -s "$mem/plus-tard.md" ]; then
  while IFS= read -r ligne; do
    case "$ligne" in "- M-"*"état: en attente"*) ;; *) continue ;; esac
    q=$(printf '%s' "$ligne" | sed -n 's/.*quand: *\([^·]*\).*/\1/p')
    [ -n "$q" ] || continue
    ok=1
    for c in $q; do
      k=${c%%=*}; v=${c#*=}
      case "$k" in
        phase) [ "$v" = "$p" ] || ok="" ;;
        ecran) [ "$v" = "$ec" ] || ok="" ;;
        domaine) [ "$v" = "$d" ] || ok="" ;;
        *) ok="" ;;
      esac
    done
    [ -n "$ok" ] && dues="${dues}${dues:+
}$ligne"
  done < "$mem/plus-tard.md"
fi
e=$(tr -d '\n\r' 2>/dev/null < "$proj/.machine-a-app/etat.json")
ch=$(printf '%s' "$e" | grep -o '"chantier" *: *{[^}]*}' | head -1)
chantier=""
if [ -n "$ch" ]; then
  chantier="Chantier en cours : $(ghostdev_champ "$ch" sujet) · stratégie $(ghostdev_champ "$ch" strategie) · étape $(ghostdev_nombre "$ch" etape)"
  fc=$(printf '%s' "$ch" | grep -o '"fiches" *: *\[[^]]*\]' | grep -o '[A-Z][A-Z]*-[0-9][0-9]*' | tr '\n' ' ' | sed 's/ *$//')
  [ -n "$fc" ] && chantier="$chantier · fiches $fc"
fi
lues=$(sort -u "$sess/lues" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
# La mémoire : 15 lignes et 2 000 caractères au plus (cahier 4.7). Les notes « plus tard » arrivées passent d'abord :
# leur moment est venu, et ce sont elles que la coupe enlèverait sinon.
memoire=""
[ -n "$dues" ] && memoire="Notes « plus tard » dont le moment est arrivé :
$(printf '%s\n' "$dues" | head -n 5)"
[ -n "$lignes" ] && memoire="${memoire}${memoire:+
}Mémoire du projet pour ce moment :
$(printf '%s\n' "$lignes" | head -n 10)"
[ -n "$memoire" ] && memoire=$(printf '%s\n' "$memoire" | head -n 15 | head -c 2000)
sortie="$memoire"
[ -n "$chantier" ] && sortie="${sortie}${sortie:+
}$chantier"
[ -n "$lues" ] && sortie="${sortie}${sortie:+
}Fiches déjà lues depuis le dernier compactage (à passer dans deja_lues) : $lues"
# Le journal local des injections, pour le banc et le diagnostic : les numéros M-… vraiment dits à Claude à chaque
# consultation, jamais le texte, marqués « après compactage » quand il y en a eu un. Il ne quitte jamais la machine.
if [ -z "$sous_agent" ]; then
  apres=""; [ -f "$sess/compacte" ] && apres=" · après compactage"
  printf '%s%s · %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$apres" \
    "$(printf '%s\n' "$memoire" | grep -o 'M-[0-9][0-9]*' | sort -u | tr '\n' ' ' | sed 's/ *$//')" >> "$sess/injections.log"
fi
[ -n "$sortie" ] || exit 0
dire "$sortie"
