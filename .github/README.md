# [ Quickshell/II ]

Premium Material 3 / Material You dotfiles for Hyprland, powered by Quickshell.

## System Preview

<img width="1924" height="1095" alt="SCreenshots_ii-p3drovfx" src="https://github.com/user-attachments/assets/dd08c71b-0965-4f9c-9c58-01271fd24e67" />


## Overview

This repository is a heavily customized fork of **[ii-vynx](https://github.com/vaguesyntax/ii-vynx)**, which itself is based on **[illogical-impulse](https://github.com/end-4/dots-hyprland)**. **This is my personal customization. It's not focused on performance or stability — if you use it, expect a lot of bugs.** If you find one, please open an issue or report it in the ii-p3drovfx thread inside **[end-4 discord](https://discord.gg/GtdRBXgMwq)**. I also accept PRs.

It aims to provide a state-of-the-art Linux desktop experience by strictly adhering to **Material 3 (Material You)** design principles, featuring dynamic theming via Matugen and a highly modular architecture built on **Quickshell**.

> [!NOTE]
> This repository is a work in progress. Some modules, like the Gmail client, require manual setup of API keys.

## Requirements

- **Hyprland 0.56.1 or newer**
- **Matugen 4.1.0 or newer**
- **quickshell-git 0.3.0 or newer**

## Installation

### Default installation

Use this if you don't have illogical-impulse already installed. It sets up the base
dotfiles and everything they need, then puts my config on top.

```bash
git clone --recurse-submodules https://github.com/P3DROVFX/ii-p3drovfx.git
cd ii-p3drovfx
./setup-ii-p3drovfx.sh install
```

### Minimal installation (only quickshell config)

Use this if illogical-impulse is already working and you only want my Quickshell config.
Nothing else is touched, and your current config is moved to a backup rather than deleted.

```bash
git clone --recurse-submodules https://github.com/P3DROVFX/ii-p3drovfx.git
cd ii-p3drovfx
./setup-ii-p3drovfx.sh
```

## Documentation

Please refer to the **[ii-p3drovfx wiki](https://github.com/P3DROVFX/ii-p3drovfx/wiki)** for detailed component descriptions.

<details> <summary><strong>🛠 Common Issues</strong></summary>

<br>

### Dynamic colors / Matugen are not working

If wallpaper colors are not being applied and you see an error such as:

> matugen exited with an error, so the shell kept its previous palette.

First, make sure you are running:

- **Matugen** 4.1.0 or newer
- **quickshell-git** 0.3.0 or newer

You can check the installed versions with:

```bash
matugen --version
quickshell --version
```

#### Arch Linux / CachyOS

Make sure you are using the AUR `quickshell-git` package, rather than another Quickshell build provided by a third-party repository.

A reported case on CachyOS was caused by the system using the Noctalia Quickshell package from the CachyOS repositories instead of `aur/quickshell-git`. Replacing it with the AUR package fixed Matugen and dynamic colors.

```bash
yay -S aur/quickshell-git
```

If another Quickshell package is installed, your package manager may ask to replace the conflicting package.

---

### Quickshell stopped working after a Qt update

Quickshell may stop starting correctly after a Qt update if the installed `quickshell-git` package was compiled against the previous Qt version.

For example, this can happen after updates such as:

```
Qt 6.11.1 -> Qt 6.11.2
```

Rebuild `quickshell-git` against the newly installed Qt libraries:

```bash
yay -S --rebuild aur/quickshell-git
```

Then restart Quickshell.

If rebuilding does not solve the problem, completely reinstall `quickshell-git` using your AUR helper.

> **💡 Tip**
>
> If the shell suddenly stops working immediately after a Qt system update, rebuilding `quickshell-git` should be one of the first troubleshooting steps.

</details>

## Credits

- **[end-4](https://github.com/end-4):** Creator of illogical-impulse.
- **[vaguesyntax](https://github.com/vaguesyntax):** Creator of ii-vynx.
- **[pc-trade](https://github.com/pctrade):** Some design and features inspo.
- **[so-do-i-look-like-him](https://github.com/so-do-i-look-like-him):** Installation bug fixes.
- **[asteriau](https://github.com/asteriau):** Cheatsheet keybinds animations.
- **[hnpf](https://github.com/hnpf):** Nothing widgets design
- **[gowall](https://github.com/Achno/gowall):** Dynamic icons theme system.
- **[hyprmon](https://github.com/erans/hyprmon):** Monitor management in settings.
- **[Quickshell](https://quickshell.org/):** Widget system.
- **[Hyprland](https://hypr.land/):** Compositor.

---

<div align="center">
    <p><b>If you like this project, consider giving it a star! ⭐</b></p>
</div>
