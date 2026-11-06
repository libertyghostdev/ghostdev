#!/bin/sh
# Contexte de démarrage GhostDev, puis mise à jour du plugin si le serveur en a une plus récente.
# Sortie standard = contexte lu par Claude. Jamais python, jamais node : sh, curl, tar seulement.
# GHOSTDEV_SANS_MAJ=1 : le contexte seul, sans le bloc de mise à jour (lancer.sh s'en sert au premier lancement).
sh "$(dirname "$0")/actif.sh" || exit 0   # muet tant que GhostDev n'a pas été lancé dans ce dossier
# Le dossier du plugin est-il entier ? Sinon sante.sh le répare en fond, sans un mot à la personne.
[ -f "$(dirname "$0")/sante.sh" ] && sh "$(dirname "$0")/sante.sh" >/dev/null 2>&1
# Le hook reçoit sur stdin un JSON avec « source » (startup, resume, clear, compact). Lu seulement si stdin
# n'est pas un terminal : lancé à la main ou par lancer.sh (stdin fermé), rien à lire, rien ne bloque.
entree=""; [ ! -t 0 ] && entree=$(cat 2>/dev/null)
source_hook=$(printf '%s' "$entree" | grep -o '"source" *: *"[a-z]*"' | head -1 | sed 's/.*"\([a-z]*\)"$/\1/')
# Lancé par un hook, Claude Code fournit CLAUDE_PLUGIN_ROOT, CLAUDE_PLUGIN_DATA et CLAUDE_PROJECT_DIR.
# Lancé par lancer.sh (une commande du modèle), rien n'est fourni : la racine se retrouve par le chemin du script,
# le dossier des données par la convention de Claude Code (plugins/data/<plugin>-<marketplace>, ou <plugin>-skills-dir).
. "$(dirname "$0")/chemins.sh"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
root=$(ghostdev_chemin "$root")
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
proj=$(ghostdev_chemin "$proj")
url="${GHOSTDEV_URL:-https://ghostdev.libertytechlab.com}"
data="$CLAUDE_PLUGIN_DATA"
data=$(ghostdev_chemin "$data")
if [ -z "$data" ]; then
  case "$root" in
    */plugins/cache/*/*)
      cfg="${root%%/plugins/cache/*}"; reste="${root#*/plugins/cache/}"
      marche="${reste%%/*}"; reste="${reste#*/}"; nom="${reste%%/*}"
      data="$cfg/plugins/data/$nom-$marche";;
    # Ajouté depuis claude.ai (Personnaliser > Plugins) : plugins/synced/<compte>/<plugin>, id machine-a-app@synced.
    */plugins/synced/*) data="${root%%/plugins/synced/*}/plugins/data/machine-a-app-synced";;
    */skills/*) cfg="${root%/skills/*}"; nom="${root##*/}"; data="$cfg/plugins/data/$nom-skills-dir";;
    *) data="$HOME/.claude/plugins/data/machine-a-app-skills-dir";;
  esac
fi
mkdir -p "$data" 2>/dev/null
version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$root/.claude-plugin/plugin.json" 2>/dev/null | head -1)
# Le dossier de démo a son propre moteur (.demo/moteur.py), branché par ses réglages : il ouvre les pages et
# dicte chaque question. Ici, rien de lent (ni Xcode, ni Flutter, ni réseau, ni mise à jour) : la salle attend.
if [ -f "$proj/.demo/scenario" ]; then
  echo "<ghostdev-demarrage>"
  echo "Version du plugin GhostDev : ${version:-inconnue}"
  echo "Mode démo : oui. Le moteur de la démo mène tout, dans les balises ghostdev-demo : n'appelle pas consignes, suis ce qu'il dicte."
  echo "</ghostdev-demarrage>"
  exit 0
