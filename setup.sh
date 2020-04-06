#!/bin/bash

NUMBER_REGEXP='^[0123456789abcdefABCDEF]+$'
CUR_DIR=`pwd`

function init() { cd $(mktemp -d); }
function cleanup() { rm -rf `pwd`; cd $CUR_DIR; }

echoerr() { echo -e "Ошибка: $@" 1>&2; cleanup; exit; }

function install_packages ()
{
	sudo apt-get -qq update
	
	sudo apt-get -qq install librtpkcs11ecp;
	if [[ $? -ne 0 ]]
	then
		wget -q --no-check-certificate "https://download.rutoken.ru/Rutoken/PKCS11Lib/Current/Linux/x64/librtpkcs11ecp.so";
        	if [[ $? -ne 0 ]]; then echoerr "Не могу скачать пакет librtpkcs11ecp.so"; fi 
		sudo cp librtpkcs11ecp.so /usr/lib/;
	fi

	sudo apt-get -qq install libengine-pkcs11-openssl1.1 opensc libccid pcscd libpam-p11 libpam-pkcs11 libp11-2 dialog;
	if [[ $? -ne 0 ]]; then echoerr "Не могу установить один из пакетов: librtpkcs11ecp libengine-pkcs11-openssl1.1 opensc libccid pcscd libpam-p11 libpam-pkcs11 libp11-2 dialog из репозитория"; fi
}

function token_present ()
{
	cnt=`lsusb | grep "0a89:0030" | wc -l`
	if [[ cnt -eq 0 ]]; then echoerr "Устройство семейства Рутокен ЭЦП не найдено"; exit; fi
	if [[ cnt -ne 1 ]]; then echoerr "Найдено несколько устройств семейства Рутокен ЭЦП. Оставьте только одно"; exit; fi
}

function get_cert_list ()
{
	cert_ids=`pkcs11-tool --module /usr/lib/librtpkcs11ecp.so -O --type cert 2> /dev/null | grep -Eo "ID:.*" |  awk '{print $2}'`;
	echo "$cert_ids";
}

function choose_cert ()
{
	cert_ids=`get_cert_list`
	if [[ -z "$cert_ids" ]]
	then
		echo "None"
		exit
	fi

	cert_ids=`echo -e "$cert_ids\n\"Новый сертификат\""`;
	cert_ids=`echo "$cert_ids" | awk '{printf("%s\t%s\n", NR, $0)}'`;
	cert_id=`echo $cert_ids | xargs dialog --keep-tite --stdout --title "Выбор сертификата" --menu "Выберете сертификат" 0 0 0`;
	cert_id=`echo "$cert_ids" | sed "${cert_id}q;d" | cut -f2 -d$'\t'`;
	echo "$cert_id"
}

function gen_cert_id ()
{
	res="1"
	while [[ -n "$res" ]]
	do
		cert_ids=`get_cert_list`
		rand=`echo $(( $RANDOM % 10000 ))`
		res=`echo $cert_ids | grep -w $rand`
	done
	
	echo "$rand"
}

function create_key_and_cert ()
{
	cert_id=`gen_cert_id`
	out=`pkcs11-tool --module /usr/lib/librtpkcs11ecp.so --keypairgen --key-type rsa:2048 -l -p $PIN --id $cert_id 2>&1`;
	if [[ $? -ne 0 ]]; then echoerr "Не удалось создать ключевую пару: $out"; fi 
	
	C="RU";
	ST=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "Регион:" 0 0 "Москва"`;
	L=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "Населенный пункт:" 0 0 ""`;
	O=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "Организация:" 0 0 "ООО Ромашка"`;
	OU=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "Подразделение:" 0 0 ""`;
	CN=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "Общее имя:" 0 0 ""`;
	email=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "Электронная почта:" 0 0 ""`;
	
	choice=`dialog --keep-tite --stdout --title "Выбор корневого сертификата" --menu "Родительский сертификат:" 0 0 0 1 "Создать самоподписанный сертификат" 2 "Создать заявку на сертификат"`	
	
	openssl_req="engine dynamic -pre SO_PATH:/usr/lib/x86_64-linux-gnu/engines-1.1/pkcs11.so -pre ID:pkcs11 -pre LIST_ADD:1  -pre LOAD -pre MODULE_PATH:/usr/lib/librtpkcs11ecp.so \n req -engine pkcs11 -new -key \"0:$cert_id\" -keyform engine -subj \"/C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=$CN/emailAddress=$email\""

	if [[ choice -eq 1  ]]
	then
		printf "$openssl_req -x509 -outform DER -out cert.crt "| openssl > /dev/null;
		
		if [[ $? -ne 0 ]]; then echoerr "Не удалось создать сертификат открытого ключа"; fi 
	else
		printf "$openssl_req -out $CUR_DIR/cert.csr " | openssl > /dev/null;
		
		if [[ $? -ne 0 ]]; then echoerr "Не удалось создать заявку на сертификат открытого ключа"; fi 
		
		echo "Отправьте заявку на получение сертификата УЦ. После получение сертификата, запишите его на токен с помощью export_cert_on_token.sh под индентификатором $cert_id. И повторите запуск setup.sh"
		exit
	fi

	
	pkcs11-tool --module /usr/lib/librtpkcs11ecp.so -l -p $PIN -y cert -w cert.crt --id $cert_id > /dev/null 2> /dev/null;
	if [[ $? -ne 0 ]]; then echoerr "Не удалось загрзить сертификат на токен"; fi 
	echo $cert_id
}

function setup_authentication ()
{
	pkcs11-tool --module /usr/lib/librtpkcs11ecp.so -r -y cert --id $1 > cert.crt 2> /dev/null;
	if [[ $? -ne 0 ]]; then echoerr "Не удалось загрзить загрзить сертификат с Рутокена"; fi 
	openssl x509 -in cert.crt -out cert.pem -inform DER -outform PEM;
	mkdir ~/.eid 2> /dev/null;
	chmod 0755 ~/.eid;
	cat cert.pem >> ~/.eid/authorized_certificates;
	chmod 0644 ~/.eid/authorized_certificates;
	sudo cp $CUR_DIR/p11 /usr/share/pam-configs/p11;
	read -p "ВАЖНО: Нажмите Enter и в следующем окне выберите Pam_p11"
	sudo pam-auth-update;
}

function get_token_password ()
{
	pin=`dialog --keep-tite --stdout --title "Ввод PIN-кода"  --passwordbox "Введите PIN-код от Рутокена:" 0 0 ""`;
	echo $pin
}

function setup_autolock ()
{
	sudo cp $CUR_DIR/pkcs11_eventmgr.conf /etc/pam_pkcs11/pkcs11_eventmgr.conf
	sudo cp $CUR_DIR/smartcard-screensaver.desktop /etc/xdg/autostart/smartcard-screensaver.desktop
	sudo systemctl daemon-reload
}


init

echo "Установка пакетов"
install_packages

echo "Обнаружение подключенного устройства семейства Рутокен ЭЦП"
token_present

echo "Выбор сертификата для входа в систему"
cert_id=`choose_cert`

if ! [[ "$cert_id" =~ $NUMBER_REGEXP ]]
then
	echo "Создание новой ключевой пары и сертификата"
	PIN=`get_token_password`
	cert_id=`create_key_and_cert`
fi

if ! [[ "$cert_id" =~ $NUMBER_REGEXP ]]
then
	echo "$cert_id"
	exit
fi

echo "Выбранный сертификат имеет идентифкатор $cert_id"

echo "Настройка аутентификации с помощью Рутокена"
setup_authentication $cert_id
echo "Настройка автоблокировки"
setup_autolock

echo "Изменения вступят в силу, после завершения сессии"

cleanup
