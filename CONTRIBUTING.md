# Contributing to OpenHeal

Thank you for contributing to OpenHeal.

## Before you start

- Search existing issues and pull requests.
- Use an issue for substantial behavior changes before investing in a large implementation.
- Keep each pull request limited to one logical change.
- Never include credentials, Battle.net account data, private combat logs, or personal SavedVariables.

## Development workflow

1. Fork the repository.
2. Create a branch from `main`.
3. Make the smallest practical change.
4. Test the affected behavior in the current World of Warcraft Retail client.
5. Confirm that the addon loads without new Lua errors.
6. Update documentation and `OpenHeal/CHANGELOG.md` when user-visible behavior changes.
7. Open a pull request using the repository template.

## Lua and WoW API expectations

- Avoid globals unless the WoW API requires them.
- Keep secure-frame and combat-lockdown behavior explicit.
- Do not work around protected-action restrictions in ways that cause taint.
- Validate user-controlled and SavedVariables values before using them.
- Do not silently delete or rewrite user configuration.
- Keep event handlers and combat-sensitive paths small and predictable.
- Do not add telemetry, analytics, remote communication, or data collection without prior maintainer approval and prominent documentation.
- Prefer compatibility with the Lua version and API behavior used by the current WoW Retail client.

## Testing expectations

At minimum, test:

- login or `/reload` initialization;
- opening relevant settings;
- affected functionality both in and out of combat where applicable;
- group and raid behavior if unit frames are affected;
- fresh SavedVariables and an existing configuration;
- absence of new Lua errors.

Describe the exact tests in the pull request. Screenshots are useful for visual changes but do not replace reproduction steps.

## Commit and pull request quality

Use clear imperative commit messages, for example:

- `fix: preserve frame position after reload`
- `feat: add configurable aura size`
- `docs: clarify installation path`

Pull requests should explain the problem, the chosen solution, risks, and testing. Generated archives and local development files must not be committed.

## Licensing

By submitting a contribution, you agree that it is licensed under the GNU General Public License version 3 only (`GPL-3.0-only`). You must have the right to submit every included code, media, and data file.

Third-party material must retain required copyright and license notices and must be compatible with GPL-3.0-only.