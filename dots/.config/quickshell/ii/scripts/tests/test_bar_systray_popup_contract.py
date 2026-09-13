from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
TRAY_DIR = ROOT / "modules/ii/bar/widgets/tray"


class BarSysTrayPopupContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def test_systray_overflow_popup_synchronization(self):
        content = (TRAY_DIR / "SysTray.qml").read_text(encoding="utf-8")

        # 1. Overflow popup uses touchToggle: false to avoid double toggling with downAction
        self.assertIn("touchToggle: false", content)

        # 2. _clickActive is synchronized with sysTrayRoot.trayOverflowOpen
        self.assertIn("_clickActive: sysTrayRoot.trayOverflowOpen", content)
        self.assertIn("overflowPopup._clickActive = true", content)
        self.assertIn("overflowPopup.close()", content)

        # 3. active uses standard StyledPopup computed active and closing state
        self.assertIn("active: sysTrayRoot.unpinnedItems.length > 0 && (_computedActive || _isClosing)", content)

        # 4. trayOverflowLayout doesn't hide contents behind failing opacity: 0.0 or startAnim
        self.assertNotIn('readonly property bool startAnim: overflowPopup.opened', content)
        self.assertNotIn('opacity: 0.0\n                    scale: 0.85', content)

        # 5. releaseFocus does not clear focus grab while trayOverflowOpen is true
        self.assertIn("if (!sysTrayRoot.trayOverflowOpen)", content)


if __name__ == "__main__":
    unittest.main()
