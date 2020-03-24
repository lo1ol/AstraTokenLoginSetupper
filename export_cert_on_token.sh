#!/bin/bash

echoerr() { echo "Ошибка: $@" 1>&2; exit; }

function token_present ()
{
	pkcs11-tool --module /usr/lib/librtpkcs11ecp.so -O > /dev/null 2> /dev/null;
	return $?
}

function choose_key ()
{
	key_ids=`pkcs11-tool --module /usr/lib/librtpkcs11ecp.so -O --type pubkey 2> /dev/null | grep -Eo "ID:.*" |  awk '{print $2}'`;
	if [[ -z "$key_ids" ]]
	then
		echoerr "На токене нет ключей"
	fi

	key_ids=`echo "$key_ids" | awk '{printf("%s\t%s\n", NR, $0)}'`;
	key_id=`echo $key_ids | xargs dialog --keep-tite --stdout --title "Выбор ключа" --menu "Выберете ключ" 0 0 0`;
	key_id=`echo "$key_ids" | sed "${key_id}q;d" | cut -f2 -d$'\t'`;
	echo "$key_id"
}

function export_cert ()
{
	cert=`dialog --keep-tite --stdout --title "Путь до сертификата" --fselect $HOME/ 0 0`
	pkcs11-tool --module /usr/lib/librtpkcs11ecp.so -l -p "$PIN" -y cert -w "$cert" --id "$1" > /dev/null 2> /dev/null;
	if [[ $? -ne 0 ]]; then echoerr "Не удалось загрзить сертификат на Рутокен"; fi 
}

function get_token_password ()
{
	pin=`dialog --keep-tite --stdout --title "Ввод PIN-кода"  --passwordbox "Введите PIN-код от Рутокена:" 0 0 ""`;
	echo $pin
}

echo "Обнаружение подключенного устройства семейства Рутокен ЭЦП"
token_present
if [[ $? -ne 0 ]]; then echoerr "Устройство семейства Рутокен ЭЦП не найдено"; exit; fi

echo "Выбор ключа, для которого был сделан сертификат"
key_id=`choose_key`

echo "Экспорт сертификата на Рутокен"
PIN=`get_token_password`
export_cert $key_id

echo "Сертификат усешно экспортирован на Рутокен"

