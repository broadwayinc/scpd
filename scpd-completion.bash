# Bash tab completion for scpd: completes remote paths over ssh.
# Loaded from ~/.bashrc by install-scpd.sh; only affects the `scpd` command.

_SCPD_SH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/scpd.sh"

# Local file completion that also understands a leading ~ (filenames option adds / and escaping).
_scpd_complete_local() {
  local cur="$1" search="$1" home_re='^~(/|$)'
  [[ "$cur" =~ $home_re ]] && search="$HOME${cur#\~}"
  mapfile -t COMPREPLY < <(compgen -f -- "$search")
  if [[ "$cur" =~ $home_re ]]; then
    COMPREPLY=("${COMPREPLY[@]/#$HOME/\~}")
  fi
  compopt -o filenames 2>/dev/null
}

_scpd_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="" i line esc
  local -a flags=() lines=()
  local upload=false pos=0 w
  COMPREPLY=()
  [[ $COMP_CWORD -ge 1 ]] && prev="${COMP_WORDS[COMP_CWORD-1]}"

  case "$prev" in
    -i) mapfile -t COMPREPLY < <(compgen -f -- "$cur"); return 0 ;;
    -t) mapfile -t COMPREPLY < <(compgen -W "$(bash "$_SCPD_SH" -N 2>/dev/null)" -- "$cur"); return 0 ;;
    -U|-H|-x) return 0 ;;
  esac

  # Reuse any -t/-i/-U/-H the user already typed.
  for ((i = 1; i < COMP_CWORD; i++)); do
    case "${COMP_WORDS[i]}" in
      -t|-i|-U|-H)
        if ((i + 1 < COMP_CWORD)); then
          flags+=("${COMP_WORDS[i]}" "${COMP_WORDS[i+1]}")
          ((i++))
        fi
        ;;
    esac
  done

  # In upload mode, every argument but the last is a local path.
  for ((i = 1; i < COMP_CWORD; i++)); do
    w="${COMP_WORDS[i]}"
    case "$w" in
      -u) upload=true ;;
      -t|-i|-U|-H|-x) ((i++)) ;;
      -*) ;;
      *) ((pos++)) ;;
    esac
  done

  if [[ "$cur" == -* ]]; then
    mapfile -t COMPREPLY < <(compgen -W "-t -i -u -U -H -x -l -c -T -d -h" -- "$cur")
    return 0
  fi

  # Upload: the first argument is always local; later ones are more local sources (relative
  # paths) or the remote destination (starting with ~ or /, or empty).
  if [[ "$upload" == true ]] && { ((pos == 0)) || [[ -n "$cur" && "$cur" != "~"* && "$cur" != /* ]]; }; then
    _scpd_complete_local "$cur"
    return 0
  fi

  # Inside quotes the word starts with the quote character; otherwise undo backslash escapes.
  local q=""
  if [[ "$cur" == \'* || "$cur" == \"* ]]; then
    q="${cur:0:1}"
    cur="${cur:1}"
  else
    cur="${cur//\\/}"
  fi
  mapfile -t lines < <(bash "$_SCPD_SH" "${flags[@]}" -C "$cur" 2>/dev/null)

  for line in "${lines[@]}"; do
    # Upload destinations must be folders.
    [[ "$upload" == true && "$line" != */ ]] && continue
    case "$q" in
      "'")
        esc="'${line//\'/\'\\\'\'}"
        ;;
      '"')
        esc="${line//[\\\"\$\`]/\\&}"
        esc="\"$esc"
        ;;
      *)
        # %q keeps a backslash before a leading ~ so the local shell cannot expand it.
        printf -v esc '%q' "$line"
        ;;
    esac
    if [[ "$line" == */ ]]; then
      compopt -o nospace 2>/dev/null
    elif [[ -n "$q" ]]; then
      esc+="$q"
    fi
    COMPREPLY+=("$esc")
  done
  return 0
}

complete -F _scpd_complete scpd