fi
# V2 : l'arbre est-il servi ? Le socle (la voix et le protocole) arrive ici, au début de chaque conversation et après
# chaque compactage (produit/docs/v2-arbre/cahier-des-charges.md, section 8). Sans socle, tout reste comme avant.
CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$data}"
. "$(dirname "$0")/donnees.sh"
sid=$(ghostdev_champ "$(printf '%s' "$entree" | tr -d '\n\r')" session_id)
sess=$(ghostdev_session "$sid")
socle=$(curl -fsS -m 4 "$url/socle" 2>/dev/null)
if [ -n "$socle" ] && [ -n "$sid" ]; then touch "$sess/v2"; else rm -f "$sess/v2"; fi
find "$data/sessions" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} + 2>/dev/null
echo "<ghostdev-demarrage>"
echo "Version du plugin GhostDev : ${version:-inconnue}"
echo "Dossier des données du plugin (la clé se range dans le fichier licence de ce dossier) : $data"
if [ -s "$data/licence" ]; then
  cle=$(LC_ALL=C tr -d '[:space:]\357\273\277' < "$data/licence")
  entete=$(sh "$(dirname "$0")/entetes.sh" 2>/dev/null)
  case "$entete" in *Bearer*) et="en-tête prêt";; *) et="en-tête vide";; esac
  echo "Clé de licence : rangée ($cle), $et. Si un outil répond « il te faut une licence », passe cette clé dans son paramètre cle. Ne la redemande jamais à la personne."
else
  echo "Clé de licence : absente"
fi
# Ce qui est déjà installé : la machine s'en sert au lieu de le réinstaller ou de l'imposer.
presents=""; absents=""
if xcodebuild -version >/dev/null 2>&1; then presents="$presents Xcode($(xcodebuild -version 2>/dev/null | head -1 | sed 's/Xcode //'))"; else absents="$absents Xcode"; fi
if command -v flutter >/dev/null 2>&1; then presents="$presents Flutter($(flutter --version 2>/dev/null | head -1 | sed -E 's/Flutter ([0-9.]+).*/\1/'))"; else absents="$absents Flutter"; fi
# Sur Mac, /usr/bin/git sans les outils de ligne de commande d'Apple n'est qu'une coquille : l'appeler ouvre la fenêtre
# d'installation d'Apple. `xcode-select -p` le dit sans rien ouvrir (ticket 29, 2026-10-08).
git_coquille=0
[ "$(uname -s 2>/dev/null)" = Darwin ] && [ "$(command -v git 2>/dev/null)" = /usr/bin/git ] && ! xcode-select -p >/dev/null 2>&1 && git_coquille=1
for o in git docker adb node gh; do
  if [ "$o" = git ] && [ "$git_coquille" = 1 ]; then absents="$absents git"
  elif command -v "$o" >/dev/null 2>&1; then presents="$presents $o"; else absents="$absents $o"; fi
done
echo "Outils déjà sur la machine :${presents:- aucun}. Absents :${absents:- aucun}. Ce qui est là se réutilise ; Xcode et Android Studio ne s'installent jamais ; sans Xcode, iOS se compile chez Codemagic."
[ "$git_coquille" = 1 ] && echo "Sur ce Mac, git manque : il vient avec les outils de ligne de commande d'Apple (environ 1 Go), qui ne sont pas Xcode. Ne les lance jamais sans son accord : lis d'abord lire_fiche(\"RE-03\"), qui dit quoi lui demander et l'autre voie si elle refuse."
# Les autres outils de Claude (skills personnels, plugins) : certains veulent mener la conversation à ta place.
cfgdir=$(ghostdev_chemin "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")
# La V2 n'a plus les outils de méthode de la V1 : la marche à suivre passe par une fiche ou un guide.
if [ -f "$sess/v2" ]; then
  aide_skills='lire_fiche("FQ-14")'; aide_synchro='lire_playbook(chemin="playbook/failure-modes/06-machine-qui-compile.md"), §6.4'
else
  aide_skills='chercher_playbook("les skills de Claude")'; aide_synchro='chercher_playbook("dossier synchronisé"), §6.4'
