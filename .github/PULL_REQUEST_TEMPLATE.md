## Что изменено

<!-- Кратко опишите одно связное изменение. -->

## Зачем

<!-- Укажите связанную issue и пользовательский/технический результат. -->

Closes #

## Область

- [ ] Pack, моды или игровая конфигурация
- [ ] Launcher, updater, installer или build
- [ ] Документация, CI или repository tooling

## Проверка

- [ ] PR направлен в target, разрешённый Gitflow
- [ ] PR title и commits используют `<type>(<scope>): <English subject>`
- [ ] В diff нет accounts, worlds, servers, secrets, local paths или cache
- [ ] Я проверил точный diff и не включил unrelated changes
- [ ] `.\scripts\validate-commit-policy.ps1 -TestFixtures` проходит
- [ ] `.\scripts\validate-pack.ps1` проходит
- [ ] `.\scripts\test-updater.ps1` проходит или launcher paths не изменены

## Дополнительные результаты

<!-- Перечислите mod counts, NeoForge impact, game test, Setup/Portable test или residual risk. -->
