from __future__ import annotations

import importlib.util
import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "ai_plan_usage.py"
SPEC = importlib.util.spec_from_file_location("ai_plan_usage", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class AiPlanUsageParserTests(unittest.TestCase):
    def test_codex_rate_limits_preserve_real_windows(self) -> None:
        result = MODULE.parse_codex_rate_limits(
            {
                "plan_type": "plus",
                "primary": {
                    "used_percent": 17,
                    "window_minutes": 300,
                    "resets_at": 1_800_000_000,
                },
                "secondary": {
                    "used_percent": 42,
                    "window_minutes": 10080,
                    "resets_at": 1_800_500_000,
                },
            }
        )
        self.assertEqual(result["plan"], "plus")
        self.assertEqual([item["windowKind"] for item in result["items"]], ["short", "weekly"])
        self.assertEqual(result["items"][0]["windowLabel"], "5 hours")
        self.assertEqual(result["items"][1]["remainingPercent"], 58)

    def test_codex_relative_reset_is_converted_to_timestamp(self) -> None:
        before = int(time.time() * 1000)
        result = MODULE.parse_codex_rate_limits(
            {
                "primary": {
                    "used_percent": 1,
                    "window_minutes": 300,
                    "resets_in_seconds": 120,
                }
            }
        )
        reset = result["items"][0]["resetsAt"]
        self.assertGreaterEqual(reset, before + 119_000)
        self.assertLessEqual(reset, before + 121_000)

    def test_window_kinds_preserve_daily_and_monthly_labels(self) -> None:
        self.assertEqual(MODULE.window_kind(1440, ""), "daily")
        self.assertEqual(MODULE.window_kind(43200, "monthly"), "monthly")
        self.assertEqual(MODULE.duration_label(0, "monthly limit"), "Monthly")

    def test_claude_usage_keeps_model_scoped_weekly_lanes(self) -> None:
        result = MODULE.parse_claude_usage(
            {
                "five_hour": {"utilization": 9, "resets_at": "2026-08-30T05:00:00Z"},
                "seven_day": {"utilization": 21, "resets_at": "2026-09-03T05:00:00Z"},
                "seven_day_sonnet": {
                    "utilization": 34,
                    "resets_at": "2026-09-03T05:00:00Z",
                },
            },
            plan="max",
        )
        self.assertEqual(len(result["items"]), 3)
        self.assertEqual(result["items"][2]["groupId"], "sonnet")
        self.assertEqual(result["items"][2]["id"], "claude:sonnet:weekly")
        self.assertGreater(result["items"][2]["resetsAt"], 0)

    def test_antigravity_summary_yields_two_pools_and_four_lanes(self) -> None:
        result = MODULE.parse_antigravity_summary(
            {
                "response": {
                    "userTier": "Pro",
                    "groups": [
                        {
                            "displayName": "Gemini Models",
                            "buckets": [
                                {
                                    "displayName": "Weekly Limit",
                                    "window": "weekly",
                                    "remainingFraction": 0.75,
                                },
                                {
                                    "displayName": "Five Hour Limit",
                                    "window": "5h",
                                    "remainingFraction": 0.5,
                                },
                            ],
                        },
                        {
                            "displayName": "Claude and GPT models",
                            "buckets": [
                                {
                                    "displayName": "Weekly Limit",
                                    "window": "weekly",
                                    "remainingFraction": 0.9,
                                },
                                {
                                    "displayName": "Five Hour Limit",
                                    "window": "5h",
                                    "remainingFraction": 0.8,
                                },
                            ],
                        },
                    ],
                }
            }
        )
        self.assertEqual(result["plan"], "Pro")
        self.assertEqual(len(result["items"]), 4)
        self.assertEqual(
            {item["groupId"] for item in result["items"]}, {"gemini", "other"}
        )
        self.assertEqual(
            {item["windowKind"] for item in result["items"]}, {"short", "weekly"}
        )

    def test_antigravity_legacy_status_uses_most_constrained_model_per_pool(self) -> None:
        result = MODULE.parse_antigravity_status(
            {
                "userStatus": {
                    "planStatus": {"planInfo": {"planName": "Starter"}},
                    "cascadeModelConfigData": {
                        "clientModelConfigs": [
                            {
                                "label": "Gemini Pro",
                                "quotaInfo": {"remainingFraction": 0.8},
                            },
                            {
                                "label": "Gemini Flash",
                                "quotaInfo": {"remainingFraction": 0.35},
                            },
                            {
                                "label": "Claude Sonnet",
                                "quotaInfo": {"remainingFraction": 0.6},
                            },
                        ]
                    },
                }
            }
        )
        gemini = next(item for item in result["items"] if item["groupId"] == "gemini")
        self.assertEqual(gemini["usedPercent"], 65)
        self.assertEqual(result["plan"], "Starter")

    def test_zai_usage_preserves_five_hour_and_weekly_token_windows(self) -> None:
        result = MODULE.parse_zai_usage(
            {
                "data": {
                    "level": "pro",
                    "limits": [
                        {
                            "type": "TOKENS_LIMIT",
                            "unit": 3,
                            "number": 5,
                            "percentage": 36,
                            "nextResetTime": 1_800_000_000_000,
                        },
                        {
                            "type": "CREDIT_LIMIT",
                            "unit": 6,
                            "number": 1,
                            "percentage": 24,
                            "nextResetTime": 1_800_500_000_000,
                        },
                        {
                            "type": "TIME_LIMIT",
                            "unit": 5,
                            "number": 1,
                            "percentage": 8,
                        },
                    ],
                }
            }
        )
        self.assertEqual(result["plan"], "pro")
        self.assertEqual([item["windowKind"] for item in result["items"]], ["short", "weekly"])
        self.assertEqual(result["items"][0]["windowLabel"], "5 hours")
        self.assertEqual(result["items"][1]["remainingPercent"], 76)

    def test_kimi_code_usage_preserves_weekly_summary_and_five_hour_limit(self) -> None:
        result = MODULE.parse_kimi_usage(
            {
                "user": {"membership": {"level": "LEVEL_ADVANCED"}},
                "usage": {
                    "limit": "100",
                    "used": "51",
                    "remaining": "49",
                    "resetTime": "2030-01-08T00:00:00Z",
                },
                "limits": [
                    {
                        "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
                        "detail": {
                            "limit": "100",
                            "used": "10",
                            "remaining": "90",
                            "resetTime": "2030-01-01T05:00:00Z",
                        },
                    }
                ],
            }
        )
        self.assertEqual(result["plan"], "Advanced")
        self.assertEqual([item["windowKind"] for item in result["items"]], ["short", "weekly"])
        self.assertEqual(result["items"][0]["windowMinutes"], 300)
        self.assertEqual(result["items"][1]["remainingPercent"], 49)

    def test_opencode_go_usage_preserves_all_published_windows(self) -> None:
        result = MODULE.parse_opencode_usage(
            {
                "usage": {
                    "rolling": {"status": "ok", "percent": 12, "resetsAt": "2030-01-01T05:00:00Z"},
                    "weekly": {"status": "ok", "percent": 34, "resetsAt": "2030-01-08T00:00:00Z"},
                    "monthly": {"status": "ok", "percent": 56, "resetsAt": "2030-02-01T00:00:00Z"},
                }
            }
        )
        self.assertEqual(result["plan"], "Go")
        self.assertEqual(
            [item["windowKind"] for item in result["items"]],
            ["short", "weekly", "monthly"],
        )
        self.assertEqual(result["items"][0]["windowLabel"], "5 hours")

    def test_openrouter_credits_exposes_one_remaining_balance_item(self) -> None:
        result = MODULE.parse_openrouter_credits(
            {"data": {"total_credits": 25.5, "total_usage": 7.25}}
        )
        self.assertEqual(len(result["items"]), 1)
        item = result["items"][0]
        self.assertEqual(item["metricKind"], "credits")
        self.assertEqual(item["windowKind"], "balance")
        self.assertEqual(item["remainingAmount"], 18.25)
        self.assertEqual(item["currency"], "USD")
        self.assertNotIn("totalUsage", item)

    def test_openrouter_current_key_requires_a_numeric_remaining_limit(self) -> None:
        available = MODULE.parse_openrouter_key(
            {"data": {"limit": 10, "limit_remaining": 4.5}}
        )
        unlimited = MODULE.parse_openrouter_key(
            {"data": {"limit": None, "limit_remaining": None}}
        )
        self.assertTrue(available["available"])
        self.assertEqual(available["items"][0]["remainingAmount"], 4.5)
        self.assertFalse(unlimited["available"])

    def test_local_client_credentials_are_discovered_by_provider_id(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, mock.patch.dict(
            MODULE.os.environ, {}, clear=True
        ):
            root = Path(temporary)
            claude_settings = root / "claude-settings.json"
            claude_settings.write_text(
                json.dumps(
                    {
                        "env": {
                            "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
                            "ANTHROPIC_AUTH_TOKEN": "zai-secret",
                        }
                    }
                ),
                encoding="utf-8",
            )
            opencode_auth = root / "auth.json"
            opencode_auth.write_text(
                json.dumps(
                    {
                        "opencode-go": {"type": "api", "key": "go-secret"},
                        "unrelated": {"type": "api", "key": "other-secret"},
                    }
                ),
                encoding="utf-8",
            )
            kimi_root = root / "kimi"
            (kimi_root / "credentials").mkdir(parents=True)
            (kimi_root / "credentials" / "kimi-code.json").write_text(
                json.dumps(
                    {
                        "access_token": "kimi-secret",
                        "expires_at": time.time() + 3600,
                    }
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                MODULE.zai_api_key(
                    claude_settings_path=claude_settings,
                    opencode_auth_path=opencode_auth,
                ),
                "zai-secret",
            )
            self.assertEqual(
                MODULE.kimi_api_key(
                    kimi_roots=[kimi_root], opencode_auth_path=opencode_auth
                ),
                "kimi-secret",
            )
            self.assertEqual(MODULE.opencode_api_key(opencode_auth), "go-secret")

    def test_collect_dispatches_each_new_provider_independently(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(
            MODULE, "collect_zai", return_value=MODULE.provider_result("zai")
        ) as zai, mock.patch.object(
            MODULE, "collect_kimi", return_value=MODULE.provider_result("kimi")
        ) as kimi, mock.patch.object(
            MODULE, "collect_opencode", return_value=MODULE.provider_result("opencode")
        ) as opencode, mock.patch.object(
            MODULE,
            "collect_openrouter",
            return_value=MODULE.provider_result("openrouter"),
        ) as openrouter:
            result = MODULE.collect(
                ["zai", "kimi", "opencode", "openrouter"],
                cache_dir=Path(temporary),
                claude_network=False,
                force=True,
            )
        self.assertEqual(
            [provider["id"] for provider in result["providers"]],
            ["zai", "kimi", "opencode", "openrouter"],
        )
        zai.assert_called_once()
        kimi.assert_called_once()
        opencode.assert_called_once()
        openrouter.assert_called_once()

    def test_cache_never_contains_credentials(self) -> None:
        payload = MODULE.provider_result(
            "claude",
            items=[],
            plan="max",
            source="test",
            error="offline",
        )
        with tempfile.TemporaryDirectory() as temporary:
            cache_dir = Path(temporary)
            MODULE.save_provider_cache(cache_dir, payload)
            body = (cache_dir / "claude.json").read_text(encoding="utf-8")
        self.assertNotIn("accessToken", body)
        self.assertNotIn("refreshToken", body)

    def test_invalid_cache_timestamp_is_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            cache_dir = Path(temporary)
            (cache_dir / "claude.json").write_text(
                json.dumps({"id": "claude", "updatedAt": "not-a-number", "items": []}),
                encoding="utf-8",
            )
            self.assertIsNone(MODULE.load_provider_cache(cache_dir, "claude"))

    def test_antigravity_null_response_is_an_unavailable_snapshot(self) -> None:
        result = MODULE.parse_antigravity_status({"response": None})
        self.assertFalse(result["available"])
        self.assertEqual(result["items"], [])

    def test_one_provider_failure_does_not_drop_healthy_results(self) -> None:
        healthy = MODULE.provider_result(
            "claude",
            items=[
                MODULE.make_item(
                    item_id="claude:short",
                    provider_id="claude",
                    used_percent=10,
                    window_label="5 hours",
                    window_kind_value="short",
                )
            ],
        )
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(
            MODULE, "collect_chatgpt", side_effect=RuntimeError("bad payload")
        ), mock.patch.object(MODULE, "collect_claude", return_value=healthy):
            result = MODULE.collect(
                ["chatgpt", "claude"],
                cache_dir=Path(temporary),
                claude_network=False,
                force=False,
            )
        self.assertTrue(result["ok"])
        self.assertEqual([provider["id"] for provider in result["providers"]], ["chatgpt", "claude"])
        self.assertFalse(result["providers"][0]["available"])
        self.assertTrue(result["providers"][1]["available"])


class AiPlanUsageQmlContracts(unittest.TestCase):
    def test_feature_has_no_borders_or_pulse_animation(self) -> None:
        paths = list(
            (ROOT / "modules" / "ii" / "bar" / "widgets" / "aiPlanUsage").glob("*.qml")
        )
        paths += list(
            (ROOT / "modules" / "ii" / "bar" / "popups" / "aiPlanUsage").glob("*.qml")
        )
        paths.append(
            ROOT / "modules" / "settings" / "configs" / "widgets" / "AiPlanUsageConfig.qml"
        )
        combined = "\n".join(path.read_text(encoding="utf-8") for path in paths)
        self.assertNotIn("border.width", combined)
        self.assertNotIn("warnPulse", combined)
        self.assertNotIn("loops: Animation.Infinite", combined)

    def test_feature_wiring_covers_requested_designs_and_providers(self) -> None:
        config = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
        bar = (ROOT / "modules" / "ii" / "bar" / "BarComponent.qml").read_text(
            encoding="utf-8"
        )
        service = (ROOT / "services" / "AiPlanUsage.qml").read_text(encoding="utf-8")
        settings = (
            ROOT
            / "modules"
            / "settings"
            / "configs"
            / "widgets"
            / "AiPlanUsageConfig.qml"
        ).read_text(encoding="utf-8")
        popup = (
            ROOT
            / "modules"
            / "ii"
            / "bar"
            / "popups"
            / "aiPlanUsage"
            / "AiProviderQuotaCard.qml"
        ).read_text(encoding="utf-8")

        self.assertIn("property list<string> enabledProviders", config)
        self.assertNotIn("primaryWindow", config)
        self.assertNotIn("secondaryWindow", config)
        self.assertIn("AiPlanUsageWidget", bar)
        self.assertIn("ExpressiveAiPlanUsage", bar)
        self.assertIn("displayProviders", service)
        self.assertIn('id: "antigravity:" + groupId', service)
        self.assertIn("selected.length >= 2", service)
        self.assertIn("providerData.items", popup)
        for provider in (
            "chatgpt",
            "claude",
            "antigravity",
            "zai",
            "kimi",
            "opencode",
            "openrouter",
        ):
            self.assertIn(provider, settings.lower())
        for mode in ("resource", "semicircle", "circle", "shape", "bar", "text"):
            self.assertIn(f'value: "{mode}"', settings)

    def test_bar_click_cycles_provider_and_popup_stays_card_only(self) -> None:
        widget_paths = [
            ROOT
            / "modules"
            / "ii"
            / "bar"
            / "widgets"
            / "aiPlanUsage"
            / "AiPlanUsageWidget.qml",
            ROOT
            / "modules"
            / "ii"
            / "bar"
            / "widgets"
            / "aiPlanUsage"
            / "ExpressiveAiPlanUsage.qml",
        ]
        widgets = "\n".join(path.read_text(encoding="utf-8") for path in widget_paths)
        indicator = (
            ROOT
            / "modules"
            / "ii"
            / "bar"
            / "widgets"
            / "aiPlanUsage"
            / "AiQuotaIndicator.qml"
        ).read_text(encoding="utf-8")
        popup = (
            ROOT
            / "modules"
            / "ii"
            / "bar"
            / "popups"
            / "aiPlanUsage"
            / "AiPlanUsagePopup.qml"
        ).read_text(encoding="utf-8")
        provider_card = (
            ROOT
            / "modules"
            / "ii"
            / "bar"
            / "popups"
            / "aiPlanUsage"
            / "AiProviderQuotaCard.qml"
        ).read_text(encoding="utf-8")

        self.assertEqual(widgets.count("onClicked: AiPlanUsage.cycleProvider()"), 2)
        self.assertNotIn("onClicked: AiPlanUsage.refresh", widgets)
        self.assertNotIn("StyledToolTip", indicator)
        self.assertNotIn("HeroCard", popup)
        self.assertNotIn("AiPlanUsage.refresh", popup)
        self.assertNotIn("ensureFresh", popup)
        self.assertIn("model: AiPlanUsage.displayProviders", popup)
        self.assertIn("OpacityMask", popup)
        self.assertIn("showDivider: false", provider_card)

    def test_provider_swap_animates_and_gauges_are_automatic(self) -> None:
        transition = (
            ROOT
            / "modules"
            / "ii"
            / "bar"
            / "widgets"
            / "aiPlanUsage"
            / "AiQuotaTransition.qml"
        ).read_text(encoding="utf-8")
        settings = (
            ROOT
            / "modules"
            / "settings"
            / "configs"
            / "widgets"
            / "AiPlanUsageConfig.qml"
        ).read_text(encoding="utf-8")
        indicator = (
            ROOT
            / "modules"
            / "ii"
            / "bar"
            / "widgets"
            / "aiPlanUsage"
            / "AiQuotaIndicator.qml"
        ).read_text(encoding="utf-8")

        self.assertIn("SequentialAnimation", transition)
        self.assertIn('property: "opacity"', transition)
        self.assertIn("Translate", transition)
        self.assertNotIn("Primary gauge", settings)
        self.assertNotIn("Second gauge", settings)
        self.assertIn("root.vertical", indicator)

    def test_vertical_progress_and_text_only_have_no_container_surface(self) -> None:
        indicator = (
            ROOT
            / "modules"
            / "ii"
            / "bar"
            / "widgets"
            / "aiPlanUsage"
            / "AiQuotaIndicator.qml"
        ).read_text(encoding="utf-8")
        vertical_progress = indicator.split("id: verticalBarComponent", 1)[1].split(
            "id: textComponent", 1
        )[0]
        text_only = indicator.split("id: textComponent", 1)[1]

        self.assertIn("StyledProgressBar", vertical_progress)
        self.assertIn("id: verticalProgress", vertical_progress)
        self.assertNotIn("verticalRail", vertical_progress)
        self.assertNotIn("Rectangle", vertical_progress)
        self.assertIn("StyledText", text_only)
        self.assertNotIn("Rectangle", text_only)

    def test_expressive_outline_modes_use_provider_accent_foreground(self) -> None:
        widget_dir = (
            ROOT / "modules" / "ii" / "bar" / "widgets" / "aiPlanUsage"
        )
        expressive = (widget_dir / "ExpressiveAiPlanUsage.qml").read_text(
            encoding="utf-8"
        )
        transition = (widget_dir / "AiQuotaTransition.qml").read_text(
            encoding="utf-8"
        )
        indicator = (widget_dir / "AiQuotaIndicator.qml").read_text(
            encoding="utf-8"
        )

        self.assertIn("useAccentForeground: true", expressive)
        self.assertIn("property bool useAccentForeground: false", transition)
        self.assertIn("useAccentForeground: root.useAccentForeground", transition)
        self.assertIn(
            "root.useAccentForeground ? root.providerAccent : root.contentColor",
            indicator,
        )

    def test_openrouter_is_presented_as_remaining_credits_only(self) -> None:
        service = (ROOT / "services" / "AiPlanUsage.qml").read_text(encoding="utf-8")
        row = (
            ROOT
            / "modules"
            / "ii"
            / "bar"
            / "popups"
            / "aiPlanUsage"
            / "AiQuotaRow.qml"
        ).read_text(encoding="utf-8")

        self.assertIn('String(item.metricKind ?? "quota") !== "credits"', service)
        self.assertIn("creditAmountText", service)
        self.assertIn("visible: !root.creditBalance", row)
        self.assertIn('Translation.tr("Credits remaining")', row)


if __name__ == "__main__":
    unittest.main()
