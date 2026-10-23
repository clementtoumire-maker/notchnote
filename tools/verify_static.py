#!/usr/bin/env python3
"""Static checks that run without Swift/Xcode (used by GATES.md)."""
import os, re, plistlib, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(root)
errors = []
swift = []
for d, _, fs in os.walk("NotchNote"):
    for f in fs:
        if f.endswith(".swift"):
            swift.append(os.path.join(d, f))

def strip(src):
    """Remove comments and string literals so bracket counting is meaningful."""
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    return src

for p in swift:
    s = strip(open(p, encoding="utf-8").read())
    for a, b in (("{", "}"), ("(", ")"), ("[", "]")):
        if s.count(a) != s.count(b):
            errors.append(f"{p}: unbalanced {a}{b} ({s.count(a)} vs {s.count(b)})")

# every Swift file is in the Xcode project
pbx = open("NotchNote.xcodeproj/project.pbxproj").read()
for p in swift:
    if os.path.basename(p) not in pbx:
        errors.append(f"{p}: missing from project.pbxproj")

# plists
info = plistlib.load(open("NotchNote/Resources/Info.plist", "rb"))
if info.get("LSUIElement") is not True: errors.append("LSUIElement must be true")
if "NSCalendarsFullAccessUsageDescription" not in info: errors.append("calendar usage string missing")
if info.get("LSMinimumSystemVersion") != "15.0": errors.append("LSMinimumSystemVersion must be 15.0")
ent = plistlib.load(open("NotchNote/Resources/NotchNote.entitlements", "rb"))
for k in ent:
    if "icloud" in k.lower() or "application-groups" in k or "aps-environment" in k:
        errors.append(f"entitlement {k} needs a paid account")
if "MACOSX_DEPLOYMENT_TARGET = \"15.0\"" not in pbx: errors.append("deployment target is not 15.0")
if 'CODE_SIGN_IDENTITY = "-"' not in pbx: errors.append("project is not set to ad-hoc signing")

# privacy promise: no networking code at all
net = re.compile(r"URLSession|URLRequest|NWConnection|CFNetwork|WKWebView|Data\(contentsOf: *URL\(string")
for p in swift:
    if net.search(strip(open(p, encoding="utf-8").read())):
        errors.append(f"{p}: networking API found (usage-data promise)")

# no paywall / limits
for p in swift:
    t = open(p, encoding="utf-8").read().lower()
    if re.search(r"\b(paywall|subscription|isPro|proOnly|taskLimit|maxTasks)\b".lower(), t):
        errors.append(f"{p}: paywall/limit identifier found")

# required feature symbols exist
required = {
  "NotchNote/Notch/NotchGeometry.swift": ["safeAreaInsets", "auxiliaryTopLeftArea"],
  "NotchNote/Notch/NotchPanels.swift": ["nonactivatingPanel", "constrainFrameRect", "registerForDraggedTypes"],
  "NotchNote/Notch/NotchController.swift": ["didChangeScreenParametersNotification", "NSHapticFeedbackManager"],
  "NotchNote/Editor/EditorTextView.swift": ["hasMarkedText", "shouldChangeText", "isUndoing"],
  "NotchNote/System/ReminderService.swift": ["screenIsLocked", "screensaver.didstart", "willSleepNotification", "UNUserNotificationCenter"],
  "NotchNote/System/SpotlightIndexer.swift": ["CSSearchableIndex"],
  "NotchNote/System/AddTaskIntent.swift": ["AppIntent", "AppShortcutsProvider"],
  "NotchNote/Model/TaskStore.swift": [".atomic", "trashItem"],
  "NotchNote/Model/AppSettings.swift": ["SMAppService"],
  "NotchNote/System/CalendarService.swift": ["requestFullAccessToEvents", "EKEventStoreChanged"],
}
for f, needles in required.items():
    t = open(f, encoding="utf-8").read()
    for n in needles:
        if n not in t: errors.append(f"{f}: expected '{n}'")

if errors:
    print("\n".join(errors)); sys.exit(1)
print(f"static verification passed ({len(swift)} swift files)")
