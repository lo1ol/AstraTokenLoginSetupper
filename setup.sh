#!/bin/bash

NUMBER_REGEXP='^[0-9]+$'
CUR_DIR=`pwd`

function init() { cd $(mktemp -d); }
function cleanup() { rm -rf `pwd`; cd $CUR_DIR; }

echoerr() { echo "Ошибка: $@" 1>&2; cleanup; exit; }

function install_packages ()
{
	wget -q "https://wiki.astralinux.ru/download/attachments/32834416/libengine-pkcs11-openssl1.1_0.4.4-4_amd64.deb?version=2&modificationDate=1548065040377&api=v2" -O libengine-pkcs11-openssl1.1_0.4.4-4_amd64.deb;
	if [[ $? -ne 0 ]]; then echoerr "Не могу скачать пакет libengine-pkcs11-openssl"; fi 
	sudo dpkg -i libengine-pkcs11-openssl1.1_0.4.4-4_amd64.deb > /dev/null;
	if [[ $? -ne 0 ]]; then echoerr "Не могу установить пакет libengine-pkcs11-openssl"; fi 

	wget -q "https://download.rutoken.ru/Rutoken/PKCS11Lib/Current/Linux/x64/librtpkcs11ecp_2.0.4.0-1_amd64.deb";
	if [[ $? -ne 0 ]]; then echoerr "Не могу скачать пакет librtpkcs11ecp.so"; fi 
	sudo dpkg -i librtpkcs11ecp_2.0.4.0-1_amd64.deb > /dev/null;
	if [[ $? -ne 0 ]]; then echoerr "Не установить пакет librtpkcs11ecp.so"; fi 

	sudo apt-get -qq update
	sudo apt-get -qq install opensc libccid pcscd libpam-p11 libpam-pkcs11 libp11-2 dialog;
	if [[ $? -ne 0 ]]; then echoerr "Не могу установить один из пакетов opensc libccid pcscd libpam-p11 libpam-pkcs11 libp11-2 dialog из репозитория"; fi
}

function token_present ()
{
	cert_ids=`pkcs11-tool --module /usr/lib/librtpkcs11ecp.so -O 2> /dev/null`;
	return $?
}
function choose_cert ()
{
	cert_ids=`pkcs11-tool --module /usr/lib/librtpkcs11ecp.so -O --type cert 2> /dev/null | grep -Eo "ID:.*" |  awk '{print $2}'`;
	if [[ -z "$cert_ids" ]]
	then
		return
	fi

	cert_ids=`echo -e "$cert_ids\n\"Новый сертификат\""`;
	cert_ids=`echo "$cert_ids" | awk '{printf("%s\t%s\n", NR, $0)}'`;
	cert_id=`echo $cert_ids | xargs dialog --keep-tite --stdout --title "Выбор сертификат" --menu "Выберете сертификат" 0 0 0`;
	cert_id=`echo "$cert_ids" | sed "${cert_id}q;d" | cut -f2 -d$'\t'`;
	echo "$cert_id"
}

function create_cert ()
{
	cert_id=`dialog --keep-tite --stdout --title "Задание id сертификата" --inputbox "Придумайте id сертификата: " 0 0 ""`;
	if ! [[ "$cert_id" =~ $NUMBER_REGEXP ]]; then echoerr "id сертификата должно быть числом"; fi	
	pkcs11-tool --module /usr/lib/librtpkcs11ecp.so --keypairgen --key-type rsa:2048 -l -p $PIN --id $cert_id > /dev/null 2> /dev/null;
	if [[ $? -ne 0 ]]; then echoerr "Не удалось создать ключ"; fi 
	
	C=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "Country Name (2 letter code):" 0 0 "AU"`;
	ST=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "State or Province Name (full name):" 0 0 "Some-State"`;
	L=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "Locality Name (eg, city):" 0 0 ""`;
	O=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "Organization Name (eg, company):" 0 0 "Internet Widgits Pty Ltd"`;
	OU=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "Organizational Unit Name (eg, section):" 0 0 ""`;
	CN=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "Common Name (e.g. server FQDN or YOUR name):" 0 0 ""`;
	email=`dialog --keep-tite --stdout --title "Данные сертификата" --inputbox "Email Address:" 0 0 ""`;
	printf "engine dynamic -pre SO_PATH:/usr/lib/x86_64-linux-gnu/engines-1.1/pkcs11.so -pre ID:pkcs11 -pre LIST_ADD:1  -pre LOAD -pre MODULE_PATH:/usr/lib/librtpkcs11ecp.so \n req -engine pkcs11 -new -key 0:$cert_id -keyform engine -x509 -out cert.crt -outform DER -subj \"/C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=$CN/emailAddress=$email\"" | openssl > /dev/null;
	if [[ $? -ne 0 ]]; then echoerr "Не удалось создать сертификат ключа"; fi 

	pkcs11-tool --module /usr/lib/librtpkcs11ecp.so -l -p $PIN -y cert -w cert.crt --id $cert_id > /dev/null 2> /dev/null;
	if [[ $? -ne 0 ]]; then echoerr "Не удалось загрзить сертификат на токен"; fi 
	echo $cert_id
}

function setup_authorization ()
{
	pkcs11-tool --module /usr/lib/librtpkcs11ecp.so -r -y cert --id $1 > cert.crt 2> /dev/null;
	if [[ $? -ne 0 ]]; then echoerr "Не удалось загрзить загрзить сертификат с токена"; fi 
	openssl x509 -in cert.crt -out cert.pem -inform DER -outform PEM;
	mkdir ~/.eid 2> /dev/null;
	chmod 0755 ~/.eid;
	cat cert.pem >> ~/.eid/authorized_certificates;
	chmod 0644 ~/.eid/authorized_certificates;
	sudo cp $CUR_DIR/p11 /usr/share/pam-configs/p11;
	read -p "!!! Нажмите Enter и в следующем окне выберете Pam_p11 !!!"
	sudo pam-auth-update;
}

function get_token_password ()
{
	pin=`dialog --keep-tite --stdout --title "Token PIN"  --passwordbox "Enter Token PIN:" 0 0 ""`;
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

echo "Поиск токена"
token_present
if [[ $? -ne 0 ]]; then echoerr "Токен не найден"; exit; fi

echo "Выбор сертификата для входа в систему"
cert_id=`choose_cert`

if ! [[ "$cert_id" =~ $NUMBER_REGEXP ]]
then
	echo "Создание нового ключа и сретификата"
	PIN=`get_token_password`
	cert_id=`create_cert`
fi

echo "Настройка авторизации с помощью токена"
setup_authorization $cert_id
echo "Настройка автоблокировки"
setup_autolock

echo "Изменения вступят в силу, после завершения сессии"

cleanup
