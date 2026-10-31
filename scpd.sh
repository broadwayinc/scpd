#!/usr/bin/env bash
# Usage: scpd [-t target] [-i keyfile] [-u user] [-H host] <path>...
# Folders use rsync -a when available on both sides, else scp -r.
# A path ending with '/' is downloaded as a folder, otherwise as a file.
# Connection settings come from named targets in scpd.conf (see README.md).
set -euo pipefail

KEY=""
USER_NAME=""
HOST=""
DEST=""

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${DOWNLOAD_CONF:-$SCRIPT_DIR/scpd.conf}"

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Trim a config value, drop matching surrounding quotes, expand a leading ~ and $HOME.
strip_value() {
  local v
  v="$(trim "$1")"
  if [[ ${#v} -ge 2 ]] &&
     { [[ "${v:0:1}" == '"' && "${v: -1}" == '"' ]] || [[ "${v:0:1}" == "'" && "${v: -1}" == "'" ]]; }; then
    v="${v:1:${#v}-2}"
  fi
  if [[ "$v" == "~" || "$v" == "~/"* ]]; then
    v="$HOME${v#\~}"
  fi
  printf '%s' "${v//\$HOME/$HOME}"
}

# Target names in file order.
conf_targets() {
  [[ -f "$CONFIG" ]] || return 0
  local line re='^\[([^]]+)\]$'
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    if [[ "$line" =~ $re ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
    fi
  done < "$CONFIG"
}

# The "default = name" value written before the first section, if any.
conf_explicit_default() {
  [[ -f "$CONFIG" ]] || return 0
  local line re='^default[[:space:]]*=(.*)$'
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ "$line" == \[* ]] && return 0
    if [[ "$line" =~ $re ]]; then
      strip_value "${BASH_REMATCH[1]}"
      return 0
    fi
  done < "$CONFIG"
}

# The chosen default target if it exists, otherwise the first target.
conf_default() {
  local d first
  d="$(conf_explicit_default)"
  if [[ -n "$d" ]] && conf_targets | grep -xF -- "$d" >/dev/null; then
    printf '%s' "$d"
    return 0
  fi
  first="$(conf_targets | sed -n 1p)"
  printf '%s' "$first"
}

# Load KEY, USER_NAME, HOST and DEST from the named target; fails if it does not exist.
conf_load() {
  local want="$1" line sec="" found=1 k v
  local header_re='^\[([^]]+)\]$' kv_re='^([A-Za-z_]+)[[:space:]]*=(.*)$'
  [[ -f "$CONFIG" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" =~ $header_re ]]; then
      sec="${BASH_REMATCH[1]}"
      [[ "$sec" == "$want" ]] && found=0
      continue
    fi
    [[ "$sec" == "$want" ]] || continue
    if [[ "$line" =~ $kv_re ]]; then
      k="${BASH_REMATCH[1]}"
      v="$(strip_value "${BASH_REMATCH[2]}")"
      case "$k" in
        key) KEY="$v" ;;
        user) USER_NAME="$v" ;;
        host) HOST="$v" ;;
        dest) DEST="$v" ;;
      esac
    fi
  done < "$CONFIG"
  return "$found"
}

# Add or replace a target, rewriting the config file.
save_target() {
  local name="$1" key="$2" user="$3" host="$4" dest="$5" make_default="$6" dflt tmp
  dflt="$(conf_explicit_default)"
  if [[ "$make_default" == true ]]; then
    dflt="$name"
  fi
  mkdir -p -- "$(dirname -- "$CONFIG")"
  tmp="$(mktemp "$CONFIG.XXXXXX")"
  {
    if [[ -n "$dflt" ]]; then
      printf 'default = %s\n\n' "$dflt"
    fi
    if [[ -f "$CONFIG" ]]; then
      awk -v name="$name" '
        /^[[:space:]]*\[.*\][[:space:]]*$/ {
          line = $0
          gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", line)
          insec = 1
          skip = (line == name)
        }
        !insec && /^[[:space:]]*default[[:space:]]*=/ { next }
        !skip { print }
      ' "$CONFIG"
    fi
    printf '\n[%s]\nkey = %s\nuser = %s\nhost = %s\ndest = %s\n' "$name" "$key" "$user" "$host" "$dest"
  } | cat -s | sed '1{/^$/d}' > "$tmp"
  mv -- "$tmp" "$CONFIG"
}

# ask VAR "Label" ["suggested value"]: prompt until a non-empty value is given.
ask() {
  local __var="$1" label="$2" def="${3:-}" ans
  while true; do
    if [[ -n "$def" ]]; then
      read -r -p "$label [$def]: " ans
      ans="${ans:-$def}"
    else
      read -r -p "$label: " ans
    fi
    ans="$(trim "$ans")"
    [[ -n "$ans" ]] && break
    echo "A value is required." >&2
  done
  printf -v "$__var" '%s' "$ans"
}

# Interactively add or edit a target (existing values are offered as defaults).
configure_target() {
  local name="${1:-}" key user host dest suggested="" answer make_default=false first_run=false
  if [[ ! -t 0 ]]; then
    echo "Configuring a target needs an interactive terminal." >&2
    exit 1
  fi
  if [[ -z "$(conf_targets)" ]]; then
    first_run=true
    suggested="default"
  fi
  if [[ -z "$name" ]]; then
    ask name "Target name" "$suggested"
  fi
  if [[ ! "$name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "Invalid target name '$name': use letters, digits, '.', '_' and '-'." >&2
    exit 1
  fi

  KEY="" USER_NAME="" HOST="" DEST=""
  if conf_load "$name"; then
    echo "Editing existing target '$name'."
  fi
  ask key "SSH key file" "$KEY"
  ask user "Remote username" "$USER_NAME"
  ask host "Remote host" "$HOST"
  ask dest "Download folder" "${DEST:-./scp}"

  if [[ "$first_run" != true && "$(conf_default)" != "$name" ]]; then
    read -r -p "Make '$name' the default target? [y/N] " answer
    [[ "$answer" == [yY]* ]] && make_default=true
  fi
  save_target "$name" "$key" "$user" "$host" "$dest" "$make_default"
  echo "Saved target '$name' in $CONFIG"
}

list_targets() {
  local d name
  if [[ -z "$(conf_targets)" ]]; then
    echo "No targets configured. Run: scpd -c"
    return 0
  fi
  d="$(conf_default)"
  while IFS= read -r name; do
    (
      KEY="" USER_NAME="" HOST="" DEST=""
      conf_load "$name" || true
      printf '%s%s  %s@%s  key=%s  dest=%s\n' "$name" "$([[ "$name" == "$d" ]] && echo ' (default)')" \
        "$USER_NAME" "$HOST" "$KEY" "$DEST"
    )
  done < <(conf_targets)
}

# Pick the target, set up the first one if none exists, and load its values.
resolve_target() {
  local name="$TARGET"
  if [[ -z "$(conf_targets)" ]]; then
    [[ "$MODE" == "complete" ]] && exit 0
    if [[ -t 0 ]]; then
      echo "No targets configured yet. Let's set one up."
      configure_target ""
    else
      echo "No targets configured. Run: scpd -c" >&2
      exit 1
    fi
  fi
  [[ -n "$name" ]] || name="$(conf_default)"
  if ! conf_load "$name"; then
    [[ "$MODE" == "complete" ]] && exit 0
    echo "Unknown target: $name" >&2
    echo "Available targets:" >&2
    conf_targets | sed 's/^/  /' >&2
    exit 1
  fi
}

open_docs() {
  local docs="$SCRIPT_DIR/README.md"
  if [[ ! -f "$docs" ]]; then
    echo "Documentation not found: $docs" >&2
    exit 1
  fi
  cat "$docs"
}

# Quote a remote path for the remote shell, keeping a leading ~ or ~user expandable.
remote_quote() {
  local p="$1" head="" rest="$1" sq="'\\''" q="'"
  if [[ "$p" =~ ^(~[A-Za-z0-9_.-]*)(/.*)?$ ]]; then
    head="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]#/}"
    [[ -n "$head" ]] && head="$head/"
    [[ -n "${BASH_REMATCH[2]}" ]] || { printf '%s' "${head%/}"; return; }
    [[ -n "$rest" ]] || { printf '%s' "$head"; return; }
  fi
  rest="${rest//"$q"/$sq}"
  printf '%s%s' "$head" "'$rest'"
}

# Run a command on the remote host; SSH_EXTRA holds mode-specific ssh options.
run_ssh() {
  ssh -i "$KEY" "${SSH_EXTRA[@]}" "$USER_NAME@$HOST" "$1"
}

# Bash expands an unquoted ~ to the LOCAL home before scpd runs. If a path under the
# local home does not exist on the remote but the same path under the remote home
# does, use the remote-home form.
resolve_remote_path() {
  local p="$1" alt
  if [[ "$p" == "$HOME" || "$p" == "$HOME/"* ]]; then
    if ! run_ssh "test -e $(remote_quote "$p")" 2>/dev/null; then
      alt="~${p#"$HOME"}"
      if run_ssh "test -e $(remote_quote "$alt")" 2>/dev/null; then
        p="$alt"
      fi
    fi
  fi
  printf '%s' "$p"
}

list_paths() {
  local target
  for target in "$@"; do
    case "$target" in
      "~"*|/*) ;;
      *) echo "Path must start with ~ or /: $target" >&2; exit 1 ;;
    esac
    target="$(resolve_remote_path "$target")"
    run_ssh "ls -lAhp -- $(remote_quote "$target")"
  done
}

# Print remote completion candidates for a partial path (used by scpd-completion.bash).
complete_paths() {
  local cur="$1" dir base entry
  if [[ -z "$cur" ]]; then
    printf '/\n~/\n'
    return 0
  fi
  if [[ "$cur" == "~" ]]; then
    printf '~/\n'
    return 0
  fi
  [[ "$cur" == "~"* || "$cur" == /* ]] || return 0
  [[ "$cur" == */* ]] || return 0

  dir="${cur%/*}/"
  base="${cur##*/}"
  SSH_EXTRA=(-o BatchMode=yes -o ConnectTimeout=5
    -o ControlMaster=auto -o ControlPersist=60
    -o "ControlPath=${XDG_RUNTIME_DIR:-$HOME/.ssh}/scpd-%C")
  run_ssh "ls -1ApL -- $(remote_quote "$dir") 2>/dev/null" 2>/dev/null |
    while IFS= read -r entry; do
      [[ -z "$base" && "$entry" == .* ]] && continue
      [[ "$entry" == "$base"* ]] && printf '%s%s\n' "$dir" "$entry"
    done || true
}

usage() {
  local status="${1:-1}" out=1
  [[ "$status" -eq 0 ]] || out=2
  cat >&"$out" <<'EOF'
Usage: scpd [-t target] [-i keyfile] [-u user] [-H host] [-x pattern] <path>...
       scpd -l [-t target] <path>...
       scpd -c [name] | -T | -d | -h

  -t  use this target from scpd.conf (default: the configured default,
      otherwise the first target)
  -i  override the target's key file
  -u  override the target's remote username
  -H  override the target's remote host
  -x  exclude folder contents matching PATTERN (repeatable, e.g. -x node_modules);
      folder downloads only, needs rsync on both machines
  -l  list remote path(s) instead of downloading
  -c  add or edit a target (asks for its values)
  -T  list configured targets
  -d  print the README documentation
  -h  show this help

Paths must start with ~ or /; a trailing '/' downloads a folder.
EOF
  exit "$status"
}

MODE="download"
TARGET=""
OPT_KEY="" OPT_USER="" OPT_HOST=""
SSH_EXTRA=()
EXCLUDES=()

# -C (complete) and -N (print target names) are internal flags used by the tab completion script.
while getopts "t:i:u:H:x:hdlcTCN" opt; do
  case "$opt" in
    t) TARGET="$OPTARG" ;;
    i) OPT_KEY="$OPTARG" ;;
    u) OPT_USER="$OPTARG" ;;
    H) OPT_HOST="$OPTARG" ;;
    x) EXCLUDES+=("$OPTARG") ;;
    d) open_docs; exit 0 ;;
    l) MODE="list" ;;
    c) MODE="configure" ;;
    T) MODE="targets" ;;
    C) MODE="complete" ;;
    N) MODE="names" ;;
    h) usage 0 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

