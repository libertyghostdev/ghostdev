#!/bin/sh
# Essais de la mise à jour du plugin (maj.sh), sans serveur GhostDev : une archive servie sur ce Mac.
#   sh produit/plugin/scripts/tests-maj.sh
# Ce qu'ils gardent (chez une acheteuse, du 2026-09-20 au 10-15 : une mise à jour coupée a laissé son dossier à moitié vide, sans
# demarrage.sh, donc sans plus aucune mise à jour possible) : une seule mise à jour à la fois, un verrou laissé par
# une mise à jour tuée qui ne bloque pas la suivante, le numéro de version écrit en dernier pour qu'une mise à jour
# coupée soit reprise à la session suivante, et le verrou rendu après un échec.
ici=$(cd "$(dirname "$0")" && pwd)
plugin=$(dirname "$ici")
ok=0; ko=0
verifie() { if [ "$1" = 0 ]; then ok=$((ok+1)); echo "  ok      $2"; else ko=$((ko+1)); echo "  ECHEC   $2"; fi; }
contient() { printf '%s' "$1" | grep -q -- "$2"; }
version_de() { sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$1/.claude-plugin/plugin.json" 2>/dev/null | head -1; }
fichiers() { (cd "$1" && find . -type f -print | sort); }

racine=$(mktemp -d)
# L'archive servie : le plugin d'ici, tel quel.
mkdir -p "$racine/www/plugin" && (cd "$plugin" && tar -czf "$racine/www/plugin/archive.tgz" .)
mkdir -p "$racine/attendu" && tar -xzf "$racine/www/plugin/archive.tgz" -C "$racine/attendu"
neuve=$(version_de "$racine/attendu")
port=$((20000 + $$ % 20000))
(cd "$racine/www" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) &
serveur=$!
trap 'kill $serveur 2>/dev/null; rm -rf "$racine"' EXIT
url="http://127.0.0.1:$port"
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fsS -o /dev/null "$url/plugin/archive.tgz" 2>/dev/null && break; sleep 0.3; done

# Un dossier en version 0.0.1, avec un fichier que la nouvelle version n'a plus.
ancien() {
  rm -rf "$racine/skills"; mkdir -p "$racine/skills"
  cp -R "$racine/attendu" "$racine/skills/machine-a-app"
  sed -i.bak 's/"version": *"[^"]*"/"version": "0.0.1"/' "$racine/skills/machine-a-app/.claude-plugin/plugin.json"
  rm -f "$racine/skills/machine-a-app/.claude-plugin/plugin.json.bak"
  echo "ancien" > "$racine/skills/machine-a-app/scripts/ancien.sh"
}
# Comme demarrage.sh : maj.sh lancé depuis une copie temporaire.
lancer() {
  t=$(mktemp -d); cp "$plugin/scripts/maj.sh" "$t/maj.sh"
  sh "$t/maj.sh" "$racine/skills/machine-a-app" "$t" "0.0.1" "$neuve" "${1:-$url}" 2>&1
}
d="$racine/skills/machine-a-app"

echo "=== Une mise à jour normale ==="
ancien; s=$(lancer)
contient "$s" "mis à jour"; verifie $? "elle se dit faite"
[ "$(version_de "$d")" = "$neuve" ]; verifie $? "la nouvelle version est en place ($neuve)"
[ "$(fichiers "$d")" = "$(fichiers "$racine/attendu")" ]; verifie $? "les fichiers sont exactement ceux de l'archive, l'ancien retiré"
[ ! -e "$d.verrou" ] && [ ! -e "$d.incoming" ]; verifie $? "ni verrou ni dossier d'arrivée laissés"

echo "=== Une autre mise à jour est en cours ==="
ancien; mkdir "$d.verrou"; sleep 300 & vivant=$!; echo "$vivant" > "$d.verrou/pid"
s=$(lancer)
contient "$s" "déjà en cours"; verifie $? "elle le dit"
[ "$(version_de "$d")" = "0.0.1" ] && [ -f "$d/scripts/ancien.sh" ]; verifie $? "elle ne touche à rien"
[ -d "$d.verrou" ]; verifie $? "le verrou de l'autre reste"
kill $vivant 2>/dev/null; rm -rf "$d.verrou"

echo "=== Deux sessions démarrent en même temps ==="
ancien; lancer > "$racine/a.txt" & a=$!; lancer > "$racine/b.txt" & b=$!; wait $a; wait $b
[ "$(version_de "$d")" = "$neuve" ]; verifie $? "la nouvelle version est en place"
[ "$(fichiers "$d")" = "$(fichiers "$racine/attendu")" ]; verifie $? "le dossier est complet, rien de perdu ni de mélangé"
[ ! -e "$d.verrou" ]; verifie $? "aucun verrou laissé"

echo "=== Une mise à jour tuée en plein remplacement est reprise ==="
ancien
mkdir -p "$racine/faux"; echo 0 > "$racine/faux/n"
# Un « mv » qui tue la mise à jour au cinquième fichier, comme la limite de 40 secondes du démarrage.
cat > "$racine/faux/mv" <<FIN
#!/bin/sh
n=\$((\$(cat "$racine/faux/n") + 1)); echo \$n > "$racine/faux/n"
[ \$n -ge 5 ] && kill -9 \$PPID
exec /bin/mv "\$@"
FIN
chmod +x "$racine/faux/mv"
# Dans un sous-shell : en sh, un PATH posé devant une fonction reste posé après elle.
( PATH="$racine/faux:$PATH"; lancer >/dev/null )
[ "$(version_de "$d")" = "0.0.1" ]; verifie $? "coupée : le numéro de version n'a pas encore bougé"
[ -d "$d.verrou" ]; verifie $? "coupée : son verrou est resté"
s=$(lancer)
contient "$s" "mis à jour"; verifie $? "la session suivante reprend, malgré le verrou laissé par un mort"
[ "$(fichiers "$d")" = "$(fichiers "$racine/attendu")" ] && [ "$(version_de "$d")" = "$neuve" ]
verifie $? "le dossier finit complet, en version $neuve"

echo "=== Le verrou est rendu après un échec ==="
ancien; s=$(lancer "http://127.0.0.1:1")
contient "$s" "non appliquée"; verifie $? "le téléchargement raté est dit"
[ ! -e "$d.verrou" ] && [ "$(version_de "$d")" = "0.0.1" ]; verifie $? "aucun verrou laissé, l'ancienne version gardée"

echo
echo "$ok ok, $ko en échec."
[ "$ko" = 0 ]
