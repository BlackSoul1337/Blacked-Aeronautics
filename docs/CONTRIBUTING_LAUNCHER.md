# Contributions в launcher

Launcher changes влияют на обновление, установку и пользовательские файлы. Перед реализацией
создайте launcher issue и получите подтверждение maintainer, что подход и scope подходят проекту.

Сначала прочитайте [архитектуру launcher](LAUNCHER_ARCHITECTURE.md).

## Области

- `updater/` — C# updater и безопасное применение launcher releases.
- `launcher-template/` — ElyPrism instance, update command и bundled metadata.
- `installer/` — Inno Setup.
- `scripts/build-updater.ps1` — сборка updater.
- `scripts/build-portable.ps1` — создание Portable distribution.
- `scripts/build-setup.ps1` — создание Setup.
- `scripts/test-updater.ps1` — regression tests updater и packwiz fallback.

Не коммитьте локальные ElyPrism/JDK inputs, `dist/`, `devs/`, archives или accounts.

## Требования

- Сохраняйте пользовательские accounts, settings и unmanaged files.
- Проверяйте Setup и Portable paths, пути с пробелами и Unicode.
- Не ослабляйте TLS, hash, manifest, path traversal и process-boundary проверки.
- Сохраняйте fallback pack delivery и автоматический retry неполного первого обновления.
- Переиспользуйте существующую updater/build логику вместо параллельной реализации.
- Не меняйте release version без согласованной launcher release-задачи.

## Проверка

Минимальная обязательная команда:

```powershell
.\scripts\test-updater.ps1
```

GitHub Actions запускает тот же suite на Windows с Temurin Java 21, если PR меняет updater,
launcher template, installer или build/test scripts.

Полные Setup и Portable builds требуют локальных ignored inputs и выполняются maintainer перед
launcher release. Укажите в PR, какие из них удалось проверить.

## Pull Request

Обычная launcher feature создаётся от `develop` и направляется обратно в `develop`. В PR:

- свяжите согласованную issue;
- опишите user impact, migration и rollback;
- перечислите изменённые user-owned files или подтвердите, что их нет;
- приложите результаты updater tests;
- отдельно укажите Setup/Portable testing.

Security и update-integrity изменения получают обязательный high-effort review.
