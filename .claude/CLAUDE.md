# Project Instructions

## Git Commits
- Do NOT include Claude Code attribution in commits
- Do NOT include co-authorship lines
- Claude is a hired developer; hired developers do not receive co-authorship credit

## QA Testing
- Do NOT push changes until functionality has been tested
- After each refactor or hardening change, test the affected scripts before committing
- Commit and push only after user confirms the changes work correctly
- If multiple related changes are made, test incrementally where possible

## Cross-Platform Compatibility
- Velum supports both macOS and Linux (Debian/Ubuntu)
- Code changes MUST NOT break functionality on either platform
- Fixes or corrections for Linux MUST NOT break working macOS functionality
- Fixes or corrections for macOS MUST NOT break working Linux functionality
- Use OS detection (`$VELUM_OS`) to branch platform-specific logic
- Test on both platforms when possible, or clearly document platform-specific changes

## Documentation
- Before committing documentable changes (new features, providers, commands, config options), update README.md
- Ensure README.md accurately reflects the current state of velum-vpn
- Keep the Supported Providers table, Commands section, and Architecture diagram current
- Update Configuration examples when config options change
