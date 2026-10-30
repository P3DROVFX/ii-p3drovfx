from __future__ import annotations

import importlib.util
import json
import os
import shutil
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "colors" / "matugen_templates.py"
SPEC = importlib.util.spec_from_file_location("matugen_templates", SCRIPT)
MT = importlib.util.module_from_spec(SPEC)
sys.modules["matugen_templates"] = MT  # dataclasses look the module up
SPEC.loader.exec_module(MT)

HAS_MATUGEN = shutil.which("matugen") is not None

# A config shaped like real ones: comments between blocks, installer markers,
# paths with spaces and parentheses, hooks with quotes, extra keys, subtables.
REAL_CONFIG = """\
[config]
version_check = false

# Harmonized accent hues
[config.custom_colors]
code_red = "#E53935"

[templates.m3colors]
input_path = '~/.config/matugen/templates/colors.json'
output_path = '~/.local/state/quickshell/user/generated/colors.json'

[templates.hyprland]  # window borders
input_path = '{T}/hypr.conf'
output_path = '{O}/hypr/colors.conf'

[templates.iisddmtheme]
input_path = '{T}/sddm.qml'
output_path = '{O}/sddm/Colors.qml'
post_hook = 'sudo ~/.config/ii-sddm-theme/sddm-theme-apply.sh &'

# Kvantum theme for Qt apps; rebuild with build_m3e_theme.py.
[templates.kvantum_svg]
input_path = '{T}/kv.svg'
output_path = '{O}/Kvantum/x.svg'
compare_to = '{{{{colors.primary.default.hex}}}}'

[templates.withsub]
input_path = '{T}/sub.txt'
output_path = '{O}/sub.out'

[[templates.withsub.colors_to_compare]]
name = "red"
color = "#ff0000"

# >>> zen-m3e >>>
[templates.zen-m3e]
input_path = '{T}/zen.css'
output_path = '{O}/.zen/abc.Default (release)/chrome/colors.css'
# <<< zen-m3e <<<
"""


class Sandbox(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="mt-test-")
        self.root = Path(self._tmp.name)
        self.cfg_dir = self.root / "matugen"
        self.tpl = self.cfg_dir / "templates"
        self.out = self.root / "out"
        self.tpl.mkdir(parents=True)
        self.out.mkdir()
        self._env = {k: os.environ.get(k) for k in ("MATUGEN_CONFIG_DIR", "XDG_STATE_HOME")}
        os.environ["MATUGEN_CONFIG_DIR"] = str(self.cfg_dir)
        os.environ["XDG_STATE_HOME"] = str(self.root / "state")

    def tearDown(self) -> None:
        for key, value in self._env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        self._tmp.cleanup()

    # helpers
    def write_config(self, text: str) -> Path:
        path = self.cfg_dir / "config.toml"
        path.write_text(text, encoding="utf-8")
        return path

    def template_file(self, name: str, body: str = "bg={{colors.surface.default.hex}}\n") -> str:
        path = self.tpl / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body, encoding="utf-8")
        return str(path)

    def real_config(self) -> str:
        for name in ("hypr.conf", "sddm.qml", "kv.svg", "sub.txt", "zen.css"):
            self.template_file(name)
        text = REAL_CONFIG.format(T=self.tpl, O=self.out)
        self.write_config(text)
        return text

    def run_ok(self, *argv: str) -> dict:
        status, payload = MT.run(list(argv))
        self.assertEqual(status, 0, payload)
        self.assertTrue(payload["ok"])
        return payload

    def run_err(self, code: str, *argv: str) -> dict:
        status, payload = MT.run(list(argv))
        self.assertEqual(status, 1, payload)
        self.assertEqual(payload["code"], code, payload)
        return payload

    def config_text(self) -> str:
        return (self.cfg_dir / "config.toml").read_text(encoding="utf-8")

    def live(self) -> dict:
        return tomllib.loads(self.config_text()).get("templates", {})

    def listed(self) -> dict:
        return {t["name"]: t for t in self.run_ok("list")["templates"]}


