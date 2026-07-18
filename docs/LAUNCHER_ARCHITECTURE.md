# Архитектура launcher

Blacked Aeronautics распространяет готовый Windows launcher на базе ElyPrism/PineconeMC.
Большая часть upstream launcher binary не хранится в Git; репозиторий содержит template,
custom updater, installer metadata и воспроизводимые build scripts.

## Поток сборки

1. `scripts/build-updater.ps1` компилирует `updater/BlackedAeronauticsUpdater.cs`.
2. `scripts/build-portable.ps1` копирует локальные ElyPrism и JDK inputs, накладывает
   `launcher-template/` и создаёт distribution manifest.
3. `scripts/build-setup.ps1` использует Portable content и `installer/` для Setup.
4. Maintainer публикует Setup и Portable как assets тега `vX.Y.Z-ely.N`.

Ignored local inputs не являются source of truth и не должны попадать в commits.

## Обновление launcher

Custom updater проверяет latest non-draft/non-prerelease GitHub Release, сравнивает версии,
выбирает asset для текущего distribution type и безопасно применяет manifest. Seed-файлы не
заменяют пользовательские настройки, unmanaged files сохраняются.

Updater также:

- синхронизирует NeoForge из опубликованного `pack.toml`;
- мигрирует старую packwiz pre-launch command;
- поддерживает Setup и Portable layouts;
- сохраняет Unicode и spaced paths;
- удаляет только managed files, исчезнувшие из нового manifest.

## Обновление pack

Перед запуском игры `launcher-template/instances/Blacked-Aeronautics/minecraft/packwiz-update.ps1`
запускает bundled packwiz installer. Сначала используется GitHub Pages, затем CDN mirror.
Неполная первая попытка повторяется автоматически.

Pack публикуется отдельно от launcher releases. Поэтому pack-only change не требует новой
версии Setup или Portable.

## Границы ответственности

- Pack content: `pack/` и pack scripts.
- Launcher distribution: `launcher-template/`, `installer/` и build scripts.
- Update engine: `updater/` и `scripts/test-updater.ps1`.
- Production pack deployment: `.github/workflows/pages.yml`.
- PR policy and Windows regression tests: `.github/workflows/governance.yml`.