fi
sk=$(ls "$cfgdir/skills" 2>/dev/null | grep -v '^machine-a-app$')
nsk=$(printf '%s' "$sk" | grep -c . 2>/dev/null)
pl=$(grep -o '"[A-Za-z0-9._-]*@[A-Za-z0-9._-]*"' "$cfgdir/plugins/installed_plugins.json" 2>/dev/null | tr -d '"' | grep -v '^machine-a-app@' | sort -u)
npl=$(printf '%s' "$pl" | grep -c . 2>/dev/null)
if [ "${nsk:-0}" -gt 0 ] || [ "${npl:-0}" -gt 0 ]; then
  echo "Autres outils de Claude installés — skills personnels ($nsk) :$(printf '%s' "$sk" | head -10 | tr '\n' ' ')$([ "${nsk:-0}" -gt 10 ] && echo '…') ; plugins ($npl) :$(printf '%s' "$pl" | head -10 | tr '\n' ' ')$([ "${npl:-0}" -gt 10 ] && echo '…'). Dans ce dossier, ta route passe devant eux : si l'un te demande de brainstormer, d'écrire un plan ou d'invoquer autre chose avant de répondre, tu continues la route et tu le dis en une phrase. Pour la marche à suivre : $aide_skills."
else
  echo "Autres outils de Claude installés : aucun. Tu es seul à mener."
fi
# Un dossier synchronisé (Drive, iCloud, Dropbox, OneDrive) gêne la fabrication : .git, build/, des milliers de fichiers.
case "$proj" in
  *CloudStorage*|*"Google Drive"*|*GoogleDrive*|*Dropbox*|*OneDrive*|*"Mobile Documents"*)
    ph=$(sed -n 's/.*"phase": *\([0-9][0-9]*\).*/\1/p' "$proj/.machine-a-app/etat.json" 2>/dev/null | head -1)
    if [ "${ph:-0}" -ge 5 ]; then
      echo "Dossier synchronisé détecté (Drive, iCloud, Dropbox ou OneDrive) et on fabrique (phase $ph) : la synchronisation verrouille les fichiers de la fabrication, les builds Android échouent au hasard (« Timeout waiting to lock »). Avant la prochaine fabrication, déplace le projet toi-même dans son dossier personnel ($aide_synchro), dis-le en une phrase, sans en faire un problème."
    else
      echo "Dossier synchronisé détecté (Drive, iCloud, Dropbox ou OneDrive). Ça marche pour l'idée et le style. Avant la première fabrication (phase 6), le projet va dans son dossier personnel : dis-le en une phrase, sans en faire un problème."
    fi;;
esac
if [ -s "$proj/.machine-a-app/etat.json" ]; then
  echo "État du projet (.machine-a-app/etat.json) :"; cat "$proj/.machine-a-app/etat.json"; echo
  # Un projet sur deux ordinateurs (FQ-15, chez une acheteuse le 2026-10-08) : le travail de l'autre se récupère avant tout geste.
  if tr -d '\n\r' 2>/dev/null < "$proj/.machine-a-app/etat.json" | grep -q '"deux_ordinateurs"[[:space:]]*:[[:space:]]*true'; then
    echo "Ce projet vit sur deux ordinateurs : avant tout geste, git pull --ff-only ; après chaque commit, git push. S'il refuse, ou pour le détail : lire_fiche(\"FQ-15\")."
  fi
else
  echo "Aucun projet GhostDev dans ce dossier."