class ListingTests(Sandbox):
    def test_lists_every_template_of_a_real_config(self) -> None:
        self.real_config()
        listed = self.listed()
        self.assertEqual(set(listed), {"m3colors", "hyprland", "iisddmtheme", "kvantum_svg", "withsub", "zen-m3e"})
        self.assertEqual(listed["iisddmtheme"]["postHook"], "sudo ~/.config/ii-sddm-theme/sddm-theme-apply.sh &")
        self.assertTrue(listed["m3colors"]["locked"])
        self.assertFalse(listed["m3colors"]["editable"])
        self.assertTrue(listed["hyprland"]["core"])
        self.assertEqual(listed["kvantum_svg"]["extraKeys"], ["compare_to"])
        self.assertTrue(listed["zen-m3e"]["output"].endswith("abc.Default (release)/chrome/colors.css"))
        self.assertTrue(listed["hyprland"]["inputExists"])
        (self.tpl / "zen.css").unlink()
        self.assertFalse(self.listed()["zen-m3e"]["inputExists"])

    def test_missing_config_lists_nothing(self) -> None:
        payload = self.run_ok("list")
        self.assertFalse(payload["configExists"])
        self.assertEqual(payload["templates"], [])
        self.assertTrue(payload["themes"])  # the catalog is still offered

    def test_invalid_config_is_reported_not_rewritten(self) -> None:
        bad = "[templates.x\ninput_path = 'a'\n"
        self.write_config(bad)
        payload = self.run_ok("list")
        self.assertTrue(payload["configError"])
        self.run_err("invalid_config", "add", "y", "--input", self.template_file("y.txt"), "--output", "/tmp/y")
        self.assertEqual(self.config_text(), bad)

    def test_inline_and_dotted_templates_are_read_only(self) -> None:
        a = self.template_file("a.txt")
        self.write_config(f"[templates]\ninline = {{ input_path = '{a}', output_path = '{self.out}/a' }}\n"
                          f"dotted.input_path = '{a}'\ndotted.output_path = '{self.out}/d'\n")
        listed = self.listed()
        self.assertEqual(listed["inline"]["source"], "inline")
        self.assertFalse(listed["inline"]["editable"])
        self.assertFalse(listed["dotted"]["editable"])
        self.run_err("not_editable", "disable", "inline")
        self.run_err("exists", "add", "dotted", "--input", a, "--output", f"{self.out}/x")

    def test_multiline_values_are_read_only(self) -> None:
        a = self.template_file("a.txt")
        self.write_config(f"[templates.multi]\ninput_path = '{a}'\noutput_path = '{self.out}/m'\n"
                          "post_hook = '''\necho one\n'''\n")
        self.assertFalse(self.listed()["multi"]["editable"])
        self.run_err("not_editable", "update", "multi", "--post-hook", "echo")

    def test_quoted_names_and_header_comments(self) -> None:
        a = self.template_file("a.txt")
        self.write_config(f'[templates."my app"] # mine\ninput_path = \'{a}\'\noutput_path = \'{self.out}/m\'\n')
        self.assertIn("my app", self.listed())
        self.run_ok("update", "my app", "--rename", "my_app")
        self.assertIn("[templates.my_app] # mine", self.config_text())
        self.assertIn("my_app", self.live())


