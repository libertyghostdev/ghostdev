#!/bin/sh
# Mise à jour du plugin GhostDev. Appelé par demarrage.sh depuis une copie temporaire.
# Arguments : dossier du plugin, dossier temporaire, version locale, version distante, url du serveur.
#
# La session en cours parle au serveur par .mcp.json et scripts/entetes.sh, lus à chaque appel.
# L'ancienne version vidait le dossier avant de recopier : pendant ce trou, un appel tombait sur un
# fichier absent ou à moitié écrit, le lien se coupait, et Claude ne le rétablit pas dans une
# conversation ouverte (vu chez une acheteuse le 2026-09-24). Donc : aucun trou. Chaque fichier
# arrive entier, par un déplacement dans le même dossier, et ce qui a disparu de la nouvelle version
# n'est retiré qu'à la fin.
#
# Une seule mise à jour à la fois. Deux sessions qui démarrent ensemble lançaient deux mises à jour sur le même
# dossier, et il finissait incomplet (reproduit par tests-maj.sh). Chez une acheteuse, le 2026-09-20, une mise à jour coupée
# a laissé un dossier à moitié vide, sans demarrage.sh, donc sans plus aucune mise à jour possible pendant 25 jours.
# Le verrou garde le numéro de la mise à jour qui le tient : s'il est mort (la limite de temps du démarrage l'a
# tué), ou si le verrou a plus de dix minutes, la mise à jour suivante le reprend.
root="$1"; tmp="$2"; locale="$3"; distante="$4"; url="$5"
inc="$root.incoming"
verrou="$root.verrou"

prendre_verrou() {
  mkdir "$verrou" 2>/dev/null && { echo $$ > "$verrou/pid"; return 0; }
  pid=$(cat "$verrou/pid" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ -z "$(find "$verrou" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    return 1
  fi
  rm -rf "$verrou"
  mkdir "$verrou" 2>/dev/null && { echo $$ > "$verrou/pid"; return 0; }
  return 1
}
if ! prendre_verrou; then
  echo "Une mise à jour de GhostDev est déjà en cours dans une autre session : version $locale gardée ici."
  echo "</ghostdev-demarrage>"; rm -rf "$tmp"; exit 0
fi
trap 'rm -rf "$verrou"' EXIT

rate() { echo "Mise à jour non appliquée, version $locale conservée ($1)."; echo "</ghostdev-demarrage>"; rm -rf "$tmp" "$inc"; exit 0; }

# sante.sh, qui répare un dossier abîmé, a déjà téléchargé l'archive : elle est reprise telle quelle.
[ -s "$tmp/p.tgz" ] || curl -fsS -m 30 "$url/plugin/archive.tgz" -o "$tmp/p.tgz" 2>/dev/null || rate "téléchargement"
mkdir -p "$tmp/new" && tar -xzf "$tmp/p.tgz" -C "$tmp/new" || rate "archive abîmée"
[ -f "$tmp/new/.claude-plugin/plugin.json" ] || rate "archive incomplète"

# Le filet, à côté du dossier : on peut revenir en arrière.
rm -rf "$root.previous" "$inc"
cp -R "$root" "$root.previous" || rate "copie de secours"
# La nouvelle version arrive d'abord à côté du dossier, donc sur le même disque : le déplacement
# fichier par fichier est alors instantané et entier, jamais un fichier à moitié écrit.
mkdir -p "$inc" && cp -R "$tmp/new"/. "$inc"/ || rate "préparation"

# La liste de la nouvelle version, figée AVANT de déplacer : les fichiers sortent de "$inc" en
# chemin, donc comparer avec "$inc" à la fin verrait le dossier vide et effacerait tout (vu au
# deuxième essai, le 2026-09-24).
liste="$tmp/liste"
# Le numéro de version en dernier : une mise à jour coupée en chemin garde l'ancien numéro, et la session suivante
# voit encore une version à prendre, donc elle la reprend au lieu de croire le dossier à jour. La liste des fichiers en
# premier : coupée en chemin, la mise à jour laisse un dossier qui annonce des fichiers absents, et sante.sh la finit
# au message suivant, sans attendre une nouvelle session.
v=".claude-plugin/plugin.json"; m=".claude-plugin/fichiers"
(cd "$inc" && { [ -f "$m" ] && echo "$m"; find . -type f -print | sed 's|^\./||' | grep -vxF -e "$v" -e "$m"; echo "$v"; }) > "$liste" || rate "liste"
# Une boucle, pas find -exec : sur macOS, {} au milieu d'un chemin n'est pas remplacé, et tout
# atterrissait dans un fichier nommé « {} » (vu au premier essai, le même jour).
(cd "$inc" && find . -type d ! -name . -print) | while IFS= read -r d; do mkdir -p "$root/${d#./}"; done
if ! while IFS= read -r f; do mv -f "$inc/$f" "$root/$f" || exit 1; done < "$liste"; then
  rm -rf "$root"; cp -R "$root.previous" "$root"; rate "remplacement"
fi

# Ce que la nouvelle version n'a plus : retiré seulement maintenant, quand tout le reste est en place.
(cd "$root" && find . -type f -print | sed 's|^\./||') 2>/dev/null | while IFS= read -r f; do
  grep -qxF "$f" "$liste" || rm -f "$root/$f"
done
rm -rf "$inc" "$tmp"
echo "GhostDev mis à jour : version $locale remplacée par $distante."
echo "Si un de mes outils répond « le serveur ne répond pas » dans cette conversation, dis-lui de cliquer sur Nouveau, même dossier, et d'écrire « on continue » : rien n'est perdu."
echo "</ghostdev-demarrage>"
