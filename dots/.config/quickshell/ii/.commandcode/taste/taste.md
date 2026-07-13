# Taste (Continuously Learned by [CommandCode][cmd])

[cmd]: https://commandcode.ai/

# qml-architecture
See [qml-architecture/taste.md](qml-architecture/taste.md)

# debugging
- When debugging QuickShell (qs) or other configs, execute commands directly yourself instead of asking the user to run them and report output. Confidence: 0.70

# qml
- For RowLayout items with dynamic visibility and an associated text/toggle expression, extract the expression into a readonly property (e.g., `iconText`) and bind `visible: propertyName !== ""` instead of using the text expression directly in `visible`. This prevents items from occupying layout space when `visible: true` but `text: ""`. Confidence: 0.85
