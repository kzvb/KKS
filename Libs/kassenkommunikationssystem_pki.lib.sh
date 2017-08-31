if [[ -z "$(command -v waitSpinner)" ]]; then echo -e "\033[31m=> strings.lib.sh muss vorher gesourced werden.\033[0m"; exit 1; fi
ZERTIFIKAT_SUFFIX=".pem"
# $1 = URL zur Zertifikatsdatei von der ITSG Webseite
# $2 = Ordner, in dem die Zertifikate abgelegt werden sollen
function updateZertifikate {
	if [[ ! -e "$2" ]]; then echo -e "\033[31mÜbergebener Zertifikatsordner konnte nicht gefunden werden, exit...\033[0m"; exit 1; fi
	local ZERTIFIKATS_ADRESSE="$1"
	local ZERTIFIKAT_ORDNER="$2"
	local caChainFile="${2}/ca_chain_file.pem"
	# evtl simpler gestalten mit
	# fromdos gesamt-sha256.key; sed -e '$ d' -e '1i\-----BEGIN CERTIFICATE---' -e 's#^[[:blank:]]*$#-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----#g' gesamt-sha256.key >test.key; echo -n "-----END CERTIFICATE-----" >> test.key; todos test.key
	# und
	# csplit -f cert- $file '/-----BEGIN CERTIFICATE-----/' '{*}'
	ZERTIFIKATE="$(wget -c "${ZERTIFIKATS_ADRESSE}" -O -)"
	if [[ $? != 0 ]]; then echo -e "\033[31mZertifikate konnten nicht heruntergeladen werden, exit...\033[0m"; exit 1; fi
	if [[ $(echo ${ZERTIFIKATE} | wc -l) -eq 0 ]]; then echo -e "\033[31mKeine Zertifikate in der Datei???. Manuell prüfen, exit...\033[0m"; exit 1; fi
	ZERTIFIKATS_INFORMATIONEN="${ZERTIFIKAT_ORDNER}/infos.txt"; > "${ZERTIFIKATS_INFORMATIONEN}"
	if [[ ! -z "${ZERTIFIKAT_ORDNER}" ]] && [[ "${ZERTIFIKAT_ORDNER}" != "/" ]]; then find "${ZERTIFIKAT_ORDNER}" -type f -iname "*.pem" -exec rm -f {} \;; fi
	echo -n "=> schreibe Zertifikate in ${ZERTIFIKAT_ORDNER}..."
	local tempZertifikat=$(mktemp --tmpdir=/tmp file_temp_cert.XXXXXXX)
	echo -en "-----BEGIN CERTIFICATE-----\r\n" > ${tempZertifikat}
	IFS=$'\n'
	for LINE in ${ZERTIFIKATE}; do
		LINE="$(echo -n "${LINE}" | tr -d "\r\n")"
		if [[ -z "${LINE}" ]]; then
			echo -en "-----END CERTIFICATE-----\r\n" >> ${tempZertifikat}
			# https://www.openssl.org/docs/man1.0.1/apps/x509.html
			tempZertifikatsSubject="$(openssl x509 -in ${tempZertifikat} -subject -noout -certopt no_header,no_subject,no_sigdump,no_validity,no_serial,no_version,no_issuer,no_signame,no_pubkey -text)"
			if [[ ! -z "$(echo -n "${tempZertifikatsSubject}" | grep 'X509v3')" ]]; then
				tempIK="$(echo -n "${tempZertifikatsSubject}" | head -n1 | sed -r 's#.*O=(.*?)#\1#')"
				cat "${tempZertifikat}" >> "${caChainFile}"
			else
				tempIK="$(echo -n "${tempZertifikatsSubject}" | sed -r 's#.*IK([0-9]{9})/.*#\1#' | head -n1)"
			fi
			mv ${tempZertifikat} ${ZERTIFIKAT_ORDNER}/${tempIK}${ZERTIFIKAT_SUFFIX}
			chmod 755 ${ZERTIFIKAT_ORDNER}/${tempIK}${ZERTIFIKAT_SUFFIX}
			echo -e "${tempIK:4:4}\t${tempIK}${ZERTIFIKAT_SUFFIX}\t${tempZertifikatsSubject}" >> "${ZERTIFIKATS_INFORMATIONEN}"
			tempZertifikat=$(mktemp --tmpdir=/tmp file_temp_cert.XXXXXXX)
			echo -en "-----BEGIN CERTIFICATE-----\r\n" > "${tempZertifikat}"
		else
			echo -en "${LINE}\r\n" >> "${tempZertifikat}"
		fi
	done
	unset IFS
	echo " fertig"
}

# $1 = URL zur Gesamtzertifikatsdatei von der ITSG Webseite
# $2 = Ordner, in dem die Zertifikate abgelegt werden sollen
function updateGesamtZertifikate {
	if [[ ! -e "$2" ]]; then echo -e "\033[31mÜbergebener Zertifikatsordner konnte nicht gefunden werden, exit...\033[0m"; exit 1; fi
	local ZERTIFIKATS_ADRESSE="$1"
	local ZERTIFIKAT_ORDNER="$2"
	local caChainFile="${2}/ca_chain_file${ZERTIFIKAT_SUFFIX}"
	local gesamtCertFilename="$(basename $1)"
	tempRamFsMount="/mnt/ramfs"
	local MAX_PROCS=200
	trap "kill $(jobs -p | tr '\n' ' ') 2>/dev/null; sleep 2; umount /mnt/ramfs; exit" INT TERM EXIT
	mount "${tempRamFsMount}"
	if [[ $? -ne 0 ]]; then echo -e "\033[31mShared Memory konnte nicht in ${tempRamFsMount} gemountet werden.\033[0m"; exit 1; fi
	if [[ ! -z "${ZERTIFIKAT_ORDNER}" ]] && [[ "${ZERTIFIKAT_ORDNER}" != "/" ]]; then
		echo -n "=> lösche alte noch vorhandene Zertifikate aus dem Zielordner ${ZERTIFIKAT_ORDNER}... "
		find "${ZERTIFIKAT_ORDNER}" -type f \( -name "*.pem" -o -name "tempcert-*" \) -exec rm -f {} \; &
		waitSpinner $!
		echo
	fi
	wget -c "${ZERTIFIKATS_ADRESSE}" -O "${tempRamFsMount}/${gesamtCertFilename}"
	if [[ $? != 0 ]]; then echo -e "\033[31mZertifikate konnten nicht heruntergeladen werden, exit...\033[0m"; exit 1; fi
	ZERTIFIKATS_INFORMATIONEN="${tempRamFsMount}/infos.txt"; > "${ZERTIFIKATS_INFORMATIONEN}"
	fromdos "${tempRamFsMount}/${gesamtCertFilename}"; sed -e '$ d' -e '1i\-----BEGIN CERTIFICATE---' -e 's#^[[:blank:]]*$#-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----#g' "${tempRamFsMount}/${gesamtCertFilename}" >"${tempRamFsMount}/temp.key"; echo -n "-----END CERTIFICATE-----" >> "${tempRamFsMount}/temp.key"; todos "${tempRamFsMount}/temp.key"
	csplit -s -f "${tempRamFsMount}/tempcert-" "${tempRamFsMount}/temp.key" '/-----BEGIN CERTIFICATE-----/' '{*}'
	echo -n "=> schreibe Zertifikate in ${ZERTIFIKAT_ORDNER}... "
	$(for certfile in $(find "${tempRamFsMount}" -type f -name "tempcert-*"); do
		# https://www.openssl.org/docs/man1.0.1/apps/x509.html
		$(
		tempZertifikatsSubject="$(openssl x509 -in ${certfile} -subject -noout -certopt no_header,no_subject,no_sigdump,no_validity,no_serial,no_version,no_issuer,no_signame,no_pubkey -text)"
		if [[ ! -z "$(echo -n "${tempZertifikatsSubject}" | grep 'X509v3')" ]]; then
			tempIK="$(echo -n "${tempZertifikatsSubject}" | head -n1 | sed -r 's#.*O=(.*?)#\1#')"
			cat "${certfile}" >> "${caChainFile}"
		else
			tempIK="$(echo -n "${tempZertifikatsSubject}" | sed -r 's#.*IK([0-9]{9})/.*#\1#' | head -n1)"
		fi
		mv ${certfile} "${tempRamFsMount}/${tempIK}${ZERTIFIKAT_SUFFIX}"
		echo -e "${tempIK:4:4}\t${tempIK}${ZERTIFIKAT_SUFFIX}\t${tempZertifikatsSubject}" >> "${ZERTIFIKATS_INFORMATIONEN}"
		) &
		while [[ $(jobs -p | wc -l) -gt ${MAX_PROCS} ]]; do
			echo "kurz warten..."
			sleep 1
		done
	done) &
	waitSpinner $!
	wait
	rm -f "${tempRamFsMount}/temp.key"
	rm -f "${tempRamFsMount}/${gesamtCertFilename}"
	mv "${tempRamFsMount}"/* "${ZERTIFIKAT_ORDNER}"
	echo " fertig"
}
# $1 = Ordner, in dem die Zertifikatchain abgelegt werden sollen
function getRootCerts {
	if [[ ! -e "$1" ]]; then echo -e "\033[31mÜbergebener Zielordner konnte nicht gefunden werden, exit...\033[0m"; exit 1; fi
	local caChainFile="${1}/ca_chain_file${ZERTIFIKAT_SUFFIX}"
	local tempGetRootCertTemp=$(mktemp -d)
	cd "${tempGetRootCertTemp}"
	> "${caChainFile}"
	lftp -e 'open https://trustcenter-data.itsg.de/root-certs/ && mirror --continue --include-glob "*.pem" --parallel=5 --no-empty-dirs && exit'
	for tempRootCert in $(ls -1); do
		cat "${tempRootCert}" | sed -n -e '/^-----BEGIN CERTIFICATE-----$/,/^-----END CERTIFICATE-----$/p' >> "${caChainFile}"
	done
	if [[ ! -z "${tempGetRootCertTemp}" ]] && [[ "${tempGetRootCertTemp}" != "/" ]]; then rm -rf "${tempGetRootCertTemp}"; fi
}
