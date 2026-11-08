#!/bin/sh
# Garde-fou GhostDev, appelé avant chaque commande et chaque écriture. La personne nous a donné la main : à nous
# d'être sûrs. Ce qui passe les contrôles est autorisé sans question si elle a répondu oui (voir autoriser()).
# Trois refus : 1. Xcode s'il n'est pas déjà là. 2. Ce qui détruit ou touche le système de sa machine.
# 3. Ce qui efface son travail à elle (ses écrans, ses décisions, ses fichiers non enregistrés).
# Et une règle de bon sens : ce que le playbook prescrit doit passer, sinon la mise en ligne s'arrête au milieu.
# Sortie 2 = commande bloquée, le message revient à Claude. sh seulement : jamais python, jamais node.
sh "$(dirname "$0")/actif.sh" || exit 0   # muet tant que GhostDev n'a pas été lancé dans ce dossier
. "$(dirname "$0")/chemins.sh"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
proj=$(ghostdev_chemin "$proj")
entree=$(cat)

# « Oui, je te donne la main » : l'agent range consentement = main_libre dans etat.json. Jusqu'à la 0.9.9, rien ne
# le lisait, et Claude Code demandait l'autorisation à chaque geste malgré ce oui (vu lors d'un échange, le 19 septembre 2026).
# Maintenant, ce que ce garde-fou a vérifié passe sans question. Les règles « deny » des réglages et les chemins
# protégés de Claude Code (.git, .claude) restent au-dessus : la doc dit qu'un hook ne peut pas les lever.
# Réponse « Non, demande-moi » : rien n'est autorisé ici, Claude Code demande comme d'habitude.
# Le même oui sert à deux moments : avant le geste (PreToolUse), et en filet quand Claude Code s'apprête quand même
# à ouvrir sa fenêtre (PermissionRequest). L'essai du 08/11, en mode « Accepter les modifications », a vu des fenêtres
# pour des outils que la liste « allow » couvrait déjà.
oui() {
  if [ "$evenement" = "PermissionRequest" ]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
  else
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"GhostDev : la personne a donné la main, et le garde-fou a vérifié ce geste."}}'
  fi
  exit 0
}
autoriser() {
  grep -q '"consentement" *: *"main_libre"' "$proj/.machine-a-app/etat.json" 2>/dev/null || exit 0
  oui
}

