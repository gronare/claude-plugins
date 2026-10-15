#!/bin/sh
# Review a repo's changes in a herdr split: an fzf list of changed files with a diff preview, Enter opens that diff
# in nvim, and c there sends a file:line comment into the Claude pane's input box.
# Files marked read stay out of the list until their contents change.
#
#   review.sh split [base [path ...]]     open the review split next to the calling pane (run from Claude's pane);
#                                         paths scope the list to the work under review, in review order
#   review.sh history                     open tig (commit history) in a split instead
#   review.sh list <base> <pane> [scope]  the file list itself, run inside the split
#
# base defaults to HEAD when the work tree has changes, else the upstream branch (unpushed commits).
# Short flags throughout: the script is shared, and BSD awk/wc/cut on macOS lack the GNU long forms.

set -eu

script="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
herdr="${HERDR_BIN_PATH:-herdr}"
tab="$(printf '\t')"

default_base() {
  if [ -n "$(git status --porcelain)" ]; then
    echo HEAD
  else
    git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo HEAD
  fi
}

# path<TAB>+added -deleted for tracked changes, then untracked files as all-new.
changed_files() {
  git diff --numstat "$1" | awk -F '\t' '{ printf "%s\t+%s -%s\n", $3, $1, $2 }'
  git ls-files --others --exclude-standard | while read -r path; do
    printf '%s\t+%s new\n' "$path" "$(wc -l < "$path" | tr -d ' ')"
  done
}

status_of() {
  if git ls-files --error-unmatch -- "$2" >/dev/null 2>&1 || git cat-file -e "$1:$2" 2>/dev/null; then
    git diff --name-status "$1" -- "$2" | cut -c 1
  else
    echo A
  fi
}

# $3 is always or never.
unified_diff() {
  case "$(status_of "$1" "$2")" in
    A) git diff --color="$3" --no-index /dev/null "$2" || true ;;
    *) git diff --color="$3" "$1" -- "$2" ;;
  esac
}

# Read marks, one "path<TAB>content hash" per line and repo. Keyed on the file's contents rather than its diff, so
# committing a file keeps it read and any edit brings it back.
read_marks() {
  dir="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-review"
  mkdir -p "$dir"
  echo "$dir/$(git rev-parse --show-toplevel | tr '/' '_')"
}

fingerprint() {
  if [ -e "$1" ]; then git hash-object -- "$1"; else echo deleted; fi
}

is_read() {
  grep -qxF "$1$tab$(fingerprint "$1")" "$(read_marks)" 2>/dev/null
}

unmark_read() {
  marks=$(read_marks)
  [ -f "$marks" ] || return 0
  awk -F '\t' -v path="$1" '$1 != path' "$marks" > "$marks.tmp" && mv "$marks.tmp" "$marks"
}

mark_read() {
  unmark_read "$1"
  printf '%s\t%s\n' "$1" "$(fingerprint "$1")" >> "$(read_marks)"
}

toggle_read() {
  if is_read "$1"; then unmark_read "$1"; else mark_read "$1"; fi
}

# path<TAB>stats lines tagged "scope" or "other": the scope file's paths first, in its order, then the remaining
# changes. Without a scope file every change is in scope.
categorized() {
  changes=$(changed_files "$1")
  if [ -z "$2" ]; then
    echo "$changes" | sed "s/^/scope$tab/"
    return
  fi
  sed 's|^\./||' "$2" | awk '!seen[$0]++' | while read -r path; do
    echo "$changes" | awk -F '\t' -v path="$path" '$1 == path { print "scope\t" $0 }'
  done
  echo "$changes" | awk -F '\t' 'NR == FNR { sub(/^\.\//, ""); scoped[$0]; next } !($1 in scoped) { print "other\t" $0 }' "$2" -
}