class AddTests(Sandbox):
    def test_add_appends_and_keeps_the_rest_byte_for_byte(self) -> None:
        original = self.real_config()
        src = self.template_file("new.txt")
        self.run_ok("add", "newapp", "--input", src, "--output", f"{self.out}/new.out", "--post-hook", "pkill -USR1 newapp || true")
        text = self.config_text()
        self.assertTrue(text.startswith(original.rstrip("\n")))
        self.assertEqual(self.live()["newapp"]["post_hook"], "pkill -USR1 newapp || true")
        self.assertEqual(self.live()["iisddmtheme"]["post_hook"], "sudo ~/.config/ii-sddm-theme/sddm-theme-apply.sh &")
        self.assertTrue((self.cfg_dir / "config.toml.bak-ii").read_text() == original)

    def test_add_creates_a_config_when_there_is_none(self) -> None:
        src = self.template_file("a.txt")
        self.run_ok("add", "a", "--input", src, "--output", f"{self.out}/a")
        data = tomllib.loads(self.config_text())
        self.assertFalse(data["config"]["version_check"])
        self.assertEqual(data["templates"]["a"]["input_path"], src)

    def test_rejects_bad_input(self) -> None:
        self.real_config()
        src = self.template_file("a.txt")
        self.run_err("exists", "add", "hyprland", "--input", src, "--output", f"{self.out}/x")
        for name in ("", "has space", "dot.ted", "x" * 65, "ação"):
            self.run_err("invalid_name", "add", name, "--input", src, "--output", f"{self.out}/x")
        self.run_err("input_missing", "add", "nope", "--input", f"{self.tpl}/missing.txt", "--output", f"{self.out}/x")
        self.run_err("missing_output", "add", "nope", "--input", src, "--output", "  ")
        self.run_err("same_path", "add", "nope", "--input", src, "--output", src)
        self.run_err("output_is_dir", "add", "nope", "--input", src, "--output", str(self.out))
        self.run_err("input_is_dir", "add", "nope", "--input", str(self.tpl), "--output", f"{self.out}/x")
        self.assertNotIn("nope", self.live())

    def test_awkward_characters_round_trip(self) -> None:
        src = self.template_file("it's here/tpl.txt")
        out = f"{self.out}/dir \"quoted\"\\back/out.txt"
        hook = "notify-send 'done' \"$HOME\" \\ && echo ok"
        self.run_ok("add", "awk", "--input", src, "--output", out, "--post-hook", hook)
        live = self.live()["awk"]
        self.assertEqual((live["input_path"], live["output_path"], live["post_hook"]), (src, out, hook))

    def test_create_writes_a_starter_for_each_format(self) -> None:
        for name, ext in (("plain", ".conf"), ("css", ".css"), ("json", ".json"), ("lua", ".lua")):
            path = f"{self.tpl}/{name}/{name}{ext}"
            self.run_ok("add", name, "--create", "--input", path, "--output", f"{self.out}/{name}{ext}")
            body = Path(path).read_text()
            self.assertIn("{{colors.primary.default.hex}}", body)
            if ext == ".json":
                json.loads(body.replace("{{", "").replace("}}", ""))
        self.run_err("input_exists", "add", "again", "--create", "--input", f"{self.tpl}/css/css.css", "--output", f"{self.out}/z")

    @unittest.skipUnless(HAS_MATUGEN, "matugen not installed")
    def test_every_starter_renders(self) -> None:
        for name, ext in (("plain", ".conf"), ("css", ".css"), ("json", ".json"), ("lua", ".lua"), ("noext", "")):
            self.run_ok("add", name, "--create", "--input", f"{self.tpl}/{name}/t{ext}", "--output", f"{self.out}/{name}{ext}")
            result = self.run_ok("test", name, "--color", "#336699", "--mode", "dark")
            self.assertNotIn("{{", result["preview"])
            self.assertIn("#", result["preview"])


class EditTests(Sandbox):
    def test_update_changes_only_the_named_keys(self) -> None:
        self.real_config()
        new_src = self.template_file("kv2.svg")
        self.run_ok("update", "kvantum_svg", "--input", new_src, "--post-hook", "echo hi")
        live = self.live()
        self.assertEqual(live["kvantum_svg"]["input_path"], new_src)
        self.assertEqual(live["kvantum_svg"]["post_hook"], "echo hi")
        self.assertEqual(live["kvantum_svg"]["compare_to"], "{{colors.primary.default.hex}}")
        self.assertIn("# Kvantum theme for Qt apps; rebuild with build_m3e_theme.py.", self.config_text())
        # The hook lands inside the table, before the next block's comment.
        text = self.config_text()
        self.assertLess(text.index("post_hook = 'echo hi'"), text.index("[templates.withsub]"))

    def test_empty_hook_removes_the_key(self) -> None:
        self.real_config()
        self.run_ok("update", "iisddmtheme", "--post-hook", "")
        self.assertNotIn("post_hook", self.live()["iisddmtheme"])

    def test_rename_moves_subtables_too(self) -> None:
        self.real_config()
        self.run_ok("update", "withsub", "--rename", "renamed")
        live = self.live()
        self.assertNotIn("withsub", live)
        self.assertEqual(live["renamed"]["colors_to_compare"][0]["name"], "red")
        self.run_err("exists", "update", "renamed", "--rename", "hyprland")

    def test_update_refuses_a_missing_template_file(self) -> None:
        self.real_config()
        self.run_err("input_missing", "update", "hyprland", "--input", f"{self.tpl}/gone.conf")
        self.assertEqual(self.live()["hyprland"]["input_path"], f"{self.tpl}/hypr.conf")

    def test_locked_palette_template(self) -> None:
        self.real_config()
        for argv in (("disable", "m3colors"), ("remove", "m3colors"), ("update", "m3colors", "--post-hook", "x")):
            self.run_err("locked", *argv)

    def test_unknown_names(self) -> None:
        self.real_config()
        for argv in (("disable", "ghost"), ("remove", "ghost"), ("update", "ghost", "--post-hook", "x"), ("test", "ghost")):
            self.run_err("not_found", *argv)


