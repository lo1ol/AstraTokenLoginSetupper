#!/bin/bash

DIALOG="dialog --keep-tite --stdout"

function echoerr() { echo "Ошибка: $@" 1>&2; exit; }

function init() {
        source /etc/os-release
        OS_NAME=$NAME

        case $OS_NAME in
        "RED OS")
                LIBRTPKCS11ECP=/usr/lib64/librtpkcs11ecp.so
                ;;
        "Astra Linux"*)
                LIBRTPKCS11ECP=/usr/lib/librtpkcs11ecp.so
                ;;
        esac
}

function token_present ()
{
        cnt=`lsusb | grep "0a89:0030" | wc -l`
        if [[ cnt -eq 0 ]]; then echoerr "Устройство семейства Рутокен ЭЦП не найдено"; exit; fi
        if [[ cnt -ne 1 ]]; then echoerr "Найдено несколько устройств семейства Рутокен ЭЦП. Оставьте только одно"; exit; fi
}

function choose_key ()
{
	key_ids=`pkcs11-tool --module $LIBRTPKCS11ECP -O --type pubkey 2> /dev/null | grep -Eo "ID:.*" |  awk '{print $2}'`;
	if [[ -z "$key_ids" ]]
	then
		echoerr "На токене нет ключей"
	fi

	key_ids=`echo "$key_ids" | awk '{printf("%s\t%s\n", NR, $0)}'`;
	key_id=`echo $key_ids | xargs $DIALOG --title "Выбор ключа" --menu "Выберите ключ" 0 0 0`;
	key_id=`echo "$key_ids" | sed "${key_id}q;d" | cut -f2 -d$'\t'`;
	echo "$key_id"
}

function export_cert ()
{
	cert=`$DIALOG --title "Путь до сертификата" --fselect $HOME/ 0 0`
	pkcs11-tool --module $LIBRTPKCS11ECP -l -p "$PIN" -y cert -w "$cert" --id "$1" > /dev/null 2> /dev/null;
	if [[ $? -ne 0 ]]; then echoerr "Не удалось загрзить сертификат на Рутокен"; fi 
}

function get_token_password ()
{
	pin=`$DIALOG --title "Ввод PIN-кода"  --passwordbox "Введите PIN-код от Рутокена:" 0 0 ""`;
	echo $pin
}

init

echo "Обнаружение подключенного устройства семейства Рутокен ЭЦП"
token_present
if [[ $? -ne 0 ]]; then echoerr "Устройство семейства Рутокен ЭЦП не найдено"; exit; fi

echo "Выбор ключа, для которого был сделан сертификат"
key_id=`choose_key`

if [[ -z key_id ]]; then exit; fi
echo "Экспорт сертификата на Рутокен"
PIN=`get_token_password`
export_cert $key_id

echo "Сертификат усешно экспортирован на Рутокен"

