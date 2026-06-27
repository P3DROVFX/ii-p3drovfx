# Hyprland Scripts

## Workspace Profile Manager

A high-performance Rust backend that captures live Hyprland clients via `hyprctl`, saves them as JSON profiles, and restores layouts on demand. Used by the Cheatsheet.

**Binary:** `~/.config/quickshell/ii/scripts/hyprland/workspace_profile_manager`
**Source:** `~/.config/quickshell/ii/scripts/hyprland/workspace_profile_manager_src/`

**Data:** Profiles are saved as JSON to `~/.config/illogical-impulse/workspace_profiles/` — safe to back up or sync across machines, and will survive dots updates.

### Rebuilding from Source

Only needed if you've modified the Rust source. Requires Rust/`cargo` ([install via rustup](https://rustup.rs)).

```bash
cd ~/.config/quickshell/ii/scripts/hyprland/workspace_profile_manager_src
cargo build --release
cp target/release/workspace_profile_manager ../
```
