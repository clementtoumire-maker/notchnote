# Switching to CloudKit later

Sync today = plain JSON files in a folder you choose (`<folder>/NotchNote/<uuid>.json`). Put that folder in
iCloud Drive and your Macs stay in sync, no paid account needed.

CloudKit needs a paid Apple Developer Program membership (iCloud container + provisioning profile). When you have one:

1. Xcode → target NotchNote → Signing & Capabilities → select your Team → **+ Capability → iCloud → CloudKit**,
   add a container (e.g. `iCloud.com.clement.NotchNote`).
2. Replace `NotchNote.entitlements` with the one Xcode generates, and set `CODE_SIGN_STYLE = Automatic` plus your `DEVELOPMENT_TEAM`.
3. Add a `CloudKitSyncBackend` that mirrors `TaskStore`'s three storage touch-points:
   - `readDirectory(_:location:)` → `CKQuery` on record type `NoteTask` (fields = the keys in `NoteTask.CodingKeys`)
   - `writeAtomically(_:to:)` in `flush()` → `CKModifyRecordsOperation` (savePolicy `.changedKeys`)
   - `startWatchingSync()` → `CKDatabaseSubscription` + silent-push handler calling `reloadSync()`
4. `StorageLocation.sync` already means "belongs to the shared store", so the UI (move local ⇄ sync, sync icon) needs no change.
   Conflict rule today is last-writer-wins on `updatedAt`; keep it, or use `CKRecord.recordChangeTag`.