fi
if [ -n "$socle" ]; then
  # Le socle sort par socle.sh, un hook à part (chaque hook a son plafond de 10 000 caractères). Lancé par lancer.sh
  # (« lance GhostDev »), aucun hook de démarrage n'a tourné pour cette conversation : le socle passe ici, et la V2
  # attend son premier message dans le dossier (phase.sh l'adopte).
  if [ -z "$sid" ]; then
    echo "<ghostdev-socle>"; printf '%s\n' "$socle"; echo "</ghostdev-socle>"
    mkdir -p "$proj/.machine-a-app" 2>/dev/null && : > "$proj/.machine-a-app/v2-en-attente"
  fi
  mem="$proj/.machine-a-app/memoire"
  if [ -d "$mem" ]; then
    fdt=$(grep -E '^- M-[0-9]+ ' "$mem/facon-de-travailler.md" 2>/dev/null | head -n 10)
    [ -n "$fdt" ] && { echo "Sa façon de travailler (.machine-a-app/memoire/facon-de-travailler.md) :"; printf '%s\n' "$fdt"; }
    for t in "$mem"/*.md; do
      [ -f "$t" ] || continue
      nb=$(grep -c -E '^- M-[0-9]+ ' "$t" 2>/dev/null)
      [ "${nb:-0}" -gt 40 ] && echo "Le tiroir $(basename "$t") a $nb lignes actives : range-le au prochain changement de phase (doublons fusionnés, l'ancien dans memoire/archive/)."
    done
  elif [ -s "$proj/.machine-a-app/decisions.md" ] || [ -s "$proj/.machine-a-app/sujets.json" ]; then
    echo "Passage à la V2 : la mémoire du projet change de forme. Avant toute autre chose, lis lire_fiche(\"ME-01\") et fais-la : decisions.md et sujets.json passent dans .machine-a-app/memoire/, avec une copie de l'ancien à côté."
  fi
  # Le fichier n'existe pas encore au premier lancement : sans ce test, « < etat.json » échoue avant que
  # 2>/dev/null ne s'applique, et l'erreur s'affiche.
  e=""; [ -f "$proj/.machine-a-app/etat.json" ] && e=$(tr -d '\n\r' < "$proj/.machine-a-app/etat.json")
  ch=$(printf '%s' "$e" | grep -o '"chantier" *: *{[^}]*}' | head -1)
  if [ -n "$ch" ]; then
    echo "Chantier en cours : $(ghostdev_champ "$ch" sujet) · stratégie $(ghostdev_champ "$ch" strategie) · étape $(ghostdev_nombre "$ch" etape)."
    fiches=$(printf '%s' "$ch" | grep -o '"fiches" *: *\[[^]]*\]' | grep -o '[A-Z][A-Z]*-[0-9][0-9]*' | tr '\n' ' ' | sed 's/ *$//')
    [ "$source_hook" = "compact" ] && [ -n "$fiches" ] && echo "Après un compactage : relis par lire_fiche les fiches du chantier ($fiches) avant de continuer."
  fi
  if [ "$source_hook" = "compact" ]; then
    rm -f "$sess/lues"
    touch "$sess/compacte"   # memoire.sh marque ses injections « après compactage » dans le journal local
    echo "Après un compactage : à ta prochaine consultation de guide, passe deja_lues vide."
  fi
else
# La mémoire du projet, visible à chaque démarrage : les dernières décisions, et les pages déjà dessinées.
dec="$proj/.machine-a-app/decisions.md"; [ -s "$dec" ] || dec="$proj/decisions.md"
if [ -s "$dec" ]; then
  echo "decisions.md, les 20 dernières lignes ($dec) :"; tail -n 20 "$dec"; echo
else
  echo "decisions.md : absent, à créer dès la première décision (.machine-a-app/decisions.md)."
fi
fi
# Ce qui a été réfléchi dans une deuxième fenêtre : la construction le lit, la personne ne recopie rien.
if [ -d "$proj/.machine-a-app/reflexion" ] && [ -n "$(ls -A "$proj/.machine-a-app/reflexion" 2>/dev/null)" ]; then
  echo "Réflexions rangées (.machine-a-app/reflexion/, la plus récente en premier) :"
  ls -lt "$proj/.machine-a-app/reflexion" | sed '1d;s/^[^ ]* *[0-9]* *[^ ]* *[^ ]* *[0-9]* *//' | head -10
  if [ -f "$sess/v2" ]; then
    echo "Lis celles que la mémoire ne porte pas encore : chaque décision devient une ligne de .machine-a-app/memoire/decisions.md, avec son étiquette ; dis en trois lignes ce que ça change, puis reprends la construction. Ne lui demande jamais de recopier."
  else
    echo "Lis celles que decisions.md ne porte pas encore : écris ce qui est décidé sous « Décidé », dis en trois lignes ce que ça change, puis reprends la construction. Ne lui demande jamais de recopier."
  fi
fi
if [ -d "$proj/prototype" ] && [ -n "$(ls -A "$proj/prototype" 2>/dev/null)" ]; then
  echo "prototype/, fichiers et dates (le plus récent en premier) :"; ls -lt "$proj/prototype" | sed '1d;s/^[^ ]* *[0-9]* *[^ ]* *[^ ]* *[0-9]* *//' | head -30
