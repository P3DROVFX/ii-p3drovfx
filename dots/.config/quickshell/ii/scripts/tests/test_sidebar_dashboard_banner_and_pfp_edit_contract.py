#!/usr/bin/env python3
"""Contract test for clicking profile picture and header banner in edit mode within SidebarDashboard."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class SidebarDashboardBannerAndPfpEditContractTests(unittest.TestCase):
    def setUp(self):
        self.sidebar_qml = (ROOT / "modules/ii/sidebarDashboard/SidebarDashboardContent.qml").read_text(encoding="utf-8")
        self.picker_qml = (ROOT / "modules/common/widgets/BannerImagePicker.qml").read_text(encoding="utf-8")

    def test_banner_image_picker_exists_and_sets_options(self):
        self.assertIn("Process", self.picker_qml)
        self.assertIn("Directories.scriptPath + \"/image_picker.py\"", self.picker_qml)
        self.assertIn("Config.options.sidebar.bannerImage = targetPath", self.picker_qml)
        self.assertIn("Config.options.sidebar.useCustomBanner = true", self.picker_qml)
        self.assertIn("function pick()", self.picker_qml)

    def test_sidebar_dashboard_declares_pickers(self):
        self.assertIn("BannerImagePicker", self.sidebar_qml)
        self.assertIn("UserProfileImagePicker", self.sidebar_qml)

    def test_sidebar_banner_has_edit_mode_overlay_and_click(self):
        self.assertIn("id: bannerEditContainer", self.sidebar_qml)
        self.assertIn("visible: headerRoot.editMode", self.sidebar_qml)
        self.assertIn("onClicked: bannerPicker.pick()", self.sidebar_qml)
        self.assertIn("cursorShape: headerRoot.editMode ? Qt.PointingHandCursor : Qt.ArrowCursor", self.sidebar_qml)

    def test_sidebar_banner_profile_picture_has_edit_badge_and_click(self):
        self.assertIn("id: pfpEditBadge", self.sidebar_qml)
        self.assertIn("profileImagePicker.pick()", self.sidebar_qml)
        self.assertIn("Config.options.userProfile.imageStyle = \"custom\"", self.sidebar_qml)
        self.assertIn("Config.options.sidebar.dashboardHeader.profileImageType = \"user_profile\"", self.sidebar_qml)

    def test_system_button_row_profile_picture_has_edit_badge_and_click(self):
        system_row = self.sidebar_qml.split("component SystemButtonRow:", 1)[1]
        self.assertIn("id: pfpEditBadge", system_row)
        self.assertIn("visible: systemButtonRowRoot.editMode", system_row)
        self.assertIn("profileImagePicker.pick()", system_row)

    def test_no_borders_added(self):
        # Enforce project policy against borders in custom designs
        self.assertNotIn("border.width", self.sidebar_qml.split("id: bannerEditContainer", 1)[1].split("}", 1)[0])

    def test_edit_tooltips_only_visible_when_edit_mode_and_hovered(self):
        # Tooltips must not be permanently visible on dashboard open; they must require editMode and hover
        self.assertIn("extraVisibleCondition: headerRoot.editMode && wallpaperMouseArea.containsMouse", self.sidebar_qml)
        self.assertIn("extraVisibleCondition: headerRoot.editMode && profilePicMouseArea.containsMouse", self.sidebar_qml)
        self.assertIn("extraVisibleCondition: systemButtonRowRoot.editMode && profilePicMouseArea.containsMouse", self.sidebar_qml)


if __name__ == "__main__":
    unittest.main()
