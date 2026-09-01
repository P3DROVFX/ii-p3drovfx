#!/usr/bin/env python3
"""Regression contract for UserProfileAvatar component and its integration across the shell."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class UserProfileAvatarContractTests(unittest.TestCase):
    def setUp(self):
        self.avatar_qml = (ROOT / "modules/common/widgets/UserProfileAvatar.qml").read_text(encoding="utf-8")
        self.sidebar_qml = (ROOT / "modules/ii/sidebarDashboard/SidebarDashboardContent.qml").read_text(encoding="utf-8")
        self.user_header_qml = (ROOT / "modules/settings/UserHeader.qml").read_text(encoding="utf-8")
        self.profile_config_qml = (ROOT / "modules/settings/configs/UserProfileConfig.qml").read_text(encoding="utf-8")
        self.banner_selector_qml = (ROOT / "modules/settings/configs/widgets/ConfigBannerSelector.qml").read_text(encoding="utf-8")

    def test_avatar_component_has_gif_and_material_shape_support(self):
        self.assertIn("AnimatedImage", self.avatar_qml)
        self.assertIn("OpacityMask", self.avatar_qml)
        self.assertIn("MaterialShape", self.avatar_qml)
        self.assertIn("resolveShape(root.avatarShape)", self.avatar_qml)
        self.assertIn("playing: root.shouldPlay", self.avatar_qml)
        self.assertIn("paused: !root.shouldPlay", self.avatar_qml)
        self.assertIn("resolvedColor", self.avatar_qml)
        self.assertIn("resolvedOnColor", self.avatar_qml)
        self.assertIn("resolvedImageSource", self.avatar_qml)

    def test_sidebar_dashboard_uses_user_profile_avatar_in_banner_and_non_banner(self):
        self.assertIn("UserProfileAvatar", self.sidebar_qml)
        self.assertIn("active: GlobalStates.dashboardPanelOpen", self.sidebar_qml)
        self.assertNotIn("id: hardcodedProfilePicture", self.sidebar_qml)
        self.assertNotIn("id: profilePicMask", self.sidebar_qml)

    def test_sidebar_dashboard_banner_supports_animated_gifs(self):
        self.assertIn("id: bannerAnimatedImage", self.sidebar_qml)
        self.assertIn("playing: wallpaperArea.shouldPlayBanner", self.sidebar_qml)
        self.assertIn("paused: !wallpaperArea.shouldPlayBanner", self.sidebar_qml)
        self.assertIn("shouldPlayBanner: {", self.sidebar_qml)

    def test_banner_selector_supports_gifs(self):
        self.assertIn("*.gif", self.banner_selector_qml)
        self.assertIn("AnimatedImage", self.banner_selector_qml)
        self.assertIn("bannerPreviewAnimated", self.banner_selector_qml)

    def test_settings_user_header_uses_user_profile_avatar(self):
        self.assertIn("UserProfileAvatar", self.user_header_qml)
        self.assertIn("active: GlobalStates.settingsOpen", self.user_header_qml)
        self.assertNotIn("id: avatarCircle", self.user_header_qml)

    def test_profile_config_uses_user_profile_avatar_and_supports_gifs(self):
        self.assertIn("UserProfileAvatar", self.profile_config_qml)
        self.assertIn("active: GlobalStates.settingsOpen", self.profile_config_qml)
        self.assertIn("*.gif", self.profile_config_qml)
        self.assertIn("*.webp", self.profile_config_qml)


if __name__ == "__main__":
    unittest.main()
