# qml-architecture
- For list views with animated reordering, use a persistent slot pattern: Item wrapper (with ListView-compatible API properties) → Flickable → Repeater of stable Item delegates with uniqueId, currentPosition, hasData, and imperative yPos calculations. Confidence: 0.70
- Each slot delegate must have Behavior on y (220ms, emphasized curve), height, and opacity for smooth reordering animations. Disable y animation during initial population with positionAnimationEnabled flag. Confidence: 0.70
- Use uniqueId (raw entry string or MAC address) and slotData via a map (e.g., bluetoothDeviceMap) for stable slot-data bindings that survive list filtering/reordering. Confidence: 0.70
- Replay entry animation (opacity/scale/translate) only when hasData changes from false to true via Connections onHasDataChanged, not on every position change. Confidence: 0.70
- Use a posDebounce Timer (260ms) triggered by onHeightChanged on slots to recalculate positions after layout animations settle. Confidence: 0.70
- Use Qt.callLater for initial updateSlots() calls to ensure Repeater is ready before slot manipulation. Confidence: 0.70
