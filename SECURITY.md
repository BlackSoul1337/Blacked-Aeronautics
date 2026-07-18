# Security policy

## Поддерживаемые версии

Security fixes выпускаются для последней опубликованной launcher-версии и текущего pack в
`main`. Старые Setup/Portable releases могут потребовать обновления до актуальной версии.

## Сообщить об уязвимости

Не создавайте public issue для:

- обхода update integrity или path validation;
- remote code execution;
- утечки accounts, tokens или пользовательских файлов;
- подмены download, manifest, JAR или release asset;
- опасного поведения installer/uninstaller.

Используйте
[GitHub private security advisory](https://github.com/BlackSoul1337/Blacked-Aeronautics/security/advisories/new).

Укажите affected version, шаги воспроизведения, ожидаемое/фактическое поведение, impact и
минимальный proof of concept без чужих данных. Maintainer подтвердит получение, проверит impact
и согласует disclosure после выпуска исправления.

Обычные crashes, gameplay bugs и предложения модов отправляются через Issue Forms.
