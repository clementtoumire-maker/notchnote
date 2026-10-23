# Status

| Item | State |
|---|---|
| Sources for all 6 stages written | done |
| Static checks (`python3 tools/verify_static.py`) | pass |
| `make test` (Markdown logic) | NOT RUN, no Swift toolchain where this was written |
| `xcodebuild` build | NOT RUN |
| On-hardware behaviour | NOT RUN |

## First build checklist
1. `make test`
2. `make build` (or open the project in Xcode, scheme NotchNote, My Mac, ⌘R)
3. If there are compile errors, copy the first 20 lines of `xcodebuild` output back to Claude; fix, repeat.
4. `make install`
5. Walk through: hover the notch; type `- [ ] ` and press Return; ⌘Z; ⌘⇧S; drag text onto the notch; Settings → send test reminder.
