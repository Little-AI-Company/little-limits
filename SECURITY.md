# Security policy

Little Limits keeps Claude and Codex sign-ins in your Keychain and reads local Claude Code and Codex logs, so security reports matter here.

## Report a vulnerability

Report it privately through [GitHub security advisories](https://github.com/Little-AI-Company/little-limits/security/advisories/new). Do not open a public issue. Include the app version, the steps to reproduce it, and what an attacker gains.

Fixes ship in a new release and in the Homebrew cask. There is no automatic updater, so the release notes say when an update matters for security.

## In scope

- A token, OAuth grant, cookie, or Keychain item written to disk, a log, or the usage history database.
- Prompts, replies, tool output, file contents, command text, or folder names stored in the usage history, which keeps derived facts only.
- One account's credential or reading used for another account, or the app changing your Claude Code or Codex CLI login.
- The Claude status-line capture helper running anything other than your previous status-line command.
- Network requests to anywhere other than the provider endpoints the app reads.

## Out of scope

- Changes in the private Claude and Claude Console endpoints the app reads. They are undocumented and can change without notice; report a broken reading as a bug.
- Anyone who can already run code as your macOS user or unlock your Keychain.
- Builds you package yourself with ad hoc or development signing.
