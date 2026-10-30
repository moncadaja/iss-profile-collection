#!/bin/bash
# Sign the unsigned agent commits on branch pixi-pyqt6-migration in each fork and push.
# Run as your own user (not xf08id) outside the Claude sandbox:  bash sign_and_push.sh [repo ...]
#
# NFS quirk: git creates loose objects read-only and this export rejects the write at close(),
# so each rebase writes its objects to /tmp and they are copied into .git/objects afterwards.
cd "$(dirname "${BASH_SOURCE[0]}")"
B=pixi-pyqt6-migration

is_signed() { git -C "$1" cat-file -p "$2" | awk '/^$/{exit} /^gpgsig(-sha256)? /{f=1} END{exit !f}'; }

sign_push() { local repo=$1 base=$2 c unsigned=0
  echo "=== $repo"
  if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ]; then
    echo "    SKIP: uncommitted changes (commit or stash them first)"; return
  fi
  if [ "$(git -C "$repo" branch --show-current)" != "$B" ]; then
    echo "    SKIP: not on $B"; return
  fi
  for c in $(git -C "$repo" rev-list "$base..HEAD"); do is_signed "$repo" "$c" || unsigned=1; done
  if [ -z "$(git -C "$repo" rev-list "$base..HEAD")" ]; then echo "    nothing to sign"; return; fi
  if [ $unsigned -eq 0 ]; then
    echo "    already signed"
  else
    local objdir="/tmp/gitobj-$repo-$USER"
    rm -rf "$objdir"; mkdir -p "$objdir"
    if ! GIT_OBJECT_DIRECTORY="$objdir" GIT_ALTERNATE_OBJECT_DIRECTORIES="$PWD/$repo/.git/objects" \
         git -C "$repo" rebase --exec "git commit --amend --no-edit -S" "$base"; then
      echo "    FAILED: signing rebase stopped; fix and run 'git -C $repo rebase --continue' (objects in $objdir)"; return
    fi
    ( cd "$objdir" && find . -type f | while read -r f; do install -D -m 444 "$f" "$OLDPWD/$repo/.git/objects/$f"; done )
    git -C "$repo" fsck --connectivity-only || { echo "    FAILED: fsck after copying objects; keep $objdir"; return; }
    rm -rf "$objdir"
    git -C "$repo" --no-pager log --format='    %h %G? %s' "$base..HEAD" 2>/dev/null
  fi
  git -C "$repo" push --force-with-lease origin "$B"
}

declare -A BASES=(
  [isstools]=547ca388d28b70ba270bcfc319266ec83dcb9e41
  [xview]=9ca42e3f1ef4b02b3aa56202c4ebef6bf9a01867
  [xsample]=4fff80120f2f4ddee73150896f5b2e2fd1fef2e6
  [xas]=c9ea90ad43500081fcb6a411ee5e423a565a1bfe
  [xpilatus]=f709351b272d43dd21e8dcd72db1375fc60cc0d1
  [issfactortools]=0f0f8e5fd3a3c46b801842c979d4505eb4b63516
  [isscloudtools]=8a88465517aad082d17853c53f3e7152808f435e
  [iss-profile-collection]=b2c6b292c51ec4983d041165aff6b6ce641bd13a
  [profile_sample-environment]=455db54b7b791530bb2029f619a66aa307e83abe
  [profile_pilatus]=7016fd4cdbfcd8678bb9a2e31c165e8ef1cca554
  [xviewlite]=78b1534f36136fcdf95dcb5d3134310fae637179
  [qmicroscope]=86b85b2e2a83c3e61386006830eacaf174c8bcc4
  [iss-workflows]=b62f08ad63d115c283c0082e77fb9c186cb04ed8
  [profile_analysis]=8d1d5a6823a01e68985f3e56b4e1b41c429d9588
)
ORDER="isstools xview xsample xas xpilatus issfactortools isscloudtools iss-profile-collection profile_sample-environment profile_pilatus xviewlite qmicroscope iss-workflows profile_analysis"
[ $# -gt 0 ] && ORDER="$*"

for repo in $ORDER; do
  if [ "$repo" = profile_analysis ]; then
    # history.sqlite (IPython history) is rewritten by XView; park it while signing
    git -C profile_analysis stash push -q -- history.sqlite 2>/dev/null && restore=1 || restore=0
    sign_push profile_analysis "${BASES[$repo]}"
    [ $restore -eq 1 ] && git -C profile_analysis stash pop -q
  else
    sign_push "$repo" "${BASES[$repo]}"
  fi
done
