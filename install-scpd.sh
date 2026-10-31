#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/scpd.sh"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
COMMAND_PATH="$BIN_DIR/scpd"
COMPLETION_PATH="$SCRIPT_DIR/scpd-completion.bash"
BASHRC="${BASHRC:-$HOME/.bashrc}"
BEGIN_MARK="# >>> scpd completion >>>"
END_MARK="# <<< scpd completion <<<"
COMPLETION="ask"

case "${1:-}" in
  --completion) COMPLETION="yes" ;;
  --no-completion) COMPLETION="no" ;;
  "") ;;
  *) echo "Usage: $0 [--completion | --no-completion]" >&2; exit 1 ;;
esac

strip_completion_block() {
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b { skip = 1 }
    !skip { print }
    $0 == e { skip = 0 }
  ' "$BASHRC"
}

setup_completion() {
  [[ -f "$COMPLETION_PATH" ]] || return 0
  local has_block=false cleaned
  [[ -f "$BASHRC" ]] && grep -qxF "$BEGIN_MARK" "$BASHRC" && has_block=true

  if [[ "$has_block" != true ]]; then
    if [[ "$COMPLETION" == "ask" ]]; then
      if [[ -t 0 ]]; then
        read -r -p "Enable tab completion for scpd by adding a block to $BASHRC? [y/N] " answer
        [[ "$answer" == [yY]* ]] && COMPLETION="yes" || COMPLETION="no"
      else
        COMPLETION="no"
      fi
    fi
    if [[ "$COMPLETION" != "yes" ]]; then
      echo "Tab completion not enabled. To enable it, add this to $BASHRC:"
      printf '  source %q\n' "$COMPLETION_PATH"
      return 0
    fi
  fi

  touch -- "$BASHRC"
  cleaned="$(strip_completion_block; printf x)"
  cleaned="${cleaned%x}"
  {
    printf '%s' "$cleaned"
    printf '%s\n' "$BEGIN_MARK"
    printf '[ -f %q ] && source %q\n' "$COMPLETION_PATH" "$COMPLETION_PATH"
    printf '%s\n' "$END_MARK"
  } > "$BASHRC"
  echo "Tab completion enabled in $BASHRC (open a new terminal to use it)."
}

if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "Script not found: $SCRIPT_PATH" >&2
  exit 1
fi

mkdir -p -- "$BIN_DIR"

TEMP_FILE="$(mktemp "$BIN_DIR/.scpd.XXXXXX")"
trap 'rm -f -- "$TEMP_FILE"' EXIT

printf '#!/usr/bin/env bash\n# Managed by install-scpd.sh\nexec bash %q "$@"\n' "$SCRIPT_PATH" > "$TEMP_FILE"
chmod 755 "$TEMP_FILE"

if [[ -e "$COMMAND_PATH" || -L "$COMMAND_PATH" ]]; then
  if cmp -s -- "$TEMP_FILE" "$COMMAND_PATH"; then
    echo "scpd is already installed at $COMMAND_PATH"
    setup_completion
    exit 0
  fi

  replaceable=false
  if [[ -f "$COMMAND_PATH" && ! -L "$COMMAND_PATH" ]]; then
    mapfile -t existing_lines < "$COMMAND_PATH"
    if [[ ${#existing_lines[@]} -eq 3 &&
          "${existing_lines[0]}" == '#!/usr/bin/env bash' &&
          "${existing_lines[1]}" == '# Managed by install-scpd.sh' &&
          "${existing_lines[2]}" == exec\ bash\ *\ \"\$@\" ]]; then
      replaceable=true
    elif [[ ${#existing_lines[@]} -eq 2 &&
            "${existing_lines[0]}" == '#!/usr/bin/env bash' &&
            "${existing_lines[1]}" == exec\ bash\ *\ \"\$@\" ]]; then
      replaceable=true
    fi
  fi

  if [[ "$replaceable" != true ]]; then
    echo "Refusing to overwrite a command not recognized as an scpd launcher: $COMMAND_PATH" >&2
    exit 1
  fi

  echo "Replacing the existing scpd launcher at $COMMAND_PATH"
fi

mv -- "$TEMP_FILE" "$COMMAND_PATH"
echo "Installed scpd at $COMMAND_PATH"
setup_completion

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo "$BIN_DIR is not currently in PATH."
    echo "Add this to your shell configuration, then open a new terminal:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac
