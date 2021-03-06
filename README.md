# Описание
Скрипт для настройки аутентификации в системе по токену для текущего пользователя в Astra Linux и РЕД ОС.

# Использование
```bash
bash setup.sh
```

# Примечание
1. Скрипт сам должен загрузить все необходимые пакеты для работы.
2. При создании нового сертификата необходимо два раза ввести PIN-код токена.
3. Внимательно следите за указаниями, которые выдает программа.
# Пример создания ключа с несамоподписанным сертификатом:
1. Запустите setup.sh. В процессе выберите пункты для создания нового сертификата и создания заявки на сертификат. Запомните id сгенерированного сертификата из последней строки вывода.
2. Полученную заявку cert.req подпишите в УЦ. Это можно сделать при помощи команды:
```bash
openssl x509 -req -in cert.req -CA root.crt -CAkey root.key -CAcreateserial -out cert.crt -days 365 -outform DER
```
3. Запустите import_cert_to_token.sh и укажите ключ, для которого был создан сертификат и путь до сертификата.
4. Повторно запустите setup.sh и выберите id созданного сертификата.