else
  echo "prototype : vide"
fi
if [ "$source_hook" = "compact" ] && [ -z "$socle" ]; then
  echo "Après une compaction : rappelle consignes et contenu_phase de la phase en cours, relis decisions.md, puis la liste de contrôle en tête de ta fiche, avant de continuer."
fi
echo "Deux mots-clés à rappeler à la personne : « turbo » pour le cerveau fort, « SOS » quand ça bloque (tu préviens Anas sur-le-champ, sans lui demander son accord)."
cv=$(curl -fsS -m 3 "$url/contenu/version" 2>/dev/null | sed -n 's/.*"commit": *"\([^"]*\)".*/\1/p'); [ -n "$cv" ] && mkdir -p "$proj/.machine-a-app" 2>/dev/null && printf '%s' "$cv" > "$proj/.machine-a-app/contenu.version"
if [ -z "$GHOSTDEV_SANS_MAJ" ]; then
  # La clé et la version partent avec : le serveur journalise ce démarrage, et l'on voit d'ici qui tourne sur
  # quelle version et si sa clé passe, sans aller sur son ordinateur.
  ent=$(sh "$(dirname "$0")/entetes.sh" 2>/dev/null)
  ck=$(printf '%s' "$ent" | sed -n 's/.*"Bearer \([^"]*\)".*/\1/p')
  distante=$(curl -fsS -m 5 -H "Authorization: Bearer $ck" -H "X-GhostDev-Plugin: ${version:-?}" "$url/plugin/version" 2>/dev/null | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')
  if [ -n "$distante" ] && [ -n "$version" ] && [ "$distante" != "$version" ]; then
    case "$root" in *"/plugins/synced/"*)
      # Ajouté depuis claude.ai : sans l'application GitHub de Claude sur le dépôt, que la personne ne peut pas poser,
      # cette copie ne se met jamais à jour. Surtout pas maj.sh : Claude refuse tout fichier en trop dans ce dossier.
      echo "Une version plus récente du plugin existe ($distante, ici $version). Cette installation ne se met pas à jour seule. Quand la personne a un moment, dis-lui en une phrase d'écrire à Anas sur WhatsApp : il la passe à l'installation qui se met à jour toute seule. Ce n'est pas bloquant : le contenu vient du serveur et il est déjà à jour."
      echo "</ghostdev-demarrage>"; exit 0;;
    esac
    case "$root" in *"/plugins/cache/"*|*"/plugins/marketplaces/"*)
      # Installé par la place de marché : c'est Claude Code qui met à jour. L'installateur allume la mise à jour
      # automatique ; elle tourne après le premier message et la version s'ouvre à la conversation suivante.
      if tr -d ' \t\r\n' < "$cfgdir/settings.json" 2>/dev/null | grep -q '"autoUpdate":true'; then
        echo "Une version plus récente du plugin existe ($distante, ici $version). Claude la télécharge tout seul pendant cette conversation et l'ouvre à la suivante : rien à proposer ni à taper. Ce n'est pas bloquant : le contenu vient du serveur et il est déjà à jour."
      else
        echo "Une version plus récente du plugin existe ($distante, ici $version). Quand la personne a un moment, propose-lui d'écrire dans Claude : /plugin update machine-a-app@ghostdev puis de relancer la session. Ce n'est pas bloquant : le contenu vient du serveur et il est déjà à jour."
      fi
      echo "</ghostdev-demarrage>"; exit 0;;
    esac
    tmp=$(mktemp -d 2>/dev/null || { mkdir -p "/tmp/ghostdev.$$" && echo "/tmp/ghostdev.$$"; })
    cp "$root/scripts/maj.sh" "$tmp/maj.sh" 2>/dev/null
    # exec : ce script ne lit plus rien après, la mise à jour peut remplacer ses fichiers sans risque.
    exec sh "$tmp/maj.sh" "$root" "$tmp" "$version" "$distante" "$url"
  fi
fi
echo "</ghostdev-demarrage>"
