"""Verify the embedded device widget is linked as an app extension."""
from pathlib import Path
import plistlib
import struct
import sys

app = Path(sys.argv[1])
parent = plistlib.loads((app / "Info.plist").read_bytes())
widget = app / "PlugIns/JourneyWidget.appex"
info = plistlib.loads((widget / "Info.plist").read_bytes())
assert info["CFBundleIdentifier"].startswith(parent["CFBundleIdentifier"] + ".")
assert info["CFBundleVersion"] == parent["CFBundleVersion"]
assert info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
header = (widget / info["CFBundleExecutable"]).read_bytes()[:32]
magic, cpu, _, file_type, _, _, flags, _ = struct.unpack("<8I", header)
assert magic == 0xFEEDFACF and cpu == 0x0100000C and file_type == 2
binary = (widget / info["CFBundleExecutable"]).read_bytes()
assert b"_NSExtensionMain\x00" in binary, "Widget is missing the Foundation extension entry point"
print("Embedded widget identity, version, arm64 executable and Foundation extension entry point verified")