case "$MODE" in
  configure) configure_target "${TARGET:-${1:-}}"; exit 0 ;;
  targets) list_targets; exit 0 ;;
  names) conf_targets; exit 0 ;;
esac

[ $# -ge 1 ] || usage

resolve_target
[[ -z "$OPT_KEY" ]] || KEY="$OPT_KEY"
[[ -z "$OPT_USER" ]] || USER_NAME="$OPT_USER"
[[ -z "$OPT_HOST" ]] || HOST="$OPT_HOST"

for field in KEY USER_NAME HOST; do
  if [[ -z "${!field}" ]]; then
    echo "Missing '$field' for the selected target. Run: scpd -c" >&2
    exit 1
  fi
done
[ -f "$KEY" ] || { echo "Key file not found: $KEY" >&2; exit 1; }

case "$MODE" in
  list) list_paths "$@"; exit 0 ;;
  complete) complete_paths "$1"; exit 0 ;;
esac

if [[ -z "$DEST" ]]; then
  echo "Missing 'dest' for the selected target. Run: scpd -c" >&2
  exit 1
fi
mkdir -p "$DEST"

RSYNC_EXCLUDES=()
for pat in ${EXCLUDES[@]+"${EXCLUDES[@]}"}; do
  RSYNC_EXCLUDES+=(--exclude "$pat")
