# Contributions в pack

Этот путь предназначен для модов, packwiz metadata, KubeJS, resource packs, datapacks и
санитизированной игровой конфигурации.

## Предложить мод

1. Создайте issue через форму **Предложить мод**.
2. Укажите Modrinth URL, версию Minecraft/NeoForge, dependencies, client/server side,
   лицензию и причину добавления.
3. Опишите влияние на загрузку, производительность, миры и существующие моды.
4. Дождитесь одобрения maintainer до подготовки PR, если мод отсутствует на Modrinth или
   требует raw JAR.

Предпочтительный вариант — `pack/mods/*.pw.toml` с точным Modrinth download URL и hashes.
Не добавляйте скачанный JAR рядом с `.pw.toml`.

Raw JAR разрешён только после отдельной проверки source, лицензии и redistribution rights.
Maintainer добавляет approved filename и SHA-512 в `scripts/validate-pack.ps1`. Не считайте
доступность файла в интернете разрешением на его распространение.

## Приватные и локальные данные

Никогда не добавляйте:

- `e4mc` и `mods.rar`;
- worlds, accounts, `servers.dat`, logs и backups;
- абсолютные локальные пути;
- voice-chat identity/cache и device selection;
- Quick Skin uploads и активные личные skin hashes;
- Distant Horizons server data;
- KubeJS secrets, debug output, SQLite/cache files;
- настройки, принадлежащие конкретному игроку.

Если новая конфигурация содержит неизвестный identifier, token, UUID, IP, username или путь,
остановитесь и запросите review.

## Подготовка изменения

Создайте `feature/*` от `develop`. Не запускайте maintainer-only
`scripts/import-pack.ps1`: он читает локальную read-only Prism instance и предназначен для
полной синхронизации владельцем проекта.

После изменения:

```powershell
.\scripts\refresh-pack.ps1
.\scripts\validate-pack.ps1
```

Проверьте точный diff:

```powershell
git status --short
git diff --stat
git diff
```

Убедитесь, что:

- `pack/index.toml` соответствует hash в `pack/pack.toml`;
- Default Dark Mode остался в pack;
- user-owned settings сохраняют `preserve=true`;
- все Modrinth metadata содержат точные hashes;
- новые dependencies добавлены;
- в diff нет private data и raw JAR без approval.

## Pull Request

PR направляется в `develop` и получает `area:pack`. В описании перечислите:

- добавленные, обновлённые и удалённые моды;
- dependencies и configuration changes;
- результат pack validation;
- результат ручного запуска игры, если он выполнялся;
- изменение NeoForge, если оно есть.

Pack-only PR не изменяет launcher version, не строит Setup/Portable и не создаёт GitHub Release.
Игроки получают pack только после promotion в `main` и успешного Pages deployment.
