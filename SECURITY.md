# Security Policy

OpenHeal is a World of Warcraft addon. Security reports must be handled separately from ordinary bug reports.

## Supported versions

| Version | Supported |
| --- | --- |
| Latest published release | Yes |
| Current `main` branch | Best effort |
| Older releases | No |

Users should update to the latest published release before reporting a security issue.

## Reporting a vulnerability

Do **not** open a public issue containing vulnerability details, proof-of-concept code, credentials, account information, SavedVariables, or other sensitive data.

Use GitHub private vulnerability reporting:

1. Open the repository's **Security** tab.
2. Select **Advisories**.
3. Select **Report a vulnerability**.
4. Include the affected version, reproduction steps, impact, and any suggested mitigation.

If private vulnerability reporting is unavailable, contact the repository owner through their GitHub profile and request a private reporting channel. Do not publish technical details publicly.

## Response process

Reports are handled on a best-effort basis. The maintainer aims to:

- acknowledge a credible report within 7 days;
- assess severity and affected versions;
- prepare a fix before public disclosure when practical;
- credit the reporter unless anonymity is requested.

## Scope

Security issues may include:

- unauthorized collection or transmission of user data;
- execution of unintended code through addon-controlled inputs;
- malicious or compromised release artifacts;
- exposure of credentials, tokens, private data, or SavedVariables;
- unsafe external communication introduced by project tooling.

Normal Lua errors, gameplay behavior, performance problems, and expected World of Warcraft API restrictions belong in ordinary bug reports.

## Responsible disclosure

Allow reasonable time for investigation and remediation before public disclosure. Do not access data belonging to other users, disrupt services, or use a vulnerability beyond what is necessary to demonstrate it.
