# Bash tab completion for scpd: completes remote paths over ssh.
# Loaded from ~/.bashrc by install-scpd.sh; only affects the `scpd` command.

_SCPD_SH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/scpd.sh"

_scpd_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="" i line esc
  local -a flags=() lines=()
  COMPREPLY=()
  [[ $COMP_CWORD -ge 1 ]] && prev="${COMP_WORDS[COMP_CWORD-1]}"

  case "$prev" in
    -i) mapfile -t COMPREPLY < <(compgen -f -- "$cur"); return 0 ;;
    -t) mapfile -t COMPREPLY < <(compgen -W "$(bash "$_SCPD_SH" -N 2>/dev/null)" -- "$cur"); return 0 ;;
    -u|-H|-x) return 0 ;;
  esac

  # Reuse any -t/-i/-u/-H the user already typed.
  for ((i = 1; i < COMP_CWORD; i++)); do
    case "${COMP_WORDS[i]}" in
      -t|-i|-u|-H)
        if ((i + 1 < COMP_CWORD)); then
          flags+=("${COMP_WORDS[i]}" "${COMP_WORDS[i+1]}")
          ((i++))
        fi
        ;;
    esac
  done

  if [[ "$cur" == -* ]]; then
    mapfile -t COMPREPLY < <(compgen -W "-t -i -u -H -x -l -c -T -d -h" -- "$cur")
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
