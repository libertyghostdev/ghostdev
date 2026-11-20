#!/bin/sh
# La sauvegarde, par défaut, sans que la personne y pense : un ordinateur perdu ne coûte plus rien.
# Hook Stop. À la fin d'un tour, cinq minutes au plus après la précédente : le coffre chiffré s'il a changé, puis tout
# ce qui a changé envoyé sur son GitHub privé, en fond. Muet : jamais un mot à la personne, jamais un tour bloqué.
# Rien ne part si le dossier n'a pas de dépôt relié (origin), ou si le coffre ou un .env ne sont pas ignorés par git.
# Le coffre voyage seulement chiffré (.machine-a-app/coffre.chiffre), fermé par la phrase de .machine-a-app/coffre/.phrase,
# que la personne garde aussi ailleurs (FQ-15) : sans elle, la copie ne se lit pas, ni par GitHub ni par Anas.
sh "$(dirname "$0")/actif.sh" || exit 0
. "$(dirname "$0")/chemins.sh"
proj=$(ghostdev_chemin "${CLAUDE_PROJECT_DIR:-$PWD}")
[ -f "$proj/.demo/scenario" ] && exit 0
[ -n "$GHOSTDEV_SANS_SAUVEGARDE" ] && exit 0
cd "$proj" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
git remote get-url origin >/dev/null 2>&1 || exit 0
gd=$(git rev-parse --git-dir 2>/dev/null) || exit 0
# Une opération git en cours (fusion, rebase) : on ne touche à rien.
[ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ] || [ -f "$gd/MERGE_HEAD" ] && exit 0
# Cinq minutes au plus entre deux sauvegardes.
t="$gd/ghostdev-sauvegarde"
[ -n "$(find "$t" -mmin -5 2>/dev/null)" ] && exit 0

(
  # Ce qui ne voyage jamais en clair : posé dans .gitignore s'il manque. Une ancienne ligne « .machine-a-app/ »
  # entière laisse la place au détail : la mémoire, l'état et le tableau suivent le code, le dépôt est privé.
  gi="$proj/.gitignore"; touch "$gi"
  if grep -qx '\.machine-a-app/\{0,1\}' "$gi"; then
    { grep -vx '\.machine-a-app/\{0,1\}' "$gi" || :; } > "$gi.tmp" && mv -f "$gi.tmp" "$gi"
  fi
  for l in ".machine-a-app/coffre/" ".machine-a-app/sauvegardes/" ".machine-a-app/miroir/" ".machine-a-app/tmp/" ".env*" "!.env.example"; do
    grep -qxF "$l" "$gi" || printf '%s\n' "$l" >> "$gi"
  done
  # Le garde : si le coffre ou un .env pouvaient partir, rien ne part.
  if [ -d .machine-a-app/coffre ] && ! git check-ignore -q .machine-a-app/coffre/x; then exit 0; fi
  for e in .env .env.local .env.production; do [ -f "$e" ] && ! git check-ignore -q "$e" && exit 0; done

  # Le coffre chiffré, refait seulement s'il a changé.
  c=.machine-a-app/coffre
  if [ -d "$c" ] && [ -s "$c/.phrase" ] && command -v openssl >/dev/null 2>&1; then
    emp=$(cd "$c" && find . -type f ! -name .phrase ! -name .empreinte -exec cksum {} + 2>/dev/null | sort | cksum)
    if [ "$emp" != "$(cat "$c/.empreinte" 2>/dev/null)" ]; then
      if tar -cf - -C "$c" --exclude ./.phrase --exclude ./.empreinte . 2>/dev/null \
        | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass "file:$c/.phrase" -out .machine-a-app/coffre.chiffre.tmp 2>/dev/null; then
        mv -f .machine-a-app/coffre.chiffre.tmp .machine-a-app/coffre.chiffre && printf '%s' "$emp" > "$c/.empreinte"
      else rm -f .machine-a-app/coffre.chiffre.tmp; fi
    fi
  fi

  touch "$t"
  git add -A >/dev/null 2>&1 || exit 0
  if ! git diff --cached --quiet 2>/dev/null; then
    nom=$(git config user.name); mail=$(git config user.email)
    git -c user.name="${nom:-GhostDev}" -c user.email="${mail:-ghostdev@users.noreply.github.com}" \
      commit -q --no-verify -m "Sauvegarde GhostDev du $(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1 || exit 0
  fi
  # Rien à envoyer : fini.
  [ -z "$(git rev-list '@{u}..HEAD' 2>/dev/null)" ] && git rev-parse '@{u}' >/dev/null 2>&1 && { rm -f "$gd/ghostdev-envoi-refuse"; exit 0; }
  b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}" git push -q -u origin "$b" >/dev/null 2>&1; then
    rm -f "$gd/ghostdev-envoi-refuse"
  else
    date '+%Y-%m-%d %H:%M' > "$gd/ghostdev-envoi-refuse"   # demarrage.sh le dit à GhostDev
  fi
) </dev/null >/dev/null 2>&1 &
exit 0