class ToggleTests(Sandbox):
    def test_disable_hides_it_from_matugen_and_enable_restores_the_exact_text(self) -> None:
        original = self.real_config()
        for name in ("hyprland", "withsub", "zen-m3e"):
            self.run_ok("disable", name)
            self.assertNotIn(name, self.live())
            self.assertFalse(self.listed()[name]["enabled"])
        self.assertIn("#~ [[templates.withsub.colors_to_compare]]", self.config_text())
        for name in ("hyprland", "withsub", "zen-m3e"):
            self.run_ok("enable", name)
        self.assertEqual(self.config_text(), original)

    def test_toggle_is_idempotent(self) -> None:
        self.real_config()
        self.run_ok("disable", "hyprland")
        self.assertFalse(self.run_ok("disable", "hyprland")["changed"])
        self.assertFalse(self.run_ok("enable", "iisddmtheme")["changed"])

    def test_edits_keep_a_disabled_template_disabled(self) -> None:
        self.real_config()
        self.run_ok("disable", "iisddmtheme")
        self.run_ok("update", "iisddmtheme", "--post-hook", "echo off")
        self.assertNotIn("iisddmtheme", self.live())
        entry = self.listed()["iisddmtheme"]
        self.assertEqual(entry["postHook"], "echo off")
        self.assertFalse(entry["enabled"])
        self.run_ok("enable", "iisddmtheme")
        self.assertEqual(self.live()["iisddmtheme"]["post_hook"], "echo off")

    def test_enable_refuses_when_the_template_file_is_gone(self) -> None:
        self.real_config()
        self.run_ok("disable", "hyprland")
        (self.tpl / "hypr.conf").unlink()
        self.run_err("input_missing", "enable", "hyprland")

    def test_a_disabled_last_block_is_still_found(self) -> None:
        src = self.template_file("a.txt")
        self.run_ok("add", "a", "--input", src, "--output", f"{self.out}/a")
        self.run_ok("disable", "a")
        self.run_ok("add", "b", "--input", src, "--output", f"{self.out}/b")
        self.assertEqual(set(self.listed()), {"a", "b"})
        self.run_ok("enable", "a")
        self.assertEqual(set(self.live()), {"a", "b"})


class RemoveTests(Sandbox):
    def test_remove_keeps_neighbours_and_their_comments(self) -> None:
        self.real_config()
        self.run_ok("remove", "iisddmtheme")
        text = self.config_text()
        self.assertNotIn("iisddmtheme", text)
        self.assertIn("# Kvantum theme for Qt apps", text)
        self.assertIn("# >>> zen-m3e >>>", text)
        self.assertEqual(set(self.live()), {"m3colors", "hyprland", "kvantum_svg", "withsub", "zen-m3e"})
        self.assertNotIn("\n\n\n", text)

    def test_remove_a_disabled_template(self) -> None:
        self.real_config()
        self.run_ok("disable", "withsub")
        self.run_ok("remove", "withsub")
        self.assertNotIn("withsub", self.config_text())

    def test_delete_input_only_touches_owned_unshared_files(self) -> None:
        own = self.template_file("mine/own.txt")
        shared = self.template_file("shared.txt")
        outside = self.root / "elsewhere.txt"
        outside.write_text("x")
        self.run_ok("add", "own", "--input", own, "--output", f"{self.out}/1")
        self.run_ok("add", "s1", "--input", shared, "--output", f"{self.out}/2")
        self.run_ok("add", "s2", "--input", shared, "--output", f"{self.out}/3")
        self.run_ok("add", "out", "--input", str(outside), "--output", f"{self.out}/4")
        self.assertTrue(self.run_ok("remove", "own", "--delete-input")["deletedInput"])
        self.assertFalse(Path(own).exists())
        self.assertFalse(Path(own).parent.exists())
        self.assertFalse(self.run_ok("remove", "s1", "--delete-input")["deletedInput"])
        self.assertTrue(Path(shared).exists())
        self.assertFalse(self.run_ok("remove", "out", "--delete-input")["deletedInput"])
        self.assertTrue(outside.exists())


