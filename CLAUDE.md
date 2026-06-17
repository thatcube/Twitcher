# CLAUDE.md

Repository instructions for Claude-style agents.

## Branch policy (depends on whether a worktree is in use)

The correct branch behavior depends on how the repo is checked out. Determine
this first:

- **Worktree checkout** (e.g. the working directory lives under a
  `copilot-worktrees/` path, or git reports a linked worktree on a dedicated
  feature branch): you are on a per-session feature branch on purpose. This is
  the expected setup when using the GitHub Desktop app.
- **Direct `main` checkout** (the primary clone, currently on `main`): there is
  no feature branch.

### When working in a worktree (follow the normal feature-branch flow)

1. Stay on the worktree's existing feature branch — do not create additional
   branches or switch branches.
2. Commit and push to that feature branch.
3. To get changes onto `main`, merge the feature branch into `main` (a pull
   request is fine, or push the merge directly to the `main` ref). Do not check
   out `main` inside the worktree and do not edit the primary `main` checkout.

### When working directly on `main` (single-branch behavior)

1. Do not create new branches.
2. Do not switch branches.
3. Do not suggest branch-based workflows unless the user explicitly asks.
4. Commit and push only to `main`.

If a branch change is required in either mode, ask the user first.

## Deploy-to-device rule (always)

After any code change that is successfully built, always deploy and launch the latest build on the paired Apple TV for immediate user testing.

Required sequence:

1. Build.
2. Install latest app bundle on Apple TV.
3. Launch app on Apple TV.
4. Report deployment outcome.

Critical detail:
- For Apple TV testing, always run a fresh device build immediately before install:
	`xcodebuild -project Twizz.xcodeproj -scheme Twizz -destination "platform=tvOS,id=<DEVICE_ID>" build`
- Do not rely on `CODESIGNING_FOLDER_PATH` install alone without that build step, or an older app binary can be installed.

## Apple TV target

- Device ID: `DE913871-CC2D-5F75-B4F2-0D6F44AA30DE`

## Recommended install/launch command

```bash
DEVICE_ID='DE913871-CC2D-5F75-B4F2-0D6F44AA30DE' && \
APP_PATH=$(xcodebuild -project Twizz.xcodeproj -scheme Twizz -destination "platform=tvOS,id=$DEVICE_ID" -showBuildSettings | awk -F' = ' '/CODESIGNING_FOLDER_PATH/ {print $2; exit}') && \
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist") && \
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" && \
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"
```

## Git workflow

Agents must not leave local commits unpushed when finishing a task.

Required completion rule:
1. After making requested file changes, create one commit that includes all requested files for that task.
2. Push that commit to the currently checked out branch before ending the task.
3. Report the pushed commit hash in the response.
4. If the user explicitly says not to push, skip push and state that clearly.

When the user asks to merge into `main`:
- In a **worktree**, merge the feature branch into `main` (PR or a direct push
  to the `main` ref) without switching the worktree's branch or touching the
  primary `main` checkout.
- On a **direct `main` checkout**, the work is already on `main` once pushed.

## Completion checklist (do not skip)

Before ending any task that edits files in this repo, the agent must do all of the following in the same turn:

1. Run a fresh Apple TV device build.
2. Install the newly built app on Apple TV.
3. Launch the app on Apple TV.
4. Report all three outcomes explicitly in the response.
5. If any step fails, state the failure and stop claiming deployment is complete.
