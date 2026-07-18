# Правила commits

Каждый новый commit и PR title использует формат:

```text
<type>(<scope>)!?: <English imperative or present-tense subject>
```

`!` добавляется только для breaking change. Scope обязателен.

## Types

| Type | Использование |
|---|---|
| `feat` | Новая возможность |
| `fix` | Исправление дефекта |
| `docs` | Только документация |
| `style` | Форматирование без изменения поведения |
| `refactor` | Перестройка кода без новой возможности или bugfix |
| `perf` | Улучшение производительности |
| `test` | Добавление или исправление тестов |
| `build` | Build system и packaging |
| `ci` | GitHub Actions и другая CI-автоматизация |
| `chore` | Обслуживание, не подходящее под другие types |
| `revert` | Отмена предыдущего изменения |

## Scopes

| Scope | Область |
|---|---|
| `repo` | Общие правила, contributor workflow и repository tooling |
| `pack` | Packwiz, моды, конфигурация и игровые scripts |
| `launcher` | ElyPrism template и launcher integration |
| `updater` | C# updater и update process |
| `installer` | Inno Setup, Portable и packaging |
| `release` | Версии, promotion и distribution metadata |
| `ci` | Workflows и CI-only scripts |
| `deps` | Обновление зависимостей |

## Обязательные правила

- Commit целиком пишется на английском языке.
- Subject использует imperative или present form: `add`, `fix`, `prevent`, `keep`.
- Прошедшее время запрещено: нельзя `added`, `fixed`, `updated`, `removed`.
- Header и каждая строка body/footer имеют длину не более 100 символов.
- Рекомендуемая длина header — не более 72 символов.
- В конце subject нет `.`, `!`, `?`, `,`, `;` или `:`.
- Body отделяется от header пустой строкой.
- Один commit описывает одно связное изменение.

Примеры:

```text
feat(pack): add navigation mod metadata
fix(launcher): prevent incomplete first update
docs(repo): explain the Gitflow promotion path
test(updater): cover Java path override
ci(ci): add the governance gate
chore(deps): update the pinned action version
```

## Автоматическая проверка

Локальные fixtures:

```powershell
.\scripts\validate-commit-policy.ps1 -TestFixtures
```

В PR script проверяет:

- все commits в диапазоне PR, но не существующую историю;
- Conventional header, type и обязательный scope;
- ASCII-only текст как практический proxy английского языка;
- длину строк и завершающую пунктуацию;
- распространённые формы прошедшего времени;
- PR title;
- допустимое направление head/base веток.

Полностью определить грамматическое время автоматически невозможно, поэтому reviewer также
проверяет английский язык и imperative/present form.

GitHub-generated merge commits разрешены как документированное исключение. Обычные commits,
включая ручные merge commits, должны получать Conventional subject.