class FileSafetyTests(Sandbox):
    def test_symlinked_config_is_written_through(self) -> None:
        real = self.root / "dotfiles" / "config.toml"
        real.parent.mkdir()
        real.write_text("[config]\n")
        (self.cfg_dir / "config.toml").symlink_to(real)
        self.run_ok("add", "a", "--input", self.template_file("a.txt"), "--output", f"{self.out}/a")
        self.assertTrue((self.cfg_dir / "config.toml").is_symlink())
        self.assertIn("[templates.a]", real.read_text())

    def test_file_mode_is_kept(self) -> None:
        path = self.write_config("[config]\n")
        path.chmod(0o600)
        self.run_ok("add", "a", "--input", self.template_file("a.txt"), "--output", f"{self.out}/a")
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_crlf_config_stays_valid(self) -> None:
        a = self.template_file("a.txt")
        self.write_config(f"[config]\r\nversion_check = false\r\n\r\n[templates.a]\r\ninput_path = '{a}'\r\noutput_path = '{self.out}/a'\r\n")
        self.run_ok("disable", "a")
        self.run_ok("enable", "a")
        self.assertIn("a", self.live())


class ThemeTests(Sandbox):
    def test_catalog_entries_are_complete_and_files_exist(self) -> None:
        catalog = MT.load_catalog()
        self.assertGreaterEqual(len(catalog), 5)
        ids = set()
        for theme in catalog:
            for key in ("id", "name", "symbol", "description", "template", "output", "setup"):
                self.assertTrue(theme.get(key), (theme.get("id"), key))
            self.assertTrue(MT.NAME_RE.match(theme["id"]))
            self.assertTrue((MT.CATALOG_DIR / theme["template"]).is_file())
            self.assertNotIn(theme["id"], ids)
            ids.add(theme["id"])

    def test_install_and_uninstall_every_theme(self) -> None:
        original = self.real_config()
        for theme in MT.load_catalog():
            self.run_ok("install-theme", theme["id"])
            self.run_err("exists", "install-theme", theme["id"])
        themes = {t["id"]: t for t in self.run_ok("list")["themes"]}
        self.assertTrue(all(t["installed"] and t["fromCatalog"] for t in themes.values()))
        custom = tomllib.loads(self.config_text())["config"]["custom_colors"]
        self.assertEqual(custom["code_red"], "#E53935")  # the user's value is kept
        self.assertIn("code_cyan", custom)
        for theme in MT.load_catalog():
            self.run_ok("uninstall-theme", theme["id"])
        self.assertFalse(any(t["installed"] for t in self.run_ok("list")["themes"]))
        self.assertFalse((self.tpl / "ii-themes").exists())
        # Only the added custom colours remain from the round trip.
        self.assertEqual(set(self.live()), set(tomllib.loads(original)["templates"]))

    def test_custom_colors_without_a_table(self) -> None:
        self.write_config("# my config\n[config]\nversion_check = false\n\n[templates.x]\ninput_path = '/a'\noutput_path = '/b'\n")
        self.run_ok("install-theme", "kitty")
        data = tomllib.loads(self.config_text())
        self.assertIn("code_blue", data["config"]["custom_colors"])
        self.assertTrue(self.config_text().startswith("# my config\n[config]\nversion_check = false\n\n[config.custom_colors]"))

    def test_custom_colors_inline_is_refused(self) -> None:
        self.write_config("[config]\ncustom_colors = { code_red = '#ff0000' }\n")
        self.run_err("not_editable", "install-theme", "kitty")

    def test_users_own_template_counts_as_installed_but_is_not_uninstalled(self) -> None:
        own = self.template_file("btop.theme")
        self.run_ok("add", "mybtop", "--input", own, "--output", "~/.config/btop/themes/matugen.theme")
        themes = {t["id"]: t for t in self.run_ok("list")["themes"]}
        self.assertTrue(themes["btop"]["installed"])
        self.assertFalse(themes["btop"]["fromCatalog"])
        self.run_err("exists", "install-theme", "btop")
        self.run_err("not_catalog", "uninstall-theme", "btop")
        self.assertTrue(Path(own).exists())

    @unittest.skipUnless(HAS_MATUGEN, "matugen not installed")
    def test_every_theme_renders_in_both_modes(self) -> None:
        for theme in MT.load_catalog():
            self.run_ok("install-theme", theme["id"])
            for mode in ("dark", "light"):
                result = self.run_ok("test", theme["id"], "--mode", mode, "--color", "#8a4f2a")
                self.assertNotIn("{{", result["preview"], theme["id"])
                self.assertGreater(result["lines"], 3)