# Les outils autres que Bash : lire, écrire, chercher sur internet, sa page, le navigateur et le simulateur de
# l'app. Bash passe par tous les contrôles plus bas.
plat=$(printf '%s' "$entree" | tr -d '\n\r')
outil=$(printf '%s' "$plat" | sed -n -E 's/^.*"tool_name" *: *"([^"]*)".*$/\1/p')
evenement=$(printf '%s' "$plat" | sed -n -E 's/^.*"hook_event_name" *: *"([^"]*)".*$/\1/p')
if [ -n "$outil" ] && [ "$outil" != "Bash" ]; then
  case "$outil" in
    # Ses propres outils : la méthode, lue ou consultée. Ils ne changent rien chez elle : permis dès le lancement.
    mcp__plugin_*ghostdev__*) oui ;;
    # Sa page de suivi. Restent à elle : supprimer une page ou une ligne, et la mise en ligne qui donne à la page sa
    # mémoire et ses téléchargements (« capabilities »), que Claude Code fait toujours confirmer, une fois.
    Artifact|ArtifactData|ArtifactComments)
      printf '%s' "$plat" | grep -q -E '"action" *: *"delete"|"capabilities" *:' && exit 0
      autoriser ;;
    mcp__Claude_Browser__*|mcp__Claude_Code_iOS_Simulator__*) autoriser ;;
    WebFetch|WebSearch) autoriser ;;
    Read|Glob|Grep)
      # Lire est permis partout (son code peut être ailleurs), sauf là où dorment ses clés et ses mots de passe.
      case "$plat" in *"/.ssh"*|*"/.aws"*|*"/.gnupg"*|*"/.config/"*|*"/Library/Keychains"*|*".netrc"*|*"/.docker/"*) exit 0 ;; esac
      autoriser ;;
    Edit|Write|MultiEdit|NotebookEdit)
      # Écrire, seulement dans le dossier du projet. Ailleurs, Claude Code demande, comme d'habitude.
      chemin=$(printf '%s' "$plat" | sed -n -E 's/^.*"(file_path|notebook_path)" *: *"([^"]*)".*$/\2/p')
      [ -n "$chemin" ] || exit 0
      chemin=$(ghostdev_chemin "$chemin")
      case "$chemin" in */../*|*/..|../*) exit 0 ;; esac
      case "$chemin" in /*) ;; *) chemin="$proj/$chemin" ;; esac
      case "$chemin" in "$proj"/*) autoriser ;; esac
      exit 0 ;;
  esac
  exit 0
fi

# La commande, extraite proprement du JSON du hook : on s'arrête au guillemet fermant non échappé, et on
# ne prend pas les autres champs (« description » contenait « supprime le dossier » et faisait tout bloquer).
# En entier : elle était coupée à 4 000 caractères, et tout ce qui venait après passait sans contrôle.
cmd=$(printf '%s' "$entree" | awk '
  { tout = tout $0 "\n" }
  END {
    i = index(tout, "\"command\"")
    if (i == 0) exit
    s = substr(tout, i + 9)
    q = index(s, "\"")
    if (q == 0) exit
    s = substr(s, q + 1)
    pos = 1; out = ""
    while (1) {
      reste = substr(s, pos)
      q = index(reste, "\"")
      if (q == 0) { out = out reste; break }
      abs = pos + q - 1
      nb = 0; k = abs - 1
      while (k >= 1 && substr(s, k, 1) == "\\") { nb++; k-- }
      if (nb % 2 == 0) { out = out substr(s, pos, abs - pos); break }
      out = out substr(s, pos, abs - pos + 1)
      pos = abs + 1
    }
    gsub(/\\n/, " ", out); gsub(/\\t/, " ", out); gsub(/\\"/, "\"", out); gsub(/\\\\/, "\\", out)
    printf "%s", out
  }
')
[ -n "$cmd" ] || cmd="$entree"
if [ "$(printf '%s' "$cmd" | wc -c)" -gt 200000 ]; then
  echo "GhostDev : commande trop longue pour être vérifiée (plus de 200 000 caractères). Découpe-la en plusieurs commandes courtes, ou écris un script dans le dossier du projet et lance-le." >&2
  exit 2
fi

# 1. Xcode : interdit seulement s'il n'est pas déjà installé. Avec Xcode présent, compiler et tester en local est permis.
# `xcode-select --install` n'est pas Xcode : ce sont les outils de ligne de commande d'Apple (git, environ 1 Go), sans
# lesquels un Mac n'a pas de git. Il passe, et la fiche RE-03 fait demander son accord avant (ticket 29, 2026-10-08).
xcode_present=0; [ -z "$GHOSTDEV_SANS_XCODE" ] && xcodebuild -version >/dev/null 2>&1 && xcode_present=1
if [ "$xcode_present" = 0 ] && { printf '%s' "$cmd" | grep -q -E 'xcodebuild|flutter build (ios|ipa|macos)|open -a Xcode|pod install|mas install 497799835' || { printf '%s' "$cmd" | grep -q 'xcrun' && ! printf '%s' "$cmd" | grep -q 'xcrun simctl'; }; }; then
  echo "GhostDev : Xcode n'est pas sur cette machine, et on ne l'installe jamais pour la personne. La compilation iOS passe par Codemagic, en ligne. Trouve la voie en ligne." >&2
  exit 2
fi

# 2. Les installateurs officiels que les fiches d'Anas prescrivent. Un « curl | sh » venu d'ailleurs reste bloqué.
installateur_connu=0
if printf '%s' "$cmd" | grep -q -E 'https://(dokploy\.com/install\.sh|get\.maestro\.mobile\.dev|rclone\.org/install\.sh|get\.docker\.com|storage\.googleapis\.com/flutter_infra_release|sh\.rustup\.rs|astral\.sh/uv/install\.sh)'; then
  installateur_connu=1
fi
if [ "$installateur_connu" = 0 ] && printf '%s' "$cmd" | grep -q -E '(curl|wget)[^|]*\| *(sudo +)?(sh|bash|zsh)'; then
  echo "GhostDev : cette commande télécharge un script sur internet et l'exécute tout de suite, et son adresse n'est pas dans les fiches d'Anas. Cherche la page officielle de l'outil et son paquet, ou demande à Anas d'ajouter cette adresse. Les installateurs déjà connus (Dokploy, Docker, rclone, Maestro, Flutter) passent sans rien demander." >&2
  exit 2
fi

# 3. Une commande jouée sur le serveur de la personne (ssh) : c'est sa machine à elle, que les fiches montent
# de zéro. sudo, apt, ufw, systemctl y sont normaux. Les destructions, elles, restent bloquées partout.
distante=0
printf '%s' "$cmd" | grep -q -E '(^|[;&|] *)(ssh|scp|rsync)[[:space:]]' && distante=1

# Un installateur reconnu qui demande les droits dans son tube (rclone : « | sudo bash ») reste permis :
# c'est sa façon officielle de s'installer, et l'adresse a déjà été vérifiée juste au-dessus.
cmd_sys="$cmd"
[ "$installateur_connu" = 1 ] && cmd_sys=$(printf '%s' "$cmd" | sed -E 's/\| *sudo +(bash|sh|zsh)/| \1/g')

if [ "$distante" = 0 ] && printf '%s' "$cmd_sys" | grep -q -E '(^|[;&|] *)(sudo|su)[[:space:]]|chmod -R 777|chown -R|(^|[;&|] *)(shutdown|reboot|killall|halt)[[:space:]]|launchctl (unload|remove)|defaults delete|systemctl (stop|disable)'; then
  echo "GhostDev : cette commande touche le système de son ordinateur, et on n'y touche jamais. Reste dans le dossier du projet, ou joue la commande sur son serveur par ssh si c'est le serveur qu'on installe." >&2
  exit 2
fi

# 4. Ce qui détruit, partout, y compris sur son serveur.
if printf '%s' "$cmd" | grep -q -E 'rm -[a-zA-Z]*r[a-zA-Z]* +(-[a-zA-Z]+ +)*(/|~|\$HOME|\.\.|\*|/[A-Za-z])|rm -[a-zA-Z]*r[a-zA-Z]* .*\.git( |$)|git push[^|]* (--force|-f)( |$)|git reset --hard|git clean -[a-zA-Z]*f|mkfs|diskutil (erase|reformat)|dd if=|> */dev/(sd|disk)|:\(\)\{'; then
  echo "GhostDev : commande dangereuse bloquée. Rien ne se supprime en masse, rien ne sort du dossier du projet, rien ne touche le système. Trouve une voie qui ne détruit rien ; s'il faut vraiment supprimer, fais d'abord une copie dans .machine-a-app/sauvegardes/ et supprime fichier par fichier." >&2
  exit 2
fi

# 5. Son travail à elle. Les fichiers fabriqués (build, node_modules) se suppriment sans rien perdre ;
# ses écrans, ses décisions et son idée, jamais : c'est ce que agent.md lui promet.
if printf '%s' "$cmd" | grep -q -E 'rm -[a-zA-Z]*r[a-zA-Z]* +(-[a-zA-Z]+ +)*("|'"'"')?[^ ]*(prototype|\.machine-a-app|IDEE\.md|decisions\.md|style\.json|cahier-technique\.md|inventaire-code\.md)|(^|[;&|] *)(rm|mv) +(-[a-zA-Z]+ +)*("|'"'"')?(prototype|\.machine-a-app|IDEE\.md|decisions\.md|style\.json)'; then
  echo "GhostDev : ça effacerait le travail de la personne (ses écrans, ses décisions, son idée). On ne supprime jamais ça. Si un fichier doit vraiment partir, copie-le d'abord dans .machine-a-app/sauvegardes/<date>/ et dis-le-lui en une phrase." >&2
  exit 2
fi

# 6. Tout jeter d'un coup dans git : permis seulement s'il n'y a rien à perdre. Le playbook le prescrit
# (normaliser les fins de ligne juste après un commit), et à ce moment-là le dépôt est propre.
if printf '%s' "$cmd" | grep -q -E 'git (checkout|restore) (--)? *\.( |$)|git checkout -- \.|find [^|]* -delete|git branch -D'; then
  sale=$(git -C "$proj" status --porcelain 2>/dev/null | head -1)
  if [ -n "$sale" ]; then
    echo "GhostDev : cette commande jetterait tout ce qui n'est pas encore enregistré dans le projet, et il y a du travail en cours. Enregistre d'abord (git add -A puis git commit), ou vise le seul fichier concerné au lieu du dossier entier." >&2
    exit 2
  fi
fi

# Tous les contrôles sont passés.
autoriser
