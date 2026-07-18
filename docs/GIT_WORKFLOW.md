# Gitflow Blacked Aeronautics

В проекте используются три постоянные ветки и короткие рабочие ветки. Production-ветка
называется `main`: переименование в `master` сломало бы существующие Pages и CDN-ссылки
`@main`.

## Постоянные ветки

| Ветка | Назначение | Допустимые источники PR |
|---|---|---|
| `main` | Проверенное production-состояние и источник Pages | `release`, `hotfix/*` |
| `release` | Стабилизация и ручное тестирование release-кандидата | `develop`, `bugfix/*`, `main` |
| `develop` | Интеграция следующей версии | `feature/*`, `docs/*`, `chore/*`, `release` |

`develop` является default branch на GitHub. Прямые push, force-push и удаление постоянных
веток запрещены.

## Рабочие ветки

| Префикс | Создавать от | PR направлять в | Когда использовать |
|---|---|---|---|
| `feature/*` | `develop` | `develop` | Новая возможность |
| `docs/*` | `develop` | `develop` | Только документация |
| `chore/*` | `develop` | `develop` | CI, tooling, зависимости и обслуживание |
| `bugfix/*` | `release` | `release` | Исправление найденного на staging дефекта |
| `hotfix/*` | `main` | `main` | Срочное исправление production |

После префикса используется короткий lowercase slug: `feature/mod-browser`,
`bugfix/pack-download`, `hotfix/update-loop`. При наличии issue желательно добавить номер:
`feature/42-mod-browser`.

## Обычная разработка

1. Обновить `develop` и создать от неё `feature/*`, `docs/*` или `chore/*`.
2. Сделать небольшие Conventional Commits и открыть PR в `develop`.
3. Дождаться `Governance / gate` и review.
4. Использовать squash merge. Итоговый commit получает Conventional title PR.

Прямой `feature/* → main` или `feature/* → release` блокируется CI.

## Подготовка production

1. Открыть PR `develop → release` с title вида
   `chore(release): promote develop to staging`.
2. Использовать merge commit, чтобы сохранить ancestry постоянных веток.
3. На `release` выполнять только стабилизацию. Новые feature туда не добавлять.
4. Исправления создавать как `bugfix/*` от `release` и squash-merge обратно.
5. После bugfix открыть back-sync PR `release → develop`.
6. После успешного тестирования открыть PR `release → main` и использовать merge commit.

Pack-only merge в `main` запускает Pages и не создаёт launcher tag или GitHub Release.
Изменение launcher distribution выпускается существующим тегом `vX.Y.Z-ely.N` и только после
полной проверки Setup и Portable.

## Hotfix

1. Создать `hotfix/*` от актуального `main`.
2. Открыть PR в `main` и выполнить проверки.
3. После merge синхронизировать `main → release`.
4. Затем синхронизировать `release → develop`.

Hotfix не переносится cherry-pick в каждую ветку: merge постоянных веток сохраняет единое
происхождение исправления.

## Merge policy

- Короткие ветки: squash merge.
- Promotion и back-sync постоянных веток: merge commit.
- Rebase merge отключён.
- PR title обязан соответствовать [правилам commits](COMMITS.md).
- Conversations должны быть resolved, stale approvals сбрасываются.
- После merge короткая ветка удаляется автоматически.
- System-generated `Merge pull request ...` commits являются единственным исключением из
  Conventional header.