# One list row: the path for fzf's {1}, then what is displayed (--with-nth 2): +added -deleted in a fixed-width column,
# the path, and a note. $4 is an ANSI style for the whole row, e.g. dim for read files.
row() {
  added=${2%% *} deleted=${2#* }
  if [ "$deleted" = new ]; then deleted=""; note=" new"; else note=""; fi
  printf '%s\t%s\033[32m%6s\033[0m%s \033[31m%5s\033[0m%s  %s\033[90m%s%s\033[0m\n' \
    "$1" "$4" "$added" "$4" "$deleted" "$4" "$1" "$note" "$3"
}

# The list for fzf: a status line (fzf's --header-lines 1), then unread files in scope, unread other changes when
# $2/other exists, and read files dimmed when $2/read exists. $3 is the scope file, if any.
rows() {
  dim="$(printf '\033[2m')"
  in_scope=0 others=0 read_count=0 main="" rest="" read=""
  while IFS="$tab" read -r kind path stats; do
    [ -n "$path" ] || continue
    if [ "$kind" = other ]; then
      others=$((others + 1))
      [ -e "$2/other" ] || continue
    else
      in_scope=$((in_scope + 1))
    fi
    if is_read "$path"; then
      read_count=$((read_count + 1))
      read="$read$(row "$path" "$stats" "  ✓ read" "$dim")
"
    elif [ "$kind" = other ]; then
      rest="$rest$(row "$path" "$stats" "  other" "")
"
    else
      main="$main$(row "$path" "$stats" "" "")
"
    fi
  done <<EOF
$(categorized "$1" "${3:-}")
EOF
  # against <base> · 5 to review · 3 other hidden · 1 read hidden · ? help, counts in yellow.
  count() { printf '\033[33m%s\033[0m %s' "$1" "$2"; }
  status="against $(printf '\033[35m%s\033[0m' "$1")"
  if [ -n "${3:-}" ]; then
    status="$status  ·  $(count "$in_scope" "to review")"
    if [ "$others" -gt 0 ]; then
      if [ -e "$2/other" ]; then status="$status  ·  $(count "$others" "other shown")"; else status="$status  ·  $(count "$others" "other hidden")"; fi
    fi
  else
    status="$status  ·  $(count "$in_scope" changed)"
  fi
  if [ "$read_count" -gt 0 ]; then
    if [ -e "$2/read" ]; then status="$status  ·  $(count "$read_count" "read shown")"; else status="$status  ·  $(count "$read_count" "read hidden")"; fi
  fi
  printf '\t%s  ·  \033[1m?\033[0m help\n' "$status"
  printf '%s' "$main"
  printf '%s' "$rest"
  [ -e "$2/read" ] && printf '%s' "$read"
  return 0
}

# Shown in the preview pane by ?, until the cursor moves.
help() {
  heading() { printf '\n \033[1;35m%s\033[0m\n' "$1"; }
  key() { printf '   \033[1m%-12s\033[0m%s\n' "$1" "$2"; }
  heading "File list"
  key "type" "filter; !word hides matches (!spec/ is prefilled)"
  key "enter" "open the file's diff"
  key "ctrl-r" "mark the file read, or unread"
  key "ctrl-h" "show or hide read files"
  key "ctrl-o" "show or hide changes outside the review"
  key "ctrl-c" "close the split (or close the pane from herdr)"
  heading "Diff"
  key "c" "comment on the line, or a visual selection"
  key "o" "open the file over the diff, at that line"
  key "-" "open the file's folder over the diff"
  key "w" "toggle line wrap"
  key "r" "mark read and go back to the list"
  key "q  esc" "back to the list"
  heading "Opened files (the float)"
  key "leader m" "comment on the line, or a visual selection (leader is space in many configs)"
  key "ctrl-q" "back to the diff"
  printf '   %s\n' "Everything else is your usual nvim. Saved edits are" "reported to Claude when you go back to the diff."
  heading "Good to know"
  printf '   %s\n' "Comments are typed into Claude's input box; nothing is" "sent until you press Enter there." "" "A read file comes back when its contents change." "" "Move the cursor to get the diff preview back."
}

open() {
  unified_diff "$1" "$2" never |
    REVIEW_PATH="$2" REVIEW_BASE="$1" REVIEW_SCRIPT="$script" nvim -S "$(dirname "$script")/review.lua" - || true
}

# $3, when given, is a file of repo-relative paths that make up the work under review, in review order.
list() {
  scope="${3:-}"
  if [ -z "$(changed_files "$1")" ]; then
    echo "Nothing to review against $1."
    sleep 2
    return
  fi
  # Which extra rows are shown lives in a directory (flag files read and other), so bindings can flip it between reloads.
  view=$(mktemp -d)
  trap 'rm -rf "$view" ${scope:+"$scope"}' EXIT
  reload="reload(sh '$script' rows '$1' '$view' '$scope')"
  flip() { echo "execute-silent(if [ -e '$view/$1' ]; then rm '$view/$1'; else touch '$view/$1'; fi)+$reload"; }
  sh "$script" rows "$1" "$view" "$scope" | REVIEW_AGENT_PANE="$2" fzf \
    --ansi --header-lines 1 \
    --delimiter '\t' --with-nth 2 \
    --query '!spec/ ' \
    --layout reverse --info inline-right --prompt '  ' --pointer '▌' \
    --color 'prompt:magenta,pointer:magenta,hl:yellow,hl+:yellow,info:bright-black' \
    --preview "sh '$script' preview '$1' {1}" \
    --preview-window 'right,60%,<140(down,70%)' \
    --bind "enter:execute(sh '$script' open '$1' {1})+$reload" \
    --bind "ctrl-r:execute-silent(sh '$script' toggle-read {1})+$reload" \
    --bind "ctrl-h:$(flip read)" \
    --bind "ctrl-o:$(flip other)" \
    --bind "?:preview(sh '$script' help)" \
    --bind 'esc:ignore,ctrl-q:ignore,ctrl-g:ignore' || true
}

# Opens a split right of the calling pane, labelled $1, running $2; the split closes when $2 exits.
open_split() {
  root=$(git rev-parse --show-toplevel)
  pane=$("$herdr" pane split --current --direction right --cwd "$root" --focus | jq -r '.result.pane.pane_id')
  "$herdr" pane rename "$pane" "$1" >/dev/null
  "$herdr" pane run "$pane" "$2; exit" >/dev/null
  echo "$pane"
}

# split [base [path ...]]: paths limit the list to the work under review, the rest of the changes one key away.
split() {
  base="${1:-$(default_base)}"
  [ $# -gt 0 ] && shift
  scope=""
  if [ $# -gt 0 ]; then
    scope=$(mktemp)
    printf '%s\n' "$@" > "$scope"
  fi
  open_split review "sh '$script' list '$base' '$HERDR_PANE_ID' '$scope'"
}

command="${1:-}"
[ $# -gt 0 ] && shift
case "$command" in
  split) split "$@" ;;
  history) open_split history "tig" ;;
  list) list "$@" ;;
  rows) rows "$@" ;;
  preview) unified_diff "$1" "$2" always ;;
  diff) unified_diff "$1" "$2" never ;;
  open) open "$@" ;;
  mark-read) mark_read "$1" ;;
  toggle-read) toggle_read "$1" ;;
  help) help ;;
  *) echo "usage: review.sh split [base [path ...]] | review.sh history" >&2; exit 2 ;;
esac
