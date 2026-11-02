#!/usr/bin/env bash
# Installs the scpd command in ~/.local/bin (or $XDG_BIN_HOME).
#
#   From a checkout:  ./install-scpd.sh [--completion | --no-completion]
#   From the web:     curl -fsSL https://raw.githubusercontent.com/broadwayinc/scpd/main/install-scpd.sh | bash
#                     (pass an option with: ... | bash -s -- --completion)
#
# Run next to scpd.sh, it installs that copy. Run any other way (piped into bash, or a
# lone downloaded file), it downloads the files from SCPD_BASE_URL into SCPD_HOME
# (default ~/.local/share/scpd) and installs those. Re-run it to update; scpd.conf is kept.
# Nothing runs until the last line, so a partly downloaded script does nothing.
set -euo pipefail

# Where a web install downloads from. Point this (or SCPD_BASE_URL) at your own server
# if you host the files yourself.
DEFAULT_BASE_URL="https://raw.githubusercontent.com/broadwayinc/scpd/main"
WEB_FILES=(scpd.sh scpd-completion.bash README.md uninstall-scpd.sh)

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
COMMAND_PATH="$BIN_DIR/scpd"
BASHRC="${BASHRC:-$HOME/.bashrc}"
BEGIN_MARK="# >>> scpd completion >>>"
END_MARK="# <<< scpd completion <<<"
COMPLETION="ask"
CLEANUP=()

