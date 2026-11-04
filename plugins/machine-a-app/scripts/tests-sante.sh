#!/bin/sh
# Essais de la réparation silencieuse du plugin (sante.sh), sans serveur GhostDev : une archive servie sur ce Mac,
# construite comme le serveur la construit (avec sa liste .claude-plugin/fichiers).
#   sh produit/plugin/scripts/tests-sante.sh
# Ce qu'ils gardent : un dossier abîmé se répare tout seul, en fond, sans une ligne à la personne (le 2026-10-18,
# GhostDev a fait coller une ligne d'installation à une cliente) ; un dossier entier ne coûte rien ; une mise à jour en
# cours n'est pas doublée ; sans réseau, une seule tentative par heure ; la copie d'Anas (sans liste) et une
# installation par le marketplace ne sont jamais touchées à tort.
ici=$(cd "$(dirname "$0")" && pwd)
plugin=$(dirname "$ici")
ok=0; ko=0
verifie() { if [ "$1" = 0 ]; then ok=$((ok+1)); echo "  ok      $2"; else ko=$((ko+1)); echo "  ECHEC   $2"; fi; }
version_de() { sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$1/.claude-plugin/plugin.json" 2>/dev/null | head -1; }
fichiers() { (cd "$1" && find . -type f -print | sort); }
maintenant() { python3 -c 'import time; print(time.time())'; }

racine=$(mktemp -d)
# L'archive servie : le plugin d'ici, avec la liste de ses fichiers, comme _construire_archive du serveur.
mkdir -p "$racine/attendu" && cp -R "$plugin"/. "$racine/attendu"/
(cd "$racine/attendu" && find . -type f ! -path ./.claude-plugin/fichiers -print | sed 's|^\./||' | sort) \
  > "$racine/liste" && mv "$racine/liste" "$racine/attendu/.claude-plugin/fichiers"
mkdir -p "$racine/www/plugin" && (cd "$racine/attendu" && tar -czf "$racine/www/plugin/archive.tgz" .)
neuve=$(version_de "$racine/attendu")
# Un petit serveur qui note chaque téléchargement et la raison de la réparation (l'en-tête X-GhostDev-Reparation).
cat > "$racine/serveur.py" <<'FIN'
import http.server, os, sys
os.chdir(sys.argv[2])
class H(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        with open(sys.argv[3], "a") as f:
            f.write(f"{self.path} {self.headers.get('X-GhostDev-Reparation', '-')}\n")
        return super().do_GET()
    def log_message(self, *a):
        pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
FIN
port=$((20000 + $$ % 20000))
journal="$racine/journal.txt"; : > "$journal"
python3 "$racine/serveur.py" "$port" "$racine/www" "$journal" >/dev/null 2>&1 &
serveur=$!
trap '{ kill $serveur; wait $serveur; } 2>/dev/null; rm -rf "$racine"' EXIT
export GHOSTDEV_URL="http://127.0.0.1:$port"
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fsS -o /dev/null "$GHOSTDEV_URL/plugin/archive.tgz" 2>/dev/null && break; sleep 0.3; done
# Jamais la vraie clé d'Anas ni ses dossiers : un HOME et des données à part.
export HOME="$racine/home"; export CLAUDE_PLUGIN_DATA="$racine/home/data"; mkdir -p "$CLAUDE_PLUGIN_DATA"

d="$racine/skills/machine-a-app"
n=0
# Un dossier installé par l'archive, et une marque de tentative neuve (TMPDIR) : chaque essai part de zéro.
installe() {
  rm -rf "$racine/skills" "$d.verrou"; mkdir -p "$racine/skills"; cp -R "$racine/attendu" "$d"
  n=$((n+1)); export TMPDIR="$racine/tmp$n"; mkdir -p "$TMPDIR"; : > "$journal"
}
telecharge() { grep -c "^/plugin/archive.tgz" "$journal"; }
attend_entier() {
  for _ in $(seq 1 50); do [ "$(fichiers "$d")" = "$(fichiers "$racine/attendu")" ] && return 0; sleep 0.3; done
  return 1
}

echo "=== Un dossier entier ==="
installe
t0=$(maintenant); s=$(sh "$d/scripts/sante.sh"); t1=$(maintenant)
[ -z "$s" ]; verifie $? "rien n'est écrit"
python3 -c "import sys; sys.exit(0 if $t1 - $t0 < 0.5 else 1)"; verifie $? "il rend la main tout de suite"
sleep 1; [ "$(telecharge)" = 0 ]; verifie $? "rien n'est téléchargé"

echo "=== Un fichier manque, au milieu d'une mise à jour coupée ==="
installe; rm -f "$d/scripts/phase.sh"
sed -i.bak 's/"version": *"[^"]*"/"version": "0.0.1"/' "$d/.claude-plugin/plugin.json"; rm -f "$d/.claude-plugin/plugin.json.bak"
t0=$(maintenant); s=$(sh "$d/scripts/sante.sh"); t1=$(maintenant)
[ -z "$s" ]; verifie $? "rien n'est écrit pour la personne"
python3 -c "import sys; sys.exit(0 if $t1 - $t0 < 0.5 else 1)"; verifie $? "il rend la main tout de suite, la réparation part en fond"
attend_entier; verifie $? "le dossier revient entier, tout seul"
[ "$(version_de "$d")" = "$neuve" ]; verifie $? "en version $neuve : la mise à jour coupée est finie"
grep -q "manque scripts/phase.sh" "$journal"; verifie $? "le serveur apprend ce qui manquait (journal d'Anas)"
[ ! -e "$d.verrou" ] && [ ! -e "$d.incoming" ]; verifie $? "ni verrou ni dossier d'arrivée laissés"

echo "=== entetes.sh répare, et sa sortie reste les seuls en-têtes ==="
installe; rm -f "$d/hooks/hooks.json"
s=$(sh "$d/scripts/entetes.sh")
[ "$s" = "{\"X-GhostDev-Plugin\":\"$neuve\"}" ]; verifie $? "la sortie : les en-têtes, rien d'autre"
attend_entier; verifie $? "hooks.json revient"

echo "=== sante.sh manque lui-même ==="
installe; rm -f "$d/scripts/sante.sh" "$d/skills/ghostdev/SKILL.md"
sh "$d/scripts/entetes.sh" >/dev/null
for _ in $(seq 1 50); do [ -f "$d/scripts/sante.sh" ] && break; sleep 0.3; done
[ -f "$d/scripts/sante.sh" ]; verifie $? "il revient de l'archive du serveur"
sh "$d/scripts/entetes.sh" >/dev/null
attend_entier; verifie $? "la connexion suivante répare le reste"

echo "=== phase.sh répare, à chaque message ==="
installe; rm -f "$d/scripts/blocage.sh"; mkdir -p "$racine/projet/.machine-a-app"
printf '{"prompt":"bonjour"}' | CLAUDE_PROJECT_DIR="$racine/projet" sh "$d/scripts/phase.sh" >/dev/null
attend_entier; verifie $? "blocage.sh revient"

echo "=== La copie d'Anas, sans liste ==="
installe; rm -f "$d/.claude-plugin/fichiers" "$d/scripts/arrets.sh"
sh "$d/scripts/sante.sh"; sleep 1
[ "$(telecharge)" = 0 ] && [ ! -f "$d/scripts/arrets.sh" ]; verifie $? "un fichier secondaire manque : rien n'est touché"
rm -f "$d/scripts/phase.sh"; sh "$d/scripts/sante.sh"
attend_entier; verifie $? "un fichier sans lequel rien ne démarre manque : le dossier est réparé"

echo "=== Une mise à jour est en cours ==="
installe; rm -f "$d/scripts/phase.sh"; mkdir "$d.verrou"; sleep 300 & vivant=$!; echo "$vivant" > "$d.verrou/pid"
sh "$d/scripts/sante.sh"; sleep 1
[ "$(telecharge)" = 0 ]; verifie $? "il la laisse finir, rien n'est doublé"
{ kill $vivant; wait $vivant; } 2>/dev/null; rm -rf "$d.verrou"

echo "=== Sans réseau, une seule tentative par heure ==="
installe; rm -f "$d/scripts/phase.sh"
GHOSTDEV_URL="http://127.0.0.1:1" sh "$d/scripts/sante.sh"; sleep 1
[ ! -f "$d/scripts/phase.sh" ]; verifie $? "le serveur injoignable : rien ne change, rien n'est dit"
sh "$d/scripts/sante.sh"; sleep 1
[ "$(telecharge)" = 0 ]; verifie $? "une seconde tentative dans l'heure ne part pas"
export TMPDIR="$racine/tmp-plus-tard"; mkdir -p "$TMPDIR"; sh "$d/scripts/sante.sh"
attend_entier; verifie $? "une heure plus tard, la réparation passe"

echo "=== Une installation par le marketplace ==="
installe; m="$racine/plugins/cache/ghostdev/machine-a-app/$neuve"; mkdir -p "$(dirname "$m")"; cp -R "$d" "$m"
rm -f "$m/scripts/phase.sh"; sh "$m/scripts/sante.sh"; sleep 1
[ "$(telecharge)" = 0 ] && [ ! -f "$m/scripts/phase.sh" ]; verifie $? "jamais touchée : Claude Code s'en occupe"

echo "=== Une installation ajoutée depuis claude.ai (Personnaliser > Plugins) ==="
installe; c="$racine/plugins/synced/org_compte/machine-a-app"; mkdir -p "$(dirname "$c")"; cp -R "$d" "$c"
rm -f "$c/scripts/phase.sh"; sh "$c/scripts/sante.sh"; sleep 1
[ "$(telecharge)" = 0 ] && [ ! -f "$c/scripts/phase.sh" ]; verifie $? "jamais réparée : Claude la tient"
cp "$d/scripts/phase.sh" "$c/scripts/phase.sh"
# Le serveur annonce une version plus récente : demarrage.sh ne fait taper aucune commande et ne remplace rien.
printf '{"version":"99.0.0"}' > "$racine/www/plugin/version"
p="$racine/projet"; mkdir -p "$p/.machine-a-app"
s=$(CLAUDE_PROJECT_DIR="$p" CLAUDE_PLUGIN_DATA= sh "$c/scripts/demarrage.sh" </dev/null 2>&1); sleep 1
printf '%s' "$s" | grep -q "arrive toute seule" && ! printf '%s' "$s" | grep -q "/plugin update"; verifie $? "la nouvelle version arrive seule, aucune commande à taper"
[ "$(telecharge)" = 0 ] && [ "$(version_de "$c")" = "$neuve" ] && [ "$(ls -A "$(dirname "$c")")" = machine-a-app ]; verifie $? "rien n'est téléchargé ni posé à côté du dossier de Claude"
printf '%s' "$s" | grep -q "plugins/data/machine-a-app-synced"; verifie $? "ses données : plugins/data/machine-a-app-synced"
rm -f "$racine/www/plugin/version"

echo
echo "$ok ok, $ko en échec."
[ "$ko" = 0 ]
