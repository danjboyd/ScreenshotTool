# Working Process

This document captures the current handoff contract between Codex (engineering) and the user (architect/tester). Every session should follow these steps unless we explicitly agree to change them.

## Developer Workflow (Codex)
1. **Finish the code change.** Keep work in small, reviewable chunks.
2. **Build the GNUstep target:**  
   ```bash
   make -j"$(nproc)"
   ```
   Fix any build failures before moving to the next step.
3. **Run the regression suite:**  
   ```bash
   Tools/run_tests.sh
   ```
   All probes must pass before requesting manual testing. If tests become obsolete or redundant, delete or update them immediately so the suite stays lean and relevant.
4. **Prepare the app for manual testing:**
   - Truncate both runtime logs so the next launch starts fresh:
     ```bash
     : > ./debug.log
     : > ./screenshottool.log
     ```
   - Only after build + tests succeed should you ask the user to run the app.
5. **Packaging (release builds):**  
   Follow `docs/Packaging.md` for AppImage/DMG creation so local releases match CI artifacts.

## User Workflow (Testing Hand-off)
1. Launch the freshly-built app with the standardized scenario and capture logs:
   ```bash
   openapp ./ScreenshotTool.app/ \
           ~/Pictures/Screenshots/Screenshot\ from\ 2025-10-23\ 11-00-05.png \
           2>&1 | tee ./debug.log
   ```
2. Report findings referencing timestamps/sections in `./debug.log` so Codex can cross-check quickly.

## Continuous Maintenance
- Revisit the regression suite regularly and prune tests that no longer reflect the product’s behaviour or have overlapping coverage.
- Update this document whenever the handoff expectations or tooling change, keeping it the single source of truth for our process.
