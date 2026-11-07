/// MithkaX ships every feature unlocked in self-built binaries.
///
/// Upstream gates contributions that violate Telegram API Terms of Service
/// §1.4 behind a compile-time constant; this fork opts in by default and the
/// CI build no longer overrides it.
const allowTelegramTosViolations = bool.fromEnvironment(
  'I_DONT_FUCKING_CARE_ABOUT_TOS',
  defaultValue: true,
);
