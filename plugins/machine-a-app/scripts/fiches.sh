#!/bin/sh
# V2, le deuxième chemin (produit/docs/v2-arbre/cahier-des-charges.md, 9.6) : avant un geste connu (une commande qui
# envoie à un store, par exemple), la fiche de ce geste arrive toute seule, sans passer par la recherche. Repris du
# prototype du banc (version C), sans aucun blocage : la V2 ne bloque jamais une étape (décision V2-6). Les motifs
# viennent du serveur (/arbre/declencheurs.json), la correspondance se fait ici. Une fiche par session, de nouveau
# après 30 minutes. Deux fiches pour le même geste ne tiennent pas toujours dans un hook (10 000 caractères) : celle
# qui ne tient pas est nommée, à lire par lire_fiche. Muet à la moindre erreur. sh seulement.
sh "$(dirname "$0")/actif.sh" || exit 0
. "$(dirname "$0")/chemins.sh"; . "$(dirname "$0")/donnees.sh"
proj=$(ghostdev_chemin "${CLAUDE_PROJECT_DIR:-$PWD}")
[ -f "$proj/.demo/scenario" ] && exit 0
plat=$(cat 2>/dev/null | tr -d '\n\r')
session=$(ghostdev_champ "$plat" session_id); [ -n "$session" ] || session=sans-session
[ -f "$(ghostdev_session "$session")/v2" ] || exit 0
[ "$(ghostdev_champ "$plat" hook_event_name)" = PreToolUse ] || exit 0
texte="$(ghostdev_champ "$plat" tool_name) $(printf '%s' "$plat" | sed -n 's/.*"tool_input" *: *//p')"
url="${GHOSTDEV_URL:-https://ghostdev.libertytechlab.com}"
cache="$proj/.machine-a-app/fiches"
mkdir -p "$cache" 2>/dev/null || exit 0
n=$(ghostdev_nombre "$(tr -d '\n\r' 2>/dev/null < "$proj/.machine-a-app/etat.json")" phase)
# Les motifs, relus quand le contenu du serveur a changé (phase.sh tient contenu.version à jour).
version=$(cat "$proj/.machine-a-app/contenu.version" 2>/dev/null)
if [ ! -s "$cache/declencheurs.json" ] || [ "$(cat "$cache/version" 2>/dev/null)" != "$version" ]; then
  if curl -fsS -m 2 "$url/arbre/declencheurs.json" -o "$cache/declencheurs.tmp" 2>/dev/null; then
    mv "$cache/declencheurs.tmp" "$cache/declencheurs.json"; rm -f "$cache"/*.txt; printf '%s' "$version" > "$cache/version"
  else
    rm -f "$cache/declencheurs.tmp"
  fi
fi
[ -s "$cache/declencheurs.json" ] || exit 0
maintenant=$(date +%s)
trouves=""
while IFS= read -r ligne; do
  case "$ligne" in *'"id":'*) ;; *) continue ;; esac
  id=$(printf '%s' "$ligne" | sed -n 's/.*"id": *"\([^"]*\)".*/\1/p')
  case " $trouves " in *" $id "*) continue ;; esac
  ph=$(printf '%s' "$ligne" | sed -n 's/.*"phases": *"\([^"]*\)".*/\1/p')
  if [ -n "$ph" ]; then
    [ -n "$n" ] || continue
    case " $ph " in *" $n "*) ;; *) continue ;; esac
  fi
  motif=$(printf '%s' "$ligne" | sed -n 's/.*"motif": *"\(.*\)"}.*/\1/p' | sed 's/\\\\/\\/g')
  [ -n "$motif" ] || continue
  printf '%s' "$texte" | grep -q -i -E -- "$motif" 2>/dev/null || continue
  vu=$(grep "^$session $id " "$cache/vues" 2>/dev/null | tail -1 | cut -d' ' -f3)
  [ -n "$vu" ] && [ $((maintenant - vu)) -lt 1800 ] && continue
  trouves="$trouves $id"
done < "$cache/declencheurs.json"
[ -n "$trouves" ] || exit 0
cle=$(sh "$(dirname "$0")/entetes.sh" 2>/dev/null | sed -n 's/.*"Bearer \([^"]*\)".*/\1/p')
corps=""; aussi=""
for id in $trouves; do
  f="$cache/$id.txt"
  if [ ! -s "$f" ]; then
    curl -fsS -m 2 -H "Authorization: Bearer $cle" "$url/arbre/fiche/$id" -o "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" || { rm -f "$f.tmp"; continue; }
  fi
  total=$(printf '%s\n\n%s' "$corps" "$(cat "$f")" | wc -c | tr -d ' ')
  if [ "$total" -le 9500 ]; then corps=$(printf '%s\n\n%s' "$corps" "$(cat "$f")"); else aussi="$aussi $id"; fi
  printf '%s %s %s\n' "$session" "$id" "$maintenant" >> "$cache/vues"
done
[ -n "$aussi" ] && corps=$(printf '%s\n\nAussi pour ce geste, à lire par lire_fiche :%s.' "$corps" "$aussi")
[ -n "$corps" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' \
  "$(ghostdev_json "GhostDev, fiche de ce geste, à appliquer avec ses preuves :$corps")"