@unittest.skipUnless(HAS_MATUGEN, "matugen not installed")
class RenderTests(Sandbox):
    def test_syntax_error_is_reported(self) -> None:
        bad = self.template_file("bad.txt", "x={{ unclosed\n")
        self.run_ok("add", "bad", "--input", bad, "--output", f"{self.out}/bad")
        payload = self.run_err("render_failed", "test", "bad")
        self.assertIn("expected", payload["error"])
        self.assertNotIn("\x1b", payload["error"])

    def test_unknown_colour_is_reported(self) -> None:
        bad = self.template_file("bad.txt", "x={{colors.not_a_role.default.hex}}\n")
        self.run_ok("add", "bad", "--input", bad, "--output", f"{self.out}/bad")
        self.run_err("render_failed", "test", "bad")

    def test_custom_colours_from_the_config_are_available(self) -> None:
        tpl = self.template_file("c.txt", "red={{colors.code_red.default.hex}}\n")
        self.write_config("[config]\n[config.custom_colors]\ncode_red = '#E53935'\n")
        self.run_ok("add", "c", "--input", tpl, "--output", f"{self.out}/c")
        self.assertIn("red=#", self.run_ok("test", "c")["preview"])

    def test_hooks_never_run_in_a_test(self) -> None:
        marker = self.root / "hook-ran"
        tpl = self.template_file("h.txt")
        self.run_ok("add", "h", "--input", tpl, "--output", f"{self.out}/h", "--post-hook", f"touch {marker}")
        self.run_ok("test", "h")
        self.assertFalse(marker.exists())
        self.assertFalse((self.out / "h").exists())  # nor writes the real output

    def test_missing_template_file(self) -> None:
        tpl = self.template_file("gone.txt")
        self.run_ok("add", "g", "--input", tpl, "--output", f"{self.out}/g")
        Path(tpl).unlink()
        self.run_err("input_missing", "test", "g")

    def test_mode_follows_the_shell_palette(self) -> None:
        colors = self.root / "state/quickshell/user/generated/colors.json"
        colors.parent.mkdir(parents=True)
        colors.write_text(json.dumps({"primary": "#336699", "background": "#fafafa"}))
        tpl = self.template_file("m.txt", "{{mode}}\n")
        self.run_ok("add", "m", "--input", tpl, "--output", f"{self.out}/m")
        result = self.run_ok("test", "m")
        self.assertEqual((result["mode"], result["preview"].strip()), ("light", "light"))


class CliTests(Sandbox):
    def test_cli_prints_one_json_object(self) -> None:
        import subprocess, sys
        proc = subprocess.run([sys.executable, str(SCRIPT), "list"], capture_output=True, text=True,
                              env={**os.environ})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(json.loads(proc.stdout)["ok"])
        proc = subprocess.run([sys.executable, str(SCRIPT), "remove", "ghost"], capture_output=True, text=True,
                              env={**os.environ})
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(json.loads(proc.stdout)["code"], "not_found")


if __name__ == "__main__":
    unittest.main()
