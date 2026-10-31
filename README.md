# scpd

`scpd` downloads files and folders from a remote host using `scp`.

## Install

From the directory containing `scpd.sh`, run:

```bash
./install-scpd.sh
```

This installs the `scpd` command in `~/.local/bin` (or `$XDG_BIN_HOME` if set). If that directory is not in your `PATH`, add it as instructed by the installer and open a new terminal.

## Configure

Connection settings are stored as named **targets** in `scpd.conf`, in the same directory as `scpd.sh`. There are no built-in defaults: the first time you run `scpd` with no targets, it asks for the values and saves them.

Add a target, or edit an existing one, at any time:

```bash
scpd -c            # asks for a name, key file, username, host and download folder
scpd -c staging    # same, for the target named "staging"
scpd -T            # list targets
```

When you add a target after the first, `scpd` asks whether to make it the default. If no default is set, the first target in the file is the default. You can also edit `scpd.conf` by hand:

```ini
default = work

[work]
key = ~/.ssh/work.pem
user = ubuntu
host = work.example.com
dest = ./scp

[staging]
key = ~/.ssh/staging.pem
user = deploy
host = staging.example.com
dest = ./staging-files
```

`default` must come before the first section. Values may start with `~` or `$HOME`. A target needs `key`, `user`, `host` and `dest`.

To use a config file at another location, set `DOWNLOAD_CONF`:

```bash
DOWNLOAD_CONF="$HOME/.config/scpd/scpd.conf" scpd /remote/path/file
```

## Use

Show command help:

```bash
scpd -h
```

Print this documentation in the terminal:

```bash
scpd -d
```

List a remote file or folder before downloading:

```bash
scpd -l '~/projects/'
```

Quoting `~` is optional. If you type it unquoted, your local shell expands it to your local home (for example `/home/me/projects/`) before `scpd` runs. `scpd` handles that automatically: when a path under your local home doesn't exist on the remote but the same path under the remote home does, it uses the remote one. A path that exists as typed is never changed. Tab completion works with or without quotes.

Download a remote file:

```bash
scpd /remote/path/file.txt
```

Download a remote folder (include a trailing slash):

```bash
scpd /remote/path/folder/
```

You can provide multiple remote paths in one command. Paths must begin with `/` or `~`. A trailing `/` makes that path download recursively as a folder.

Use a different target with `-t` (works with `-l` too):

```bash
scpd -t staging /remote/path/file.txt
```

Override the key, username, or host of the chosen target for one invocation:

```bash
scpd -i "$HOME/.ssh/other.pem" -u ubuntu -H example.com /remote/path/file.txt
```

Folders (paths ending in `/`) are downloaded with `rsync -a` when rsync is installed on both machines, which preserves symlinks, permissions and timestamps. Otherwise `scpd` falls back to `scp -r`, which copies symlinks as regular files (this breaks `node_modules/.bin`). Use `-x PATTERN` (repeatable, needs rsync) to skip files, e.g. `scpd -x node_modules /remote/project/`.

Downloads go to the target's `dest`, and a relative `dest` or key path such as `./scp` is resolved from the directory where you run `scpd`.

## Tab completion

`install-scpd.sh` offers to add a small block to `~/.bashrc` that loads `scpd-completion.bash`. Use `./install-scpd.sh --completion` to accept without a prompt or `--no-completion` to skip it. Reinstalling updates the block, and `uninstall-scpd.sh` removes it.

After opening a new terminal, press Tab while typing a remote path and `scpd` connects over SSH to complete it. Tab behaves like normal path completion, and only the `scpd` command is affected. Directories end with `/`, and `-t`, `-i`, `-u` and `-H` options you already typed are used for the lookup. `-t` also completes target names. Completion uses key authentication only (no password prompts), so the first connection to a host must already be trusted by SSH. Connections are reused for 60 seconds, so repeated Tab presses are faster.

## Move or uninstall

If you move `scpd.sh`, keep `scpd.conf` beside it and run `install-scpd.sh` from its new directory to update the global launcher.

Remove the global command with:

```bash
./uninstall-scpd.sh
```
