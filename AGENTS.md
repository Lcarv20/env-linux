# AGENTS.md — instructions for AI coding agents

This file is binding for **all** AI agents working in this repository.
Read it before touching anything.

## What this repo is

`env-linux` is the **desktop environment track**: the Niri + Dux Shell (dms)
desktop, its compositor configs, services, and the modular installer that
turns a naked Fedora (and later Debian-family) install into that desktop.
It is intentionally **separate** from `~/dots-linux`, which holds only
portable dev-tool dotfiles (nvim, zsh, ghostty, …).

```
install              Executable TUI entry point (pure bash, no deps; prompts on /dev/tty)
manifest/            Package lists: copr, dnf-core, dnf-extras, flatpak-extras,
                     mise-core, mise-extras — single source of truth.
stages/              Numbered installer stages (00-repos → 90-hardware);
                     stages/lib.sh is the shared library (UI, logging, run_cmd).
system/              Root-owned files shipped by the repo (greetd config,
                     greeter niri configs, udev rules, dfiles-shell patcher).
hosts/               Per-host hardware quirks (imac18-3, vm) applied by
                     stages/90-hardware.sh → hosts/<profile>/apply.sh.
<stow packages>/     niri, dms, mango, portals, environment, systemd-user,
                     desktop-tools, scripts
```

Provenance: environment packages + installer imported from
`dots-linux` (see the import commit for the exact source SHA).

## Golden rules

1. **Never overwrite symlinks blindly.** Files in `~/.config` (and `~`)
   are symlinks into **both** `~/dots-linux` (dev tools) and **this repo**
   (environment). Before editing anything under `$HOME`:
   - `ls -la` the path. If it is a symlink, **edit the repo file it points
     to**, never the symlink in place. `readlink -f` is your friend.
   - Real file vs stow-package file = conflict → resolve in the repo or via
     the installer backup flow (`~/.dots-backup-<timestamp>/`).

2. **Do not commit secrets or runtime state.** Never `git add`: `setup.log*`,
   caches, `*.log`, tokens, cookies, machine IDs. Template secrets.

3. **Log fundamental OS changes in `~/Agentic-linux.md`** with date,
   symptom, root cause, exact fix, and scope marker: **portable** vs
   **iMac18,3-only**.

4. **Manifests are the source of truth.** Packages go into
   `manifest/*.txt` (one per line, `#` comments) — never hardcode package
   lists inside stage scripts.

5. **All mutating commands go through `run_cmd`.** In `stages/*.sh` use the
   `run_cmd`/`install_file`/`copy_tree` helpers from `stages/lib.sh`; they
   log to `setup.log` and honor `DRY_RUN=true`. Test stage changes with:
   `DRY_RUN=true bash stages/<stage>.sh`

6. **Host quirks belong in `hosts/`.** Machine-specific things (kernel args,
   DKMS modules, fixed output modes) live in `hosts/<profile>/` and are
   selected via `HOST_PROFILE` / `--host=`. Keep everything else portable.

7. **Idempotency is required.** Every stage must be safe to re-run. Check
   before changing; never assume a fresh machine.

## Useful commands

```bash
./install --dry-run                                  # full rehearsal
DRY_RUN=true bash stages/40-dotfiles.sh              # rehearse one stage
system/dfiles-patch/apply-dfiles-patch.sh --refresh  # after dux-files RPM upgrade
```
