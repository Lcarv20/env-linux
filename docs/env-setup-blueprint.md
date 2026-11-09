# Env Setup Blueprint — reproducible Fedora + Niri + Dux Shell machines

> Status: **PLAN — approved, ready to implement** — written 2026-11-09 after a
> full audit of `~/dots-linux`, `~/env-linux`, live plugins, assets, and
> `~/Agentic-linux.md`. All four decisions (§6) confirmed by the user on
> 2026-11-09. Nothing has been implemented yet.

## 1. Goal

On any fresh Fedora machine, get to "this machine, minus hardware quirks" with
two commands:

```bash
~/dots-linux/setup     # 1. dev track: zsh, nvim, ghostty, mise tools, …
~/env-linux/install    # 2. env track: niri + dms + greetd + plugins + assets + own software
```

Explicitly out of scope (per-host, never auto-applied): 5K panel mode, kernel
args, DKMS audio, Bluetooth resume rescue. These already live in
`hosts/imac18-3/` and only apply when the installer detects that machine.

## 2. Principles (your scribbles, formalized)

1. **Two tracks, strict order.** Dev dots (`dots-linux`) first, desktop env
   (`env-linux`) second. Already the architecture on disk — keep it.
2. **Releases are assets.** Wallpapers/fonts/icons ship as GitHub *release*
   tarballs, never in the git tree. The installer downloads + verifies + moves.
3. **Everything you authored is gitted.** Plugins and tools get real repos.
4. **The installer narrates and asks.** Step-by-step, explains each action
   ("Creating wallpapers folder `~/Pictures/Walpapers` …"), y/N per step.
5. **Clones live in `~/Developer/Software`.** One convention, no exceptions.
6. **Manifests are the single source of truth** for packages (already true).
7. **Idempotent everywhere.** Any stage re-runs safely on any machine.

## 3. Inventory — what actually exists today

### 3.1 `dots-linux` (dev track) — stable

- `./setup`: distro-auto (dnf/apt), mise CLI tools, stow `--no-folding`,
  conflict backup, dry-run, idempotent. Validated in podman containers
  (fedora 44/45, debian 12/13).
- Packages: fastfetch, ghostty, git, lazygit, lsd, nvim, starship, zed, zsh.
- **Gap: Google Chrome is NOT here yet** (your note). It currently lives in
  `env-linux/manifest/dnf-extras.txt` + `stages/60-extras.sh`.

### 3.2 `env-linux` (env track) — the "agent mess" audit result

**Verdict: much better than you feared.** The skeleton is sound (manifests,
numbered stages, host profiles, dry-run, idempotency rules in AGENTS.md).
Real cruft found, all small and listed in §5.

- `install` — gum TUI (pure-bash fallback), flags: `--dry-run --yes
  --profile=minimal|full|custom --host=auto --with-extras --with-mango`.
  Asks only 2 questions today (profile + confirm) — **not** the step-by-step
  y/N experience you want (decided: §6.2).
- Stages:

| Stage | Does | Status |
|---|---|---|
| 00-repos | RPM Fusion, Terra, COPRs (`manifest/copr.txt`) | OK |
| 10-desktop-base | ~74 dnf pkgs + mise core + antidote + zsh | OK |
| 20-niri-dms | Verifies niri/dms/dms-greeter/dfiles/matugen present | OK |
| 30-assets | Downloads assets tarball from **`Lcarv20/dots-linux` releases** (old repo!), SHA-256 verify, installs wallpapers/fonts/icons/dfiles-shell/bin | Works; wrong repo URL |
| 40-dotfiles | Stows 8 env packages, backs up conflicts, seeds DMS session/colors | Has dead refs to 9 dev packages (moved to dots-linux) |
| 50-services | greetd + dms-greeter, disables GDM/SDDM, systemd user units, Chrome policy dir | OK — this is most of your "hooks" |
| 60-extras | Chrome repo, dnf/mise/flatpak extras, Keychron udev, optional mango | Chrome should move to dots-linux |
| 90-hardware | Dispatcher → `hosts/<profile>/apply.sh` | OK |

