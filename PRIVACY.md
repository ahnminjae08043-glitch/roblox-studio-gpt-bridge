# Roblox Studio Bridge Privacy Policy

Last updated: 2026-07-25

Roblox Studio Bridge processes commands that a user explicitly sends from a configured GPT to the user's paired Roblox Studio installation.

## Data processed

- A random Studio device identifier and authentication token.
- Temporary six-digit pairing codes.
- Command action names, command arguments, timestamps, results, and error messages.
- Basic service logs required for security and reliability.

The service does not require a Roblox password and must never request one.

## Purpose and retention

Data is used only to route commands to the correct paired Studio installation, return results, prevent unauthorized access, and diagnose failures. Pairing codes expire after ten minutes by default. Commands expire according to the configured command TTL. Production operators should delete operational logs within 30 days unless a shorter period is required.

## Sharing

Data is not sold. Hosting and infrastructure providers may process data solely to operate the service.

## Security and user control

Commands are separated by device identifier and authenticated with device-specific tokens. Studio mutations require approval unless the user enables Always Allow. Users can revoke access by clearing the plugin pairing or uninstalling the plugin.

## Contact

Replace this section before public release with the operator's support email and legal name.