done

# True when rsync exists locally and on the remote host (checked once).
have_rsync() {
  if [[ -z "${RSYNC_OK:-}" ]]; then
    RSYNC_OK=no
    if command -v rsync >/dev/null 2>&1 && run_ssh "command -v rsync" >/dev/null 2>&1; then
      RSYNC_OK=yes
    fi
  fi
  [[ "$RSYNC_OK" == yes ]]
}

for target in "$@"; do
  case "$target" in
    "~"*|/*) ;;
    *) echo "Path must start with ~ or /: $target" >&2; exit 1 ;;
  esac
  target="$(resolve_remote_path "$target")"

  if [[ "$target" == */ ]]; then
    remote="${target%/}"
    if have_rsync; then
      # -a keeps symlinks, permissions and timestamps (scp -r would follow symlinks).
      rsync -a "${RSYNC_EXCLUDES[@]}" -e "ssh -i $(printf '%q' "$KEY")" "$USER_NAME@$HOST:$remote" "$DEST/"
    elif [[ ${#EXCLUDES[@]} -gt 0 ]]; then
      echo "-x needs rsync on both this machine and the remote host." >&2
      exit 1
    else
      echo "rsync not available on both sides; using scp -r (symlinks are copied as regular files)." >&2
      scp -i "$KEY" -r "$USER_NAME@$HOST:$remote" "$DEST/"
    fi
  else
    scp -i "$KEY" "$USER_NAME@$HOST:$target" "$DEST/"
  fi
done