- `manifest/`: copr (2), dnf-core (~74), dnf-extras (6, incl. `google-chrome-stable`),
  flatpak-extras (6), mise-core (11), mise-extras (9). Clean.
- `hosts/`: `imac18-3` (kernel args incl. 5K video mode, bt-resume-rescue v2,
  DKMS `snd_hda_macbookpro`, outputs.kdl) and `vm` (guest agents, empty outputs
  stub). Exactly the "quirks don't transfer" you wanted.
- `system/`: greetd config + greeter niri kdl (generic vs iMac), Keychron udev,
  dfiles-shell patcher (bigger picker + "Dux Chooser · " title prefix), DMS
  session.json/dms-colors.json seeds.
- **7 files uncommitted in the working tree** (live DMS writes through stow
  symlinks: settings.json, plugin_settings.json, firefox.css, niri/dms/*.kdl).
  Must be triaged + committed before any restructure.

### 3.3 Assets (release tarball)

- Current: `dots-linux-assets-v1.tar.zst` on **Lcarv20/dots-linux** releases +
  `assets-v1.sha256` sidecar in env-linux. Contains: `wallpapers/`, `icons/`,
  `fonts/`, `dfiles-shell/`, `bin/` (niri-zoomd, niri-zoomctl).
- Wallpapers: 56 files, **661 MB** (many H.264 video wallpapers) at
  `~/Pictures/Walpapers` (typo is load-bearing: session.json points there).
- Fonts: 8 user TTFs (Bubblegum Sans, Caveat Brush, Gorditas ×2, JetBrains Mono
  variable ×2, Joti One, Noto Color Emoji) + Nerd Fonts subset → installed to
  `~/.local/share/fonts` + fc-cache. System fonts come from dnf manifest.

### 3.4 DMS plugins — three tiers (this is the part you thought was lost)

| Tier | Plugins | How they're installed today |
|---|---|---|
| **Yours (gitted ✓)** | `dms-dynamic-cursor`, `dms-chrome-theme` | Already on GitHub (`Lcarv20/…`), cloned in `~/Developer/Software`, **symlinked** into `~/.config/dms/plugins/` |
| Community (registry) | `dankDesktopWeather`, `dankNotepadModule`, `dankSoftwareDepot`, `emojiPicker`, `quickCapture` | Managed by dms; pinned in `~/.config/dms/plugins.lock.json`. `dms plugins restore` reinstalls from the lockfile — **one command, nothing lost** |
| Community (external) | `dms-cpufreq` (MAHcodes — not in dms registry) | Cloned to `~/Developer/Software`, symlinked like your own |
| Bundled with env-linux | `simple-calc`, `trackpadBattery`, `web-search` | Files inside the `dms` stow package → land via stage 40 |

**Gap:** no installer stage consumes `plugins.lock.json` or clones your repos —
a fresh machine gets only the 3 bundled plugins. The lockfile mechanism exists;
it's just not wired into a stage yet.

### 3.5 Custom scripts — the full inventory (your "what do I even have?")

| Script | Lives in | What it does |
|---|---|---|
| `dux-cycle-radius` | env-linux `scripts/` stow | Cycles shell/window radius tiers (Mega→Square) on wallpaper change; driven by `dux-cycle-radius.path` user unit |
| `niri-focus-column-left-or-center` | env-linux `scripts/` stow | Mod+Left helper |
| `niri-focus-column-right-or-center` | env-linux `scripts/` stow | Mod+Right helper |
| `niri-zoomd` / `niri-zoomctl` | **assets tarball `bin/`** (binary) | Screen magnifier daemon + client; `niri-zoomd.service` user unit |
| `web-app-installer` | own repo `Lcarv20/web-app-installer`, cloned in `~/Developer/Software` | Go TUI: websites → chromeless Chrome apps; `make install` |

Everything else in `~/.local/bin` (agy, antigravity, cloudflared, hex, uv,
vibe*, llama, colorscripts, wtype, nvim shim) is installed by other tracks
(mise/uv/manual/apps) — **not** env-setup scope.

### 3.6 "Hooks" — what you actually did (and forgot)

No hidden magic. Your hooks are exactly:

1. **Stage 50:** Chrome policy dir `/etc/opt/chrome/policies/managed` (0775,
   for the chrome-theme plugin), greetd/dms-greeter enable, GDM/SDDM disable,
   systemd user units (`dfiles.service`, `dsearch`, `dux-cycle-radius.path`,
   `niri-zoomd.service`) via explicit `.wants` symlinks.
2. **Stow packages:** portals.conf (FileChooser→dfiles;gtk + mimeapps),
   environment.d vars (`DFILES_SHELL_DIR`, `DMS_SCREENSHOT_EDITOR`→quickCapture,
   XCURSOR, Electron ozone), XDG autostart masks (blueman/nm-applet/polkit —
   dms provides these natively), niri window rules (web-app-installer float
   modal, Dux Chooser float, blur/opacity, borders/shadows).
3. **dfiles-shell patcher** (`system/dfiles-patch/`): re-applies your UI
   snapshot after every dux-files RPM upgrade.
4. **Host stage 90 (iMac only):** kernel args, bt-resume-rescue v2, DKMS audio.

You minimized hooks by moving work into dms plugins (chrome-theme, dynamic
cursor, quickCapture rewires) — that's why there are only a few, and it worked.

## 4. Target architecture (proposal)

### 4.1 Stage layout (surgical changes, numbering preserved)

```
00-repos          unchanged
10-desktop-base   unchanged
20-niri-dms       unchanged
30-assets         retarget URL → Lcarv20/env-linux release `env-assets-v1`
35-plugins        NEW — see §4.2
40-dotfiles       remove 9 dead dev-package refs; keep stow + seeds
45-own-software   NEW — web-app-installer (clone → make install);
                  optional: build niri-zoom from source instead of tarball binary
50-services       unchanged (the hooks)
60-extras         remove Chrome (moved to dots-linux); keep flatpak/mise/udev
90-hardware       unchanged
```

Ordering logic: assets & plugins before dotfiles-stow so `plugin_settings.json`
references resolve; own software after services (needs Chrome + Go).

### 4.2 New stage 35-plugins (the heart of your scribbles)

1. **Community (registry):** `dms plugins restore` from the committed
   `plugins.lock.json` (pinned commits — deterministic). Narrated per plugin.
2. **Yours:** for each repo in a new `manifest/plugins.txt`
   (`repo-url name`): clone into `~/Developer/Software/<name>` (skip if exists,
   `git pull --ff-only` if it does), then symlink into
   `~/.config/dms/plugins/<name>`. Symlinks, not copies — matches the live
   machine, keeps your dev loop (`git -C ~/Developer/Software/dms-… && it's live`).
3. **External community (`dms-cpufreq`):** same clone+symlink path, listed in
   `manifest/plugins.txt` with a comment marking it third-party.
4. **Bundled three:** nothing to do — arrive with stage 40 stow.

### 4.3 Assets v2

- Publish **one** release on `Lcarv20/env-linux` tagged `env-assets-v1`
  containing the current tarball contents (wallpapers 661 MB, icons, fonts,
  dfiles-shell, bin/). Commit new `assets-v1.sha256`. Old dots-linux release
  stays as historical backup.
- **Decided:** ship all 56 wallpapers as-is — one tarball, one release
  (curating can happen later if a release ever feels heavy).
- **Decided:** keep binaries (`niri-zoomd`, `niri-zoomctl`) in the tarball —
  fast, pinned installs with no compile step; re-cut the tarball when
  niri-zoom updates.
- Micro-decision: fix the `Walpapers` → `Wallpapers` typo in the same sweep
  (session.json seed + stage 30 + tarball layout all change together anyway).
  Cheap now, annoying later.

### 4.4 Chrome ownership move

- `dots-linux/setup` gains the google-chrome repo + `google-chrome-stable`
  (dnf + apt paths, guarded, idempotent) — your explicit wish.
- `env-linux` 60-extras drops the install; stage 50 keeps creating the policy
  dir; a preflight check warns if Chrome is missing ("run dots-linux setup
  first"). The two installers stay independently runnable but document the
  order in both READMEs.

### 4.5 Installer UX — guided only, with yes-to-all (decided §6.2)

The installer always walks step by step:

1. Banner + preflight checks (Fedora, not root, network, dots-linux stowed)
   with friendly narration.
2. A short plan summary ("here's everything I'm about to do").
3. **One** choice right before the questions start: `Answer each step` vs
   `Yes to all — don't ask again this run` (also available as the `--yes`
   flag), so a VM test run is one keypress instead of ~40 confirms.
4. Per stage: a 2–4 line plain-language summary of exactly what it will do,
   then `gum confirm` (skipped under yes-to-all). Inside stages, `run_cmd`
   already narrates every mutating command ("Creating wallpapers folder
   ~/Pictures/Walpapers …").

The old `--profile=minimal|full|custom` picker is removed — the guided flow
installs the full environment (that's the point: "very close to what I have
here"). `--host=` / `--with-mango` / `--dry-run` / `--yes` stay.

Also: fix the stale "dots-linux" banner branding.

### 4.6 DMS state vs config hygiene

- Clean `dms/.config/dms/plugin_settings.json` (it currently contains a
  captured dnf5 update-history list — runtime state leaked into the repo).
- Commit or deliberately discard the 7 dirty working-tree files **first**,
  so the restructure starts from a clean, pushed HEAD.

## 5. Cruft list (fix during the work, ~1 session)

1. Stage 40: remove 9 dead dots-linux package refs (warning fires every run).
2. `install` banner + help still say "dots-linux".
3. `plugin_settings.json` runtime-state pollution (§4.6).
4. `niri/.config/niri/dms/outputs.kdl` duplicates `hosts/imac18-3/outputs.kdl`
   (machine state leaked into the portable package) — delete from package,
   host stage installs it.
5. Stage 50 + 90 both install the greeter dms.kdl — dedupe.
6. `imac18-3/apply.sh` header says "4K@1.25", reality is 5K kernel mode +
   3840x2160 niri mode — doc fix.
7. `README.md` quick start: add "run `~/dots-linux/setup` first".

## 6. Decisions

### Decided 6.1 — Surgical upgrade, not a rewrite (user, 2026-11-09)

Keep stages/manifests/hosts, dry-run and idempotency as-is. The work is:
2 new stages, assets URL retarget, guided UX, cruft list. The audit found the
skeleton sound; a rewrite would re-earn bugs the container matrix already
caught.

### Decided 6.2 — Guided only, with a yes-to-all escape hatch (user, 2026-11-09)

Every run walks step by step (§4.5). One **"Yes to all"** choice offered once,
right before the questions start (plus the `--yes` flag), so a VM test run is
a single keypress instead of ~40 confirms. The old `--profile` picker is
removed.

### Decided 6.3 — All 56 wallpapers, one tarball (user, 2026-11-09)

`env-assets-v1` release on `Lcarv20/env-linux` with the sha256 sidecar
committed.

### Decided 6.4 — niri-zoom stays as a tarball binary (user, 2026-11-09)

`niri-zoomd` / `niri-zoomctl` remain in the assets tarball `bin/` — fast,
pinned, no compile step. Re-cut the tarball when niri-zoom updates. Stage
45-own-software therefore only handles web-app-installer.

## 7. Implementation order (once decisions are in)

1. Triage + commit/push the dirty env-linux working tree; clean
   plugin_settings.json state pollution.
2. Cruft list §5 (mechanical, low risk).
3. dots-linux: add Chrome to `setup` (+ podman container re-test).
4. Build + publish `env-assets-v1` release on env-linux; retarget stage 30.
5. New stage 35-plugins + `manifest/plugins.txt` (lockfile restore + clone/symlink).
6. New stage 45-own-software: web-app-installer (clone → `make install`).
7. Installer UX: guided-only flow with the upfront yes-to-all choice,
   preflight checks and branding fix (§4.5).
8. `./install --dry-run` rehearsal end-to-end; then one real VM pass
   (`hosts/vm` exists exactly for this).
9. Update both READMEs + AGENTS.md + `~/Agentic-linux.md` log entry.
