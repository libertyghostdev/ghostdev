#!/bin/sh
# « lance GhostDev » : pose la marque du dossier et ses réglages, puis affiche le contexte de démarrage.
# Appelé par le skill ghostdev, jamais seul. sh seulement. Ne touche jamais aux réglages globaux (~/.claude/settings.json).
. "$(dirname "$0")/chemins.sh"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
proj=$(ghostdev_chemin "$proj")
mkdir -p "$proj/.machine-a-app" "$proj/.claude" || { echo "Impossible d'écrire dans $proj"; exit 1; }
# Pas de "defaultMode" ici, jamais. Documenté : « If you set "bypassPermissions" in [.claude/settings.json
# ou .claude/settings.local.json], it doesn't take effect either, and the session starts in Manual mode. »
# Écrire ce mode faisait donc l'inverse de ce qu'on croyait : il était jeté, et la session repartait en
# Manual, le mode qui demande le plus, au lieu du mode automatique par défaut des offres Pro et Max.
# Ce qui marche depuis un fichier de dossier, c'est la liste des commandes autorisées. Elle couvre ce que
# GhostDev lance vraiment, rien de plus. Les garde-fous restent le hook PreToolUse (garde-fou.sh) et le
# coupe-circuit de Claude Code, qu'aucune autorisation ne peut contourner sur un rm visant un chemin vital.
reglages='{
  "agent": "machine-a-app",
  "permissions": {
    "allow": [
      "mcp__plugin_machine-a-app_ghostdev", "mcp__plugin_machine-a-app_ghostdev__*",
      "Artifact", "ArtifactData", "ArtifactComments",
      "Bash(flutter:*)", "Bash(dart:*)", "Bash(pod:*)", "Bash(xcrun:*)", "Bash(adb:*)",
      "Bash(keytool:*)", "Bash(java:*)", "Bash(gradle:*)", "Bash(./gradlew:*)",
      "Bash(git:*)", "Bash(gh:*)",
      "Bash(python3:*)", "Bash(pip3:*)", "Bash(node:*)", "Bash(npm:*)", "Bash(npx:*)",
      "Bash(docker:*)", "Bash(docker compose:*)",
      "Bash(curl:*)", "Bash(dig:*)", "Bash(ssh:*)", "Bash(scp:*)", "Bash(rsync:*)",
      "Bash(open:*)", "Bash(sips:*)", "Bash(magick:*)", "Bash(cwebp:*)",
      "Bash(mkdir:*)", "Bash(cp:*)", "Bash(mv:*)", "Bash(touch:*)", "Bash(chmod:*)",
      "Bash(ls:*)", "Bash(cat:*)", "Bash(head:*)", "Bash(tail:*)", "Bash(wc:*)",
      "Bash(grep:*)", "Bash(sed:*)", "Bash(awk:*)", "Bash(find:*)", "Bash(sort:*)", "Bash(uniq:*)",
      "Bash(unzip:*)", "Bash(zip:*)", "Bash(tar:*)", "Bash(base64:*)", "Bash(which:*)", "Bash(command:*)",
      "Bash(sh .demo/acte.sh:*)", "Bash(sh scripts/:*)", "Bash(bash scripts/:*)"
    ],
    "deny": [
      "Bash(sudo:*)", "Bash(rm -rf /:*)", "Bash(rm -rf ~:*)", "Bash(rm -rf $HOME:*)",
      "Bash(git push --force:*)", "Bash(git push -f:*)",
      "Bash(mkfs:*)", "Bash(dd if=:*)", "Bash(shutdown:*)", "Bash(reboot:*)"
    ]
  }
}'
f="$proj/.claude/settings.json"; l="$proj/.claude/settings.local.json"
# Un dossier marqué avant la version 0.9.9 porte le mode qui était jeté en silence, et démarrait donc en
# Manual. On le réécrit, une fois, en gardant une copie à côté.
for ancien in "$f" "$l"; do
  if grep -q 'bypassPermissions' "$ancien" 2>/dev/null && grep -q '"machine-a-app"' "$ancien" 2>/dev/null; then
    cp "$ancien" "$ancien.avant-0.9.9" 2>/dev/null
    printf '%s\n' "$reglages" > "$ancien" &&
      echo "Réglages du dossier remis à jour ($(basename "$ancien")) : l'ancien mode était ignoré par Claude Code et faisait démarrer en Manual. Copie de l'ancien à côté, en .avant-0.9.9."
  fi
done
if grep -q '"machine-a-app"' "$f" "$l" 2>/dev/null; then
  echo "GhostDev était déjà actif dans $proj : rien à changer."
elif [ ! -s "$f" ]; then
  printf '%s\n' "$reglages" > "$f" && echo "GhostDev activé dans $proj (réglages du dossier écrits dans .claude/settings.json)."
elif [ ! -s "$l" ]; then
  printf '%s\n' "$reglages" > "$l" && echo "GhostDev activé dans $proj (réglages du dossier écrits dans .claude/settings.local.json, à côté des réglages existants)."
else
  echo "GhostDev activé dans $proj, mais .claude/settings.json et settings.local.json existent déjà : ajoute-y à la main \"agent\": \"machine-a-app\" et la permission mcp__plugin_machine-a-app_ghostdev."
fi
echo "Marque posée : $proj/.machine-a-app. Aux prochaines sessions dans ce dossier, GhostDev démarre seul."
# Le contexte de démarrage tout de suite (version, dossier des données, clé, outils, état, dossier synchronisé),
# pour que le modèle n'aille pas fouiller le dossier lui-même. Sans mise à jour du plugin à ce moment :
# le hook de démarrage s'en occupe aux sessions suivantes.
export GHOSTDEV_SANS_MAJ=1
CLAUDE_PROJECT_DIR="$proj" sh "$(dirname "$0")/demarrage.sh" < /dev/null
