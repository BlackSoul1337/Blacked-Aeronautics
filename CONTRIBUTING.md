# Участие в Blacked Aeronautics

Спасибо за желание помочь проекту. Сборка уже распространяется среди игроков и обновляется
автоматически, поэтому любое изменение проходит review и проверки до попадания в production.

## Выберите направление

- [Моды, packwiz и игровая конфигурация](docs/CONTRIBUTING_PACK.md) — основной открытый путь
  для contributions.
- [Launcher, updater, installer и build scripts](docs/CONTRIBUTING_LAUNCHER.md) — сначала
  создайте issue и согласуйте подход с maintainer.

Для общих изменений используйте [Gitflow](docs/GIT_WORKFLOW.md) и
[правила commits](docs/COMMITS.md).

## Перед началом

1. Найдите существующую issue или создайте подходящую Issue Form.
2. Не публикуйте security-уязвимость в обычной issue: используйте
   [private security advisory](SECURITY.md).
3. Дождитесь согласования спорного мода, неизвестного JAR, крупного launcher-изменения или
   breaking change.
4. Сделайте fork репозитория и создайте ветку от правильной постоянной ветки.

## Ветка и Pull Request

Обычная contribution создаётся от `develop`:

```powershell
git fetch origin
git switch develop
git pull --ff-only origin develop
git switch -c feature/123-short-description
```

- `feature/*` — новая возможность.
- `docs/*` — только документация.
- `chore/*` — CI, tooling или обслуживание.
- `bugfix/*` создаётся от `release` только для дефекта release-кандидата.
- `hotfix/*` создаётся от `main` только для срочного production-исправления.

Откройте PR в target, указанный в [Gitflow](docs/GIT_WORKFLOW.md). Разрешите maintainer
изменять ветку PR и заполните весь checklist.

## Commits

Каждый commit и PR title использует английский Conventional header:

```text
feat(pack): add navigation mod metadata
fix(updater): prevent incomplete update
docs(repo): explain pack validation
```

Scope обязателен. Прошедшее время и завершающая пунктуация запрещены. Полные правила и
разрешённые type/scope перечислены в [COMMITS.md](docs/COMMITS.md).

## Review и merge

- PR должен решать одну понятную задачу.
- Ответьте на review comments и пометьте conversations resolved только после исправления.
- Все обязательные checks должны пройти.
- Короткие ветки объединяются через squash; итоговый commit использует title PR.
- Maintainer может запросить дополнительные игровые или Windows-тесты.

## Лицензия и поведение

Отправляя contribution, вы соглашаетесь распространять её на условиях корневой лицензии
[MIT](LICENSE) и подтверждаете право передать этот код или контент проекту. Сторонние моды и
бинарные файлы сохраняют собственные лицензии.

Участники обязаны соблюдать [правила сообщества](CODE_OF_CONDUCT.md).
