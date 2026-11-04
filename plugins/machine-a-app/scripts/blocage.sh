#!/bin/sh
# V2 : le compteur de blocage (navigation, section 11 ; la règle du 2026-09-11 : le compteur suit la chose bloquée,
# jamais la cause). Hooks PostToolUse et PostToolUseFailure sur Bash. Une commande qui échoue arrive en
# PostToolUseFailure, avec « Exit code N » en tête de son erreur (doc des hooks, « PostToolUseFailure input ») : elle
# compte un échec pour sa chose (le programme et son premier argument : « flutter build », « git push » ; avec npm, npx, yarn et pnpm, l'argument suivant aussi : « npm run build »). La même chose
# qui réussit (PostToolUse) remet son compte à zéro. Au troisième échec d'affilée : ST-09 entre dans les arrêts et
# Claude est prié d'escalader. Un essai interrompu (is_interrupt) ne compte pas ; une lecture (grep, ls, cat…) non
# plus. Tout reste sur l'ordinateur, dans la session. Muet pour un sous-agent. sh seulement, jamais une boucle.
sh "$(dirname "$0")/actif.sh" || exit 0
. "$(dirname "$0")/chemins.sh"; . "$(dirname "$0")/donnees.sh"
proj=$(ghostdev_chemin "${CLAUDE_PROJECT_DIR:-$PWD}")
[ -f "$proj/.demo/scenario" ] && exit 0
plat=$(cat 2>/dev/null | tr -d '\n\r')
case "$plat" in *'"agent_id"'*) exit 0 ;; esac
sess=$(ghostdev_session "$(ghostdev_champ "$plat" session_id)")
[ -f "$sess/v2" ] || exit 0
[ "$(ghostdev_champ "$plat" tool_name)" = Bash ] || exit 0
printf '%s' "$plat" | grep -q '"is_interrupt" *: *true' && exit 0
evt=$(ghostdev_champ "$plat" hook_event_name)
# La chose : la première commande qui n'est ni un « cd », ni un « export », sans ses variables posées devant ; son
# programme sans chemin, et son premier argument qui n'est pas une option.
# La commande est lue ici, pas par ghostdev_champ (partagée : elle s'arrête au premier \" ) : elle tolère les guillemets
# échappés (cd "mon app" && …) et les désérialise.
commande=$(printf '%s' "$plat" | grep -oE '"command" *: *"([^"\\]|\\.)*"' | head -1 | sed 's/^[^:]*: *"//; s/"$//; s/\\"/"/g; s/\\\\/\\/g')
chose=$(printf '%s' "$commande" | awk '{
  gsub(/\\[nt]/, " ")
  n = split($0, morceaux, /&&|\|\||;|\|/)
  for (i = 1; i <= n; i++) {
    s = morceaux[i]; gsub(/^[ \t]+|[ \t]+$/, "", s)
    if (s == "" || s ~ /^(cd|export|set|source|\.)( |$)/) continue
    m = split(s, w, /[ \t]+/); j = 1
    while (j <= m && (w[j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || w[j] ~ /^(sudo|env|time|nohup|command)$/)) j++
    if (j > m) continue
    p = w[j]; sub(/.*\//, "", p); a = ""; b = ""
    for (k = j + 1; k <= m; k++) if (w[k] !~ /^-/) { a = w[k]; break }
    # npm run build et npm run test sont deux choses : pour ces lanceurs, l argument suivant fait partie de la chose.
    if (p ~ /^(npm|npx|yarn|pnpm)$/ && a != "")
      for (l = k + 1; l <= m; l++) if (w[l] !~ /^-/) { b = w[l]; break }
    print p (a == "" ? "" : " " a) (b == "" ? "" : " " b); exit
  }
}' | tr -cd 'A-Za-z0-9 ._:/@=+-' | cut -c1-60)
case "${chose%% *}" in
  ""|grep|egrep|fgrep|rg|ls|test|"["|cat|find|which|type|head|tail|wc|diff|cmp|pgrep|sleep|true|false) exit 0 ;;
esac
# Les outils d'analyse et de style échouent pour des raisons qui changent à chaque ligne corrigée : ce n'est pas une
# chose bloquée.
case "$chose" in
  "flutter analyze"*|"dart analyze"*|"dart format"*|"flutter format"*|"npm run lint"*|"npx eslint"*|"npx prettier"*|ruff|ruff\ *|black|black\ *|flake8|flake8\ *) exit 0 ;;
esac
f="$sess/echecs"; touch "$f"
if [ "$evt" = PostToolUse ]; then
  awk -F '\t' -v k="$chose" '$2 != k' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  exit 0
fi
[ "$evt" = PostToolUseFailure ] || exit 0
n=$(awk -F '\t' -v k="$chose" '$2 == k { print $1; exit }' "$f"); n=$(( ${n:-0} + 1 ))
{ awk -F '\t' -v k="$chose" '$2 != k' "$f"; printf '%s\t%s\n' "$n" "$chose"; } > "$f.tmp" && mv "$f.tmp" "$f"
[ "$n" -eq 3 ] || exit 0
grep -q -x 'ST-09' "$sess/lues" 2>/dev/null || grep -q -x 'ST-09' "$sess/arrets" 2>/dev/null || printf 'ST-09\n' >> "$sess/arrets"
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":"%s"}}\n' "$(ghostdev_json "GhostDev : trois échecs d'affilée sur la même chose (« $chose »), quelle que soit la cause. Ne relance pas une quatrième fois. Lis ST-09 (lire_fiche(\"ST-09\")), puis appelle l'outil escalader avec la chose bloquée, en une ligne : il ouvre le ticket. Ensuite fais le diagnostic de lab (methode_diagnostic) et envoie-le par rapport avec le numéro du ticket, dans ce tour : les trois essais et leur erreur vont dans le rapport. Annonce-le-lui en une phrase, puis avance sur autre chose.")"
exit 0
