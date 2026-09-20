#!/usr/bin/env python3
import os
import re
import sys

BASE_DIR = os.path.expanduser("/home/pedro/.config/quickshell/ii/modules/common/quickToggles/androidStyle")
CATALOG_PATH = os.path.join(BASE_DIR, "QuickToggleCatalog.js")
PREVIEW_PATH = os.path.join(BASE_DIR, "QuickToggleTrayPreview.qml")
CHOOSER_PATH = os.path.join(BASE_DIR, "AndroidToggleDelegateChooser.qml")
BATTERY_DIR = os.path.join(BASE_DIR, "battery")

BATTERY_VARIANTS = [
    "bluetoothBatteryWidget",
    "mobileBatteryWidget",
    "bluetoothHeadphoneCookieWidget",
    "pcBatteryBarsWidget",
    "pcBatteryCableWidget",
    "devicesBatteryListWidget",
    "bluetoothEarbudsStemWidget"
]

NEW_QML_FILES = {
    "bluetoothBatteryWidget": "AndroidBluetoothBatteryToggle.qml",
    "mobileBatteryWidget": "AndroidMobileBatteryToggle.qml",
    "bluetoothHeadphoneCookieWidget": "AndroidBluetoothHeadphoneCookieToggle.qml",
    "pcBatteryBarsWidget": "AndroidPcBatteryBarsToggle.qml",
    "pcBatteryCableWidget": "AndroidPcBatteryCableToggle.qml",
    "devicesBatteryListWidget": "AndroidDevicesBatteryListToggle.qml",
    "bluetoothEarbudsStemWidget": "AndroidBluetoothEarbudsStemToggle.qml"
}

def check_file_exists(path):
    if not os.path.isfile(path):
        print(f"FAIL: File not found: {path}")
        return False
    print(f"PASS: Found file: {path}")
    return True

def check_braces_balance(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    i = 0
    n = len(content)
    counts = {"{": 0, "}": 0, "(": 0, ")": 0, "[": 0, "]": 0}

    while i < n:
        c = content[i]
        # Line comment
        if c == "/" and i + 1 < n and content[i + 1] == "/":
            while i < n and content[i] != "\n":
                i += 1
            continue
        # Block comment
        if c == "/" and i + 1 < n and content[i + 1] == "*":
            i += 2
            while i + 1 < n and not (content[i] == "*" and content[i + 1] == "/"):
                i += 1
            i += 2
            continue
        # Single quote string
        if c == "'":
            i += 1
            while i < n and content[i] != "'":
                if content[i] == "\\":
                    i += 1
                i += 1
            i += 1
            continue
        # Double quote string
        if c == '"':
            i += 1
            while i < n and content[i] != '"':
                if content[i] == "\\":
                    i += 1
                i += 1
            i += 1
            continue
        # Backtick string
        if c == '`':
            i += 1
            while i < n and content[i] != '`':
                if content[i] == "\\":
                    i += 1
                i += 1
            i += 1
            continue

        if c in counts:
            counts[c] += 1
        i += 1

    if counts["{"] != counts["}"]:
        print(f"FAIL: {path} mismatched braces: {counts['{']} != {counts['}']}")
        return False
    if counts["("] != counts[")"]:
        print(f"FAIL: {path} mismatched parentheses: {counts['(']} != {counts[')']}")
        return False
    if counts["["] != counts["]"]:
        print(f"FAIL: {path} mismatched brackets: {counts['[']} != {counts[']']}")
        return False

    print(f"PASS: {path} braces and brackets balanced.")
    return True

def test_catalog():
    print("\n--- Testing QuickToggleCatalog.js ---")
    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    for variant in BATTERY_VARIANTS:
        pattern = rf"{variant}:\s*\{{[^}}]*variantGroup:\s*\"battery\""
        if not re.search(pattern, content, re.DOTALL):
            print(f"FAIL: {variant} not configured with variantGroup: 'battery' in TOGGLE_TYPES")
            return False
        print(f"PASS: {variant} has variantGroup: 'battery' in TOGGLE_TYPES")

    # Check canonical mappings
    aliases = [
        ("bluetoothBattery", "bluetoothBatteryWidget"),
        ("mobileBattery", "mobileBatteryWidget"),
        ("bluetoothHeadphoneCookie", "bluetoothHeadphoneCookieWidget"),
        ("pcBatteryBars", "pcBatteryBarsWidget"),
        ("pcBatteryCable", "pcBatteryCableWidget"),
        ("devicesBatteryList", "devicesBatteryListWidget"),
        ("bluetoothEarbudsStem", "bluetoothEarbudsStemWidget"),
    ]
    for alias, target in aliases:
        if alias not in content or target not in content:
            print(f"FAIL: alias {alias} -> {target} not found in canonicalType()")
            return False
        print(f"PASS: canonicalType() handles {alias} -> {target}")

    return True

def test_preview():
    print("\n--- Testing QuickToggleTrayPreview.qml ---")
    with open(PREVIEW_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    for variant in BATTERY_VARIANTS:
        if variant not in content:
            print(f"FAIL: {variant} missing from QuickToggleTrayPreview meta mapping")
            return False
        print(f"PASS: {variant} present in QuickToggleTrayPreview meta")

    return True

def test_chooser():
    print("\n--- Testing AndroidToggleDelegateChooser.qml ---")
    with open(CHOOSER_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    if "import qs.modules.common.quickToggles.androidStyle.battery" not in content:
        print("FAIL: battery directory import missing in AndroidToggleDelegateChooser.qml")
        return False
    print("PASS: battery import present in AndroidToggleDelegateChooser.qml")

    for variant in BATTERY_VARIANTS:
        pattern = rf'roleValue:\s*"{variant}"'
        if not re.search(pattern, content):
            print(f"FAIL: DelegateChoice for {variant} missing in AndroidToggleDelegateChooser.qml")
            return False
        print(f"PASS: DelegateChoice for {variant} present in AndroidToggleDelegateChooser.qml")

    return True

def test_new_qml_files():
    print("\n--- Testing new QML files ---")
    for variant, filename in NEW_QML_FILES.items():
        filepath = os.path.join(BATTERY_DIR, filename)
        if not check_file_exists(filepath):
            return False
        if not check_braces_balance(filepath):
            return False

        with open(filepath, "r", encoding="utf-8") as f:
            code = f.read()

        if "AndroidWidgetTileBase" not in code:
            print(f"FAIL: {filename} does not inherit AndroidWidgetTileBase")
            return False
        print(f"PASS: {filename} inherits AndroidWidgetTileBase")

    return True

def main():
    passed = True
    passed = passed and test_catalog()
    passed = passed and test_preview()
    passed = passed and test_chooser()
    passed = passed and test_new_qml_files()

    if passed:
        print("\nAll Battery Quick Toggle contract tests passed successfully!")
        sys.exit(0)
    else:
        print("\nSome tests failed.")
        sys.exit(1)

if __name__ == "__main__":
    main()
