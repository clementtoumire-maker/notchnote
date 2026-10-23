# Gates: NotchNote

OWNS: NotchNote/**, NotchNote.xcodeproj/**, scripts/**, tools/**, tests/**, docs/**, README.md, Makefile

Scope: a macOS 15+ menu-bar notch notepad (GlideNote clone, no paywall) that builds with a free personal Apple ID.

- [x] G1: static structure is sound (balanced braces, all sources in the Xcode project, plists valid, ad-hoc signing, no paid entitlements, no networking, no paywall identifiers, key APIs present)
  CHECK: python3 tools/verify_static.py
  EXPECT: static verification passed
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/home/claude/NotchNote-project; path=14bdffb0e8ca/16 entries; output=static verification passed (18 swift files)

- [x] G2: README documents xcodebuild steps, Xcode GUI steps, one-command install and the honest verification status
  CHECK: python3 tools/verify_readme.py
  EXPECT: readme verification passed
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/home/claude/NotchNote-project; path=14bdffb0e8ca/16 entries; output=readme verification passed

- [ ] G3: the project compiles with the current stable Xcode (xcodebuild exits 0 on the user's Mac)
  EVIDENCE: pending

- [ ] G4: Markdown logic self-tests pass when compiled and run with swiftc on the user's Mac
  EVIDENCE: pending

- [ ] G5: hover spring, haptic tick, notch alignment, clamshell, drag-to-notch and IME behaviour are confirmed on real hardware by the user
  EVIDENCE: pending

ABANDON: G3 no Swift/Xcode/macOS available in the authoring sandbox and the Mac link dropped before a build could be run; handoff: run `make build` and send back errors (STATUS.md)
ABANDON: G4 same reason; handoff: run `make test`
ABANDON: G5 needs real hardware; handoff: STATUS.md walkthrough step 5
