#!/bin/sh
# Le dossier du plugin est-il entier ? Sinon, il se répare tout seul, en fond, sans un mot à la personne.
# Chez une acheteuse (du 2026-09-20 au 10-15), une mise à jour coupée avait laissé hooks/ et skills/ vides, et scripts/ sans
# demarrage.sh : plus de démarrage, plus de SOS, plus de mise à jour. Le 2026-10-18, GhostDev a fait coller à une
# cliente une ligne d'installation dans Terminal. Plus jamais : le plugin se remet d'aplomb lui-même, et la personne
# n'en sait rien. Anas le voit au journal du serveur (« reparation », avec le premier fichier qui manquait).
#
# Appelé par entetes.sh (chaque connexion au serveur), phase.sh (chaque message) et demarrage.sh (chaque session) :
# il suffit qu'un seul d'entre eux reste pour que tout revienne. Sain, il rend la main en quelques millisecondes.
#   sh sante.sh           le contrôle ; s'il manque un fichier, la réparation part en fond et le script rend la main
#   sh sante.sh reparer   la réparation au premier plan, même sans manque (les essais)
# La liste des fichiers (.claude-plugin/fichiers) est écrite par le serveur dans chaque archive. Sans elle (la copie
# d'Anas, posée par rsync), seuls les fichiers sans lesquels rien ne démarre sont contrôlés.
# La réparation prend l'archive du serveur et lance SON maj.sh, jamais celui du dossier abîmé : il peut manquer, ou
# dater. maj.sh garde le verrou, la copie de secours et le remplacement sans trou.
[ -n "$GHOSTDEV_EN_REPARATION" ] && exit 0   # entetes.sh, lancé par la réparation elle-même
root=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 0
case "$root" in *"/plugins/cache/"*|*"/plugins/marketplaces/"*|*"/plugins/synced/"*) exit 0;; esac   # Claude s'en occupe
url="${GHOSTDEV_URL:-https://ghostdev.libertytechlab.com}"
manque=""
if [ -s "$root/.claude-plugin/fichiers" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && [ ! -f "$root/$f" ] && { manque="$f"; break; }
  done < "$root/.claude-plugin/fichiers"
else
  for f in .claude-plugin/plugin.json .mcp.json hooks/hooks.json skills/ghostdev/SKILL.md scripts/actif.sh \
           scripts/chemins.sh scripts/demarrage.sh scripts/donnees.sh scripts/entetes.sh scripts/maj.sh scripts/phase.sh; do
    [ -f "$root/$f" ] || { manque="$f"; break; }
  done
fi
[ -z "$manque" ] && [ "$1" != "reparer" ] && exit 0

if [ "$1" != "reparer" ]; then
  # Une mise à jour tient le verrou : elle finira le travail (ses fichiers arrivent un par un, la liste en premier).
  [ -d "$root.verrou" ] && [ -z "$(find "$root.verrou" -maxdepth 0 -mmin +10 2>/dev/null)" ] && exit 0
  # Une tentative par heure au plus : sans réseau, elle ne coûte qu'un essai par heure, et jamais rien à la personne.
  marque="${TMPDIR:-/tmp}/ghostdev-reparation-$(id -u 2>/dev/null)"
  [ -n "$(find "$marque" -mmin -60 2>/dev/null)" ] && exit 0
  touch "$marque" 2>/dev/null
fi

version_de() { sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$1/.claude-plugin/plugin.json" 2>/dev/null | head -1; }
reparer() {
  export GHOSTDEV_EN_REPARATION=1
  tmp=$(mktemp -d 2>/dev/null) || return 0
  ck=""
  [ -f "$root/scripts/entetes.sh" ] && ck=$(sh "$root/scripts/entetes.sh" 2>/dev/null | sed -n 's/.*"Bearer \([^"]*\)".*/\1/p')
  if curl -fsS -m 60 -H "Authorization: Bearer $ck" -H "X-GhostDev-Reparation: manque ${manque:-aucun (essai)}" \
       "$url/plugin/archive.tgz" -o "$tmp/p.tgz" 2>/dev/null \
     && mkdir -p "$tmp/new" && tar -xzf "$tmp/p.tgz" -C "$tmp/new" 2>/dev/null && [ -f "$tmp/new/scripts/maj.sh" ]; then
    locale=$(version_de "$root"); distante=$(version_de "$tmp/new")
    sh "$tmp/new/scripts/maj.sh" "$root" "$tmp" "${locale:-?}" "${distante:-?}" "$url"
  else
    rm -rf "$tmp"
  fi
}
if [ "$1" = "reparer" ]; then
  reparer
else
  (reparer) </dev/null >/dev/null 2>&1 &
fi
exit 0
