# env-linux 🖥️

The **desktop environment track**: Niri + Dux Shell (dms) on Wayland,
managed with **GNU Stow** and installed by a single interactive TUI.
Dev-tool dotfiles live separately in [`dots-linux`](https://github.com/Lcarv20/dots-linux).

Imported from the former single-repo `dots-linux` (environment packages +
installer) so each track can evolve independently.

## 🚀 Quick start (Fedora Server / Minimal VM)

```bash
git clone <this-repo> ~/env-linux
cd ~/env-linux
./install
```

The installer detects your hardware (iMac18,3 vs VM vs generic), shows a plan
(gum TUI), and runs the stages. Reboot when it finishes → you land in
**greetd → dms-greeter → Niri**.

```bash
./install --yes --profile=full        # unattended
./install --host=vm --profile=minimal
./install --dry-run                   # rehearse, change nothing
```

## 🧩 Layout

```
manifest/   package lists (copr · dnf-core · dnf-extras · flatpak · mise)
stages/     00-repos → 10-desktop-base → 20-niri-dms → 30-assets →
            40-dotfiles → 50-services → 60-extras → 90-hardware
system/     root-owned files: greetd, greeter niri configs, udev, patches
hosts/      imac18-3 (kernel args, BT rescue, DKMS audio, 5K outputs)
            vm (guest agents)
<packages>/ niri · dms · mango · portals · environment · systemd-user ·
            scripts · desktop-tools
```

### Host profiles

- **imac18,3** — s2idle + `acpi_osi=!Darwin` + `acpi_backlight=video` +
  5K `eDP-1` mode, `bt-resume-rescue`, DKMS `snd_hda_macbookpro`.
- **vm** — `qemu-guest-agent` + `spice-vdagent`, no hardcoded outputs.

### Stowed packages → paths

| Package | Path |
|---|---|
| niri | `~/.config/niri` |
| dms | `~/.config/dms` |
| mango | `~/.config/mango` |
| portals | `~/.config/xdg-desktop-portal/portals.conf`, `~/.config/xdg-terminals.list` |
| environment | `~/.config/environment.d` |
| systemd-user | `~/.config/systemd/user` |
| scripts | `~/.local/bin` (niri-zoom helpers, …) |
| desktop-tools | `~/.config/emoji-picker` |

## 🛠 Notes

- Requires `sudo`; run `./install` as your normal user (never as root).
- After a **dux-files RPM upgrade**, re-apply shell patches:
  `system/dfiles-patch/apply-dfiles-patch.sh --refresh`
- AI agents: read [`AGENTS.md`](AGENTS.md) first.