cleanup() {
  [[ ${#CLEANUP[@]} -eq 0 ]] || rm -rf -- "${CLEANUP[@]}"
}

# Ask a y/N question on the terminal. Reads /dev/tty when stdin is not one, which is the
# case with curl | bash (stdin is this script). Fails when there is no terminal at all.
confirm() {
  local answer
  if [[ -t 0 ]]; then
    read -r -p "$1 [y/N] " answer
  elif { : </dev/tty; } 2>/dev/null; then
    read -r -p "$1 [y/N] " answer </dev/tty
  else
    return 1
  fi
  [[ "$answer" == [yY]* ]]
}

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    echo "Downloading needs curl or wget." >&2
    return 1
  fi
}

# Download the program files into $1, replacing older copies. scpd.conf is never touched.
download_files() {
  local dir="$1" base="${SCPD_BASE_URL:-$DEFAULT_BASE_URL}" tmp f first
  base="${base%/}"
  mkdir -p -- "$dir"
  tmp="$(mktemp -d "$dir/.download.XXXXXX")"
  CLEANUP+=("$tmp")
  echo "Downloading scpd from $base"
  for f in "${WEB_FILES[@]}"; do
    if ! fetch "$base/$f" "$tmp/$f"; then
      echo "Download failed: $base/$f" >&2
      exit 1
    fi
    # A web server may answer a missing file with an HTML page; never install that as a script.
    if [[ "$f" == *.sh || "$f" == *.bash ]]; then
      first=""
      IFS= read -r first < "$tmp/$f" || true
      if [[ "$first" != \#* ]] || ! bash -n "$tmp/$f" 2>/dev/null; then
        echo "Not a bash script: $base/$f" >&2
        exit 1
      fi
    fi
  done
  chmod 755 "$tmp"/*.sh
  for f in "${WEB_FILES[@]}"; do
    mv -f -- "$tmp/$f" "$dir/$f"
  done
}

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
      if confirm "Enable tab completion for scpd by adding a block to $BASHRC?"; then
        COMPLETION="yes"
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

# When the launcher moves to another copy of scpd.sh, bring the old copy's targets along.
carry_over_config() {
  local old_script="$1" old_conf
  old_conf="$(dirname -- "$old_script")/scpd.conf"
  if [[ "$old_script" != "$SCRIPT_PATH" && -f "$old_conf" && ! -e "$SCRIPT_DIR/scpd.conf" ]]; then
    cp -p -- "$old_conf" "$SCRIPT_DIR/scpd.conf"
    echo "Copied your targets from $old_conf"
  fi
}

finish() {
  setup_completion
  if [[ "$WEB_INSTALL" == true ]]; then
    echo "Files are in $SCRIPT_DIR. Run the same command again to update (your targets are kept)."
    printf 'To uninstall: bash %q\n' "$SCRIPT_DIR/uninstall-scpd.sh"
  fi
}

main() {
  case "${1:-}" in
    --completion) COMPLETION="yes" ;;
    --no-completion) COMPLETION="no" ;;
    "") ;;
    *) echo "Usage: install-scpd.sh [--completion | --no-completion]" >&2; exit 1 ;;
  esac
  trap cleanup EXIT

  # BASH_SOURCE is empty when the script is piped into bash.
  local src="${BASH_SOURCE[0]:-}"
  SCRIPT_DIR=""
  if [[ -n "$src" && -f "$src" ]]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "$src")" && pwd)"
    [[ -f "$SCRIPT_DIR/scpd.sh" ]] || SCRIPT_DIR=""
  fi
  WEB_INSTALL=false
  if [[ -z "$SCRIPT_DIR" ]]; then
    WEB_INSTALL=true
    SCRIPT_DIR="${SCPD_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/scpd}"
    download_files "$SCRIPT_DIR"
    SCRIPT_DIR="$(cd -- "$SCRIPT_DIR" && pwd)"
  fi
  SCRIPT_PATH="$SCRIPT_DIR/scpd.sh"
  COMPLETION_PATH="$SCRIPT_DIR/scpd-completion.bash"

  if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "Script not found: $SCRIPT_PATH" >&2
    exit 1
  fi

  mkdir -p -- "$BIN_DIR"

  local temp_file
  temp_file="$(mktemp "$BIN_DIR/.scpd.XXXXXX")"
  CLEANUP+=("$temp_file")

  printf '#!/usr/bin/env bash\n# Managed by install-scpd.sh\nexec bash %q "$@"\n' "$SCRIPT_PATH" > "$temp_file"
  chmod 755 "$temp_file"

  if [[ -e "$COMMAND_PATH" || -L "$COMMAND_PATH" ]]; then
    if cmp -s -- "$temp_file" "$COMMAND_PATH"; then
      echo "scpd is already installed at $COMMAND_PATH"
      finish
      exit 0
    fi

    local replaceable=false old_script="" existing_lines=()
    if [[ -f "$COMMAND_PATH" && ! -L "$COMMAND_PATH" ]]; then
      mapfile -t existing_lines < "$COMMAND_PATH"
      if [[ ${#existing_lines[@]} -eq 3 &&
            "${existing_lines[0]}" == '#!/usr/bin/env bash' &&
            "${existing_lines[1]}" == '# Managed by install-scpd.sh' &&
            "${existing_lines[2]}" == exec\ bash\ *\ \"\$@\" ]]; then
        replaceable=true
        old_script="${existing_lines[2]#exec bash }"
      elif [[ ${#existing_lines[@]} -eq 2 &&
              "${existing_lines[0]}" == '#!/usr/bin/env bash' &&
              "${existing_lines[1]}" == exec\ bash\ *\ \"\$@\" ]]; then
        replaceable=true
        old_script="${existing_lines[1]#exec bash }"
      fi
    fi

    if [[ "$replaceable" != true ]]; then
      echo "Refusing to overwrite a command not recognized as an scpd launcher: $COMMAND_PATH" >&2
      exit 1
    fi

    echo "Replacing the existing scpd launcher at $COMMAND_PATH"
    # The launcher holds the path as printed by %q; a path that needed quoting is skipped.
    carry_over_config "${old_script% \"\$@\"}"
  fi

  mv -- "$temp_file" "$COMMAND_PATH"
  echo "Installed scpd at $COMMAND_PATH"
  finish

  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      echo "$BIN_DIR is not currently in PATH."
      echo "Add this to your shell configuration, then open a new terminal:"
      echo "  export PATH=\"$BIN_DIR:\$PATH\""
      ;;
  esac
}

main "$@"
