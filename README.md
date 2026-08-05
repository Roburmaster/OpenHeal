# OpenHeal

OpenHeal is an open-source healing addon for World of Warcraft Retail. The addon provides configurable healing frames and related healer-focused interface modules.

> OpenHeal is an independent community project and is not affiliated with or endorsed by Blizzard Entertainment.

## Project status

OpenHeal is under active development. Interfaces, configuration, and SavedVariables may change between pre-release versions. Back up your settings before testing development builds.

## Installation

1. Download the latest release archive from GitHub Releases.
2. Extract the archive so the addon folder is named `OpenHeal`.
3. Place it in:
   `World of Warcraft/_retail_/Interface/AddOns/`
4. Restart World of Warcraft or reload the UI.

The final path must contain `OpenHeal/OpenHeal.toc`.

## Development installation

Clone the repository and copy or link the repository's `OpenHeal` directory into the Retail AddOns directory. The repository root itself is not the addon folder.

## Reporting problems

Use the GitHub issue templates and include:

- OpenHeal version or commit;
- World of Warcraft client version;
- character class and specialization;
- exact reproduction steps;
- the complete first Lua error and stack trace;
- whether the problem occurs in combat, out of combat, or both.

Do not post account data, credentials, private combat logs, or SavedVariables containing personal information.

Security vulnerabilities must be reported privately as described in [SECURITY.md](SECURITY.md).

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), follow the [Code of Conduct](CODE_OF_CONDUCT.md), and keep pull requests focused and testable.

## Releases

Release tags use semantic-looking version tags such as `v1.0.0`. A tagged release packages only the `OpenHeal` addon directory into an installable zip archive.

## License

OpenHeal is licensed under the GNU General Public License version 3 only (`GPL-3.0-only`). See [LICENSE](LICENSE).

World of Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. All third-party names and assets remain the property of their respective owners.