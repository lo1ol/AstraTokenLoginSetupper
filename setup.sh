#!/bin/bash

NUMBER_REGEXP='^[0123456789abcdefABCDEF]+$'
CUR_DIR=`pwd`
DIALOG="dialog --keep-tite --stdout"

function init() { 
	source /etc/os-release
	OS_NAME=$NAME
	
	case $OS_NAME in
        "RED OS") 
		LIBRTPKCS11ECP=/usr/lib64/librtpkcs11ecp.so
		PKCS11_ENGINE=/usr/lib64/engines-1.1/pkcs11.so
		;;
        "Astra Linux"*)
		LIBRTPKCS11ECP=/usr/lib/librtpkcs11ecp.so
		PKCS11_ENGINE=/usr/lib/x86_64-linux-gnu/engines-1.1/pkcs11.so
		;;
        esac
	
	SCRIPT_DIR="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

	cd $(mktemp -d);
}
function cleanup() { rm -rf `pwd`; cd $CUR_DIR; }

echoerr() { echo -e "Ошибка: $@" 1>&2; cleanup; exit; }

function install_packages ()
{
	case $OS_NAME in
	"RED OS") redos_install_packages;;
	"Astra Linux"*) astra_install_packages;;
	esac
}

function redos_install_packages ()
{
	sudo yum -q -y update
	if ! [[ -f $LIBRTPKCS11ECP ]]
	then
		wget -q --no-check-certificate "https://download.rutoken.ru/Rutoken/PKCS11Lib/Current/Linux/x64/librtpkcs11ecp.so";
        	if [[ $? -ne 0 ]]; then echoerr "Не могу скачать пакет librtpkcs11ecp.so"; fi 
		sudo cp librtpkcs11ecp.so $LIBRTPKCS11ECP;
	fi

	sudo yum -q -y install ccid opensc gdm-plugin-smartcard p11-kit pam_pkcs11 rpmdevtools dialog;
	if [[ $? -ne 0 ]]; then echoerr "Не могу установить один из пакетов: ccid opensc gdm-plugin-smartcard p11-kit pam_pkcs11 rpmdevtools dialog из репозитория"; fi
	
	sudo yum -q -y install libp11 engine_pkcs11;
        if [[ $? -ne 0 ]]
        then
        	$DIALOG --msgbox "Скачайте последнюю версии пакетов libp11 engine_pkcs11 отсюда https://apps.fedoraproject.org/packages/libp11/builds/ и установите их с помощью команд sudo rpm -i /path/to/package. Или соберите сами их из исходников" 0 0
		echoerr "Установите пакеты libp11 и engine_pkcs11 отсюда https://apps.fedoraproject.org/packages/libp11/builds/"
	fi

	sudo systemctl restart pcscd
}

function astra_install_packages ()
{
	sudo apt-get -qq update
	if ! [[ -f $LIBRTPKCS11ECP ]]
	then
		wget -q --no-check-certificate "https://download.rutoken.ru/Rutoken/PKCS11Lib/Current/Linux/x64/librtpkcs11ecp.so";
        	if [[ $? -ne 0 ]]; then echoerr "Не могу скачать пакет librtpkcs11ecp.so"; fi 
		sudo cp librtpkcs11ecp.so $LIBRTPKCS11ECP;
	fi

	sudo apt-get -qq install libengine-pkcs11-openssl1.1 opensc libccid pcscd libpam-p11 libpam-pkcs11 libp11-2 dialog;
	if [[ $? -ne 0 ]]; then echoerr "Не могу установить один из пакетов: libengine-pkcs11-openssl1.1 opensc libccid pcscd libpam-p11 libpam-pkcs11 libp11-2 dialog из репозитория"; fi
}

function token_present ()
{
	cnt=`lsusb | grep "0a89:0030" | wc -l`
	if [[ cnt -eq 0 ]]; then echoerr "Устройство семейства Рутокен ЭЦП не найдено"; exit; fi
	if [[ cnt -ne 1 ]]; then echoerr "Найдено несколько устройств семейства Рутокен ЭЦП. Оставьте только одно"; exit; fi
}

function get_cert_list ()
{
	cert_ids=`pkcs11-tool --module $LIBRTPKCS11ECP -O --type cert 2> /dev/null | grep -Eo "ID:.*" |  awk '{print $2}'`;
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
	cert_id=`echo $cert_ids | xargs $DIALOG --title "Выбор сертификата" --menu "Выбeрите сертификат" 0 0 0`;
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
	out=`pkcs11-tool --module $LIBRTPKCS11ECP --keypairgen --key-type rsa:2048 -l -p $PIN --id $cert_id 2>&1`;
	if [[ $? -ne 0 ]]; then echoerr "Не удалось создать ключевую пару: $out"; fi 
	
	C="/C=RU";
	ST=`$DIALOG --title 'Данные сертификата' --inputbox 'Регион:' 0 0 'Москва'`;
	if [[ -n "$ST" ]]; then ST="/ST=$ST"; else ST=""; fi

	L=`$DIALOG --title 'Данные сертификата' --inputbox 'Населенный пункт:' 0 0 ''`;
	if [[ -n "$L" ]]; then L="/L=$L"; else L=""; fi
	
	O=`$DIALOG --title 'Данные сертификата' --inputbox 'Организация:' 0 0 'ООО Ромашка'`;
	if [[ -n "$O" ]]; then O="/O=$O"; else O=""; fi
	
	OU=`$DIALOG --title 'Данные сертификата' --inputbox 'Подразделение:' 0 0 ''`;
	if [[ -n "$OU" ]]; then OU="/OU=$OU"; else OU=""; fi
	
	CN=`$DIALOG --stdout --title 'Данные сертификата' --inputbox 'Общее имя:' 0 0 ''`;
	if [[ -n "$CN" ]]; then CN="/CN=$CN"; else CN=""; fi
	
	email=`$DIALOG --stdout --title 'Данные сертификата' --inputbox 'Электронная почта:' 0 0 ''`;
	if [[ -n "$email" ]]; then email="/emailAddress=$email"; else email=""; fi
	
	choice=`$DIALOG --stdout --title "Создание сертификата" --menu "Укажите опцию" 0 0 0 1 "Создать самоподписанный сертификат" 2 "Создать заявку на сертификат"`
	
	openssl_req="engine dynamic -pre SO_PATH:$PKCS11_ENGINE -pre ID:pkcs11 -pre LIST_ADD:1  -pre LOAD -pre MODULE_PATH:$LIBRTPKCS11ECP \n req -engine pkcs11 -new -key \"0:$cert_id\" -keyform engine -subj \"$C$ST$L$O$OU$CN$email\""

	if [[ choice -eq 1  ]]
	then
		printf "$openssl_req -x509 -outform DER -out cert.crt "| openssl > /dev/null;
		
		if [[ $? -ne 0 ]]; then echoerr "Не удалось создать сертификат открытого ключа"; fi 
	else
		printf "$openssl_req -out $CUR_DIR/cert.csr -outform PEM" | openssl > /dev/null;
		
		if [[ $? -ne 0 ]]; then echoerr "Не удалось создать заявку на сертификат открытого ключа"; fi 
		
		$DIALOG --msgbox "Отправьте заявку на сертификат в УЦ для выпуска сертификата. После получение сертификата, запишите его на токен с помощью import_cert_to_token.sh под индентификатором $cert_id. И повторите запуск setup.sh" 0 0
		exit
	fi

	
	pkcs11-tool --module $LIBRTPKCS11ECP -l -p $PIN -y cert -w cert.crt --id $cert_id > /dev/null 2> /dev/null;
	if [[ $? -ne 0 ]]; then echoerr "Не удалось загрзить сертификат на токен"; fi 
	echo $cert_id
}

function setup_authentication ()
{
        case $OS_NAME in
        "RED OS") redos_setup_authentication $1;;
        "Astra Linux"*) astra_setup_authentication $1;;
        esac
}


function redos_setup_authentication ()
{
	DB=/etc/pam_pkcs11/nssdb
	sudo mkdir $DB 2> /dev/null;
	if ! [ "$(ls -A $DB)" ]
	then
		sudo chmod 0644 $DB
		sudo certutil -d $DB -N
	fi
	
	sudo modutil -dbdir $DB -add p11-kit-trust -libfile /usr/lib64/pkcs11/p11-kit-trust.so 2> /dev/null
	
	pkcs11-tool --module $LIBRTPKCS11ECP -l -r -y cert -d $1 -o cert$1.crt
	sudo cp cert$1.crt /etc/pki/ca-trust/source/anchors/
	sudo update-ca-trust force-enable
	sudo update-ca-trust extract

	sudo mv /etc/pkcs11/pam_pkcs11.conf /etc/pkcs11/pam_pkcs11.conf.default 2> /dev/null;
	sudo mkdir /etc/pkcs11/cacerts /etc/pkcs11/crls 2> /dev/null;
	sudo cp $SCRIPT_DIR/redos/pam_pkcs11.conf /etc/pam_pkcs11/ 2> /dev/null
	
	openssl dgst -sha1 cert$1.crt | cut -d" " -f2- | awk '{ print toupper($0) }' | sed 's/../&:/g;s/:$//' | sed "s/.*/\0 -> $USER/" | sudo tee /etc/pam_pkcs11/digest_mapping -a  > /dev/null 
	
	pam_pkcs11_insert="/pam_unix/ && x==0 {print \"auth sufficient pam_pkcs11.so pkcs11_module=/usr/lib64/librtpkcs11ecp.so\"; x=1} 1"
	
	sys_auth="/etc/pam.d/system-auth"
	if ! [ "$(sudo cat $sys_auth | grep 'pam_pkcs11.so')" ]
	then
		awk "$pam_pkcs11_insert" $sys_auth | sudo tee $sys_auth  > /dev/null  
	fi

	pass_auth="/etc/pam.d/password-auth"
        if ! [ "$(sudo cat $pass_auth | grep 'pam_pkcs11.so')" ]
        then
		awk "$pam_pkcs11_insert" $pass_auth | sudo tee $pass_auth  > /dev/null
        fi
}

function astra_setup_authentication ()
{
	pkcs11-tool --module $LIBRTPKCS11ECP -r -y cert --id $1 > cert.crt 2> /dev/null;
	if [[ $? -ne 0 ]]; then echoerr "Не удалось загрзить загрзить сертификат с Рутокена"; fi 
	openssl x509 -in cert.crt -out cert.pem -inform DER -outform PEM;
	mkdir ~/.eid 2> /dev/null;
	chmod 0755 ~/.eid;
	cat cert.pem >> ~/.eid/authorized_certificates;
	chmod 0644 ~/.eid/authorized_certificates;
	sudo cp $SCRIPT_DIR/astra/p11 /usr/share/pam-configs/p11;
	read -p "ВАЖНО: Нажмите Enter и в следующем окне выберите Pam_p11"
	sudo pam-auth-update;
}

function get_token_password ()
{
	pin=`$DIALOG --title "Ввод PIN-кода"  --passwordbox "Введите PIN-код от Рутокена:" 0 0 ""`;
	echo $pin
}

function setup_autolock ()
{
        case $OS_NAME in
        "RED OS") redos_setup_autolock;;
        "Astra Linux"*) astra_setup_autolock;;
        esac
}


function redos_setup_autolock ()
{
	sudo cp $SCRIPT_DIR/redos/pkcs11_eventmgr.conf /etc/pam_pkcs11/pkcs11_eventmgr.conf
	sudo cp $SCRIPT_DIR/redos/smartcard-screensaver.desktop /etc/xdg/autostart/smartcard-screensaver.desktop
        sudo systemctl daemon-reload
}


function astra_setup_autolock ()
{
	sudo cp $SCRIPT_DIR/astra/pkcs11_eventmgr.conf /etc/pam_pkcs11/pkcs11_eventmgr.conf
	sudo cp $SCRIPT_DIR/astra/smartcard-screensaver.desktop /etc/xdg/autostart/smartcard-screensaver.desktop
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
