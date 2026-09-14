"""Contracts for the wallpaper sorting system in services/Wallpapers.qml."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WALLPAPERS_SERVICE = (ROOT / "services/Wallpapers.qml").read_text()


class WallpapersSortingContractTests(unittest.TestCase):
    def test_reads_qt6_file_modified_role(self):
        """Wallpapers.qml must query Qt 6 'fileModified' role with fallback to fileLastModified."""
        self.assertIn(
            'folderModel.get(i, "fileModified") ?? folderModel.get(i, "fileLastModified")',
            WALLPAPERS_SERVICE,
        )

    def test_uses_qt6_file_url_role(self):
        """Wallpapers.qml must query Qt 6 'fileUrl' role with fallback to fileURL."""
        self.assertIn(
            'folderModel.get(i, "fileUrl") || folderModel.get(i, "fileURL")',
            WALLPAPERS_SERVICE,
        )

    def test_normalizes_seconds_to_milliseconds(self):
        """normalizeDateValue must scale Unix seconds (< 10000000000) to milliseconds."""
        self.assertIn(
            "(value > 0 && value < 10000000000) ? value * 1000 : value",
            WALLPAPERS_SERVICE,
        )

    def test_creation_times_scales_seconds_to_milliseconds(self):
        """creationTimesProc must convert birth time seconds to milliseconds."""
        self.assertIn(
            "value < 10000000000 ? value * 1000 : value",
            WALLPAPERS_SERVICE,
        )

    def test_keeps_directories_at_top(self):
        """entries.sort must keep directories grouped at the top."""
        self.assertIn(
            "if (left.fileIsDir !== right.fileIsDir) {",
            WALLPAPERS_SERVICE,
        )
        self.assertIn(
            "return left.fileIsDir ? -1 : 1;",
            WALLPAPERS_SERVICE,
        )

    def test_descending_default_for_numeric_sort(self):
        """Default order for numeric fields (modified date, created date, size) must be descending (newest/largest first)."""
        self.assertIn(
            "if (leftValue > rightValue) {",
            WALLPAPERS_SERVICE,
        )
        self.assertIn(
            "comparison = -1;",
            WALLPAPERS_SERVICE,
        )
        self.assertIn(
            "else if (leftValue < rightValue) {",
            WALLPAPERS_SERVICE,
        )
        self.assertIn(
            "comparison = 1;",
            WALLPAPERS_SERVICE,
        )

    def test_reverses_sort_when_sort_reversed_active(self):
        """entries.sort must invert comparison when root.sortReversed is true."""
        self.assertIn(
            "if (root.sortReversed) {",
            WALLPAPERS_SERVICE,
        )
        self.assertIn(
            "comparison = -comparison;",
            WALLPAPERS_SERVICE,
        )

    def test_folder_model_refreshes_on_ready_status(self):
        """folderModel must only queue refresh when status is FolderListModel.Ready."""
        self.assertIn(
            "if (folderModel.status === FolderListModel.Ready) {",
            WALLPAPERS_SERVICE,
        )


if __name__ == "__main__":
    unittest.main()
