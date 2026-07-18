# Blacked Aeronautics agent guidance

## Repository map

- `pack/` contains the published packwiz pack, mod metadata, and sanitized configuration.
- `updater/` contains the custom C# launcher updater.
- `launcher-template/` contains the distributable ElyPrism instance template.
- `installer/` and `scripts/build-*.ps1` create Setup and Portable launcher artifacts.
- `scripts/import-pack.ps1` imports the maintainer's Prism source instance.
- `.github/workflows/pages.yml` publishes the pack from `main`.

The Prism source instance at
`E:\Prism\PrismLauncher\instances\Aeronautics - Create Customised` is read-only.
Never write to it.

## Safety and pack rules

- Preserve unrelated user changes and inspect the exact diff before staging.
- Never publish accounts, worlds, servers, logs, backups, local paths, voice identity data,
  Quick Skin uploads, e4mc, `mods.rar`, or generated debug/cache data.
- Store Modrinth mods as `.pw.toml` metadata. Do not commit a JAR unless its source and
  redistribution license were explicitly reviewed and its hash was added to validation.
- A pack-only update does not create launcher artifacts, tags, or GitHub Releases.
- Run `scripts/refresh-pack.ps1` and `scripts/validate-pack.ps1` for pack changes.
- Run `scripts/test-updater.ps1` when updater, launcher template, build, installer, or
  NeoForge synchronization logic changes.

## Gitflow

- `main` is production. It accepts `release` promotions and `hotfix/*` PRs.
- `develop` is the default integration branch. Branch `feature/*`, `docs/*`, and
  `chore/*` from it and merge them back through PRs.
- `release` is the permanent staging branch. Promote `develop` into it and branch
  `bugfix/*` from it.
- After a release bugfix, merge `release` back into `develop`.
- After a hotfix, merge `main` into `release` and then `release` into `develop`.
- Squash short working branches. Use merge commits for long-lived branch promotion and
  back-synchronization.
- Do not force-push or delete `main`, `release`, or `develop`.

## Commits and pull requests

Use `<type>(<scope>)!?: <English imperative or present-tense subject>`.

- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
  `ci`, `chore`, `revert`.
- Required scopes: `repo`, `pack`, `launcher`, `updater`, `installer`, `release`,
  `ci`, `deps`.
- Use English only and never use past tense.
- Do not end the subject with punctuation.
- Keep the header and every body/footer line at 100 characters or fewer.
- Keep PR titles in the same format.
- Keep PRs small and limited to one coherent outcome.

Run `scripts/validate-commit-policy.ps1 -TestFixtures` after changing policy rules.

## Engineering practice

- Before adding code, search for existing equivalent behavior and reuse or extend it.
- Prefer editing the existing owner of a behavior over creating a parallel implementation.
- Remove dead code encountered in the changed path only when removal is safe and in scope.
- Plan cross-subsystem, security-sensitive, release, and migration work before implementation.
- Validate the smallest relevant surface first, then run the full required checks.
- Do not stage `dist/`, `devs/`, `.tools/`, ElyPrism binaries, the JDK, archives,
  accounts, or unrelated changes.

## Project agents

Use project agents only for concrete, bounded roles:

- `planner`: architecture, release, security, migration, and multi-step planning.
- `pack-worker`: packwiz metadata, mods, configuration, sanitization, and pack validation.
- `launcher-worker`: updater, launcher template, installer, and build implementation.
- `reviewer`: correctness, security, regression, test, and maintainability review.

The root agent owns Git state, commits, pushes, PRs, and final integration. Delegate independent
read-heavy or implementation work only when it materially improves the task. Do not let agents
edit the same files concurrently.
