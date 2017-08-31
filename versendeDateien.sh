#!/bin/bash
# Das Skript basiert auf dem Dokument "Technische Anlage zum Vertrag über den Datenaustausch auf Datenträgern
# oder im Wege elektronischer Datenübertragung zwischen dem GKV-Spitzenverband und der
# Kassenzahnärztlichen Bundesvereinigung"
# https://gkv-datenaustausch.de/leistungserbringer/zahnaerzte/zahnaerzte.jsp => Technische Anlage Version 3.8 (Stand 08.12.2016) (PDF, 1,1 MB)
# Das Zeichenencoding des Skripts ist in UTF8. Von daher muss das Skript auch dementsprechend bearbeitet werden, sonst sind die Sonderzeichen kaputt
# export LANG=de_DE.utf8 und putty sollten UTF8 Zeichen schicken.
# Dieses Skript ist inspiriert durch https://github.com/tinyheb/tinyheb
# @author: Artur Lutz (a.lutz ät kzvb Punkt de)
# @license: CC0 1.0 https://creativecommons.org/publicdomain/zero/1.0/

function checkIfExists {
	if [[ ! -e ${1} ]]; then return 1; fi
}
#^-^-^-^-^-^
# Allgemein )>
#^-^-^-^-^-^
export LANG=de_DE.utf8
LANG_FUER_IO="ISO_8859-15" # in der DTA ist ISO8859-15 für die Dateien vorgesehen, wir in der KZVB verwenden den I7. Mehr Infos auf: https://www.gkv-datenaustausch.de/media/dokumente/standards_und_normen/technische_spezifikationen/Anlage_15_-_Zeichensaetze.pdf
LANG_FUER_AUSGABE="utf8"
export https_proxy="http://proxy:8080" # für wget
HOME_ORDNER="/home/datenaustausch"; checkIfExists ${HOME_ORDNER} || { echo "${HOME_ORDNER} existiert nicht."; exit 1; }
AUSFUEHRENDER_BENUTZER="datenaustausch"; if [[ ${UID} != $(id -u ${AUSFUEHRENDER_BENUTZER}) ]]; then echo "bitte als Nutzer ${AUSFUEHRENDER_BENUTZER} ausführen."; exit 1; fi
ZERTIFIKAT_ORDNER="${HOME_ORDNER}/Zertifikate"; checkIfExists ${ZERTIFIKAT_ORDNER} || mkdir -m 2755 -p ${ZERTIFIKAT_ORDNER}
EIGENE_IK_NUMMER="218200101"
ZERTIFIKAT_SUFFIX=".pem"
EIGENE_DATEN_ORDNER="${HOME_ORDNER}/Eigene_Daten"; checkIfExists ${EIGENE_DATEN_ORDNER} || mkdir -m 2755 -p ${EIGENE_DATEN_ORDNER}
TEMP_ORDNER="${HOME_ORDNER}/tmp"; checkIfExists ${TEMP_ORDNER} || mkdir -m 2755 -p ${TEMP_ORDNER}
LOG_ORDNER="${HOME_ORDNER}/Logs"; checkIfExists ${LOG_ORDNER} || mkdir -m 2755 -p ${LOG_ORDNER}
ZERTIFIKATS_ADRESSE="https://trustcenter-data.itsg.de/dale/gesamt-sha256.key"
EOF_INDIKATOR="$(echo -en "\x1A")" # SUB (subsitute)
STARTZEIT="$(date +%Y-%m-%d_%H_%M_%S)"
#^-^-^-^-^-^
# openssl   )>
#^-^-^-^-^-^
OPENSSL_CIPHER_SWITCH="-aes-256-cbc" # siehe "openssl enc -help"
ENCRYPTED_ORDNER_SUFFIX="_enc"
OUTFORM="DER"
SIGNIERT_SUFFIX=".sig"
TEMP_ORDNER_OPENSSL="/tmp"
PRIVATE_KEY="${EIGENE_DATEN_ORDNER}/${EIGENE_IK_NUMMER}.key" 
EIGENES_ZERTIFIKAT="${EIGENE_DATEN_ORDNER}/${EIGENE_IK_NUMMER}.cer.own"
EIGENES_ZERTIFIKAT_CAs="${EIGENE_DATEN_ORDNER}/${EIGENE_IK_NUMMER}.cer.ca"
EMAIL_FROM="emailadresse@kzvb.de"
#^-^-^-^-^-^
# Versand )>
#^-^-^-^-^-^
# https://www.gkv-datenaustausch.de/media/dokumente/standards_und_normen/technische_spezifikationen/Anlage_9_-_ftp_sftp_ftps.pdf Seite 10:
KASSEN_ADRESSEN="/pfad/zu/Adressen.csv"
ZUSATZ_INFOS="${EIGENE_DATEN_ORDNER}/Zusatz.txt"; if [[ ! -e "${ZUSATZ_INFOS}" ]]; then { echo "Datei "${ZUSATZ_INFOS}" existiert nicht"; exit 1; }; fi
TRANSFERNUMMER_COUNTER_DATEI="${EIGENE_DATEN_ORDNER}/Transfernummern.txt"; checkIfExists ${TRANSFERNUMMER_COUNTER_DATEI} || touch ${TRANSFERNUMMER_COUNTER_DATEI}
TESTVERFAHREN= # Leerstring bedeutet, dass die Dateien nach VERFAHREN_KENNUNG (TKZV0 oder EKZV0) aus der AUF Datei verschickt werden. Wenn nicht leer, dann wird egal was in VERFAHREN_KENNUNG steht die Daten als Testdaten verschickt und das auch in die AUF Datei geschrieben. Nach einem Testverfahren muss noch "encrypt" ausgeführt werden, weil ja sonst in den AUF Dateien TKZV0 drinsteht.
#^-^-^-^-^-^
# Datenbank )>
#^-^-^-^-^-^
DB_USER="SCHEMA"
source "${HOME_ORDNER}/Libs/datenbank.lib.sh"

# Reihenfolge ist wichtig, da in späteren Bibliotheken auf diese Funktionen schon zugreifen
source "${HOME_ORDNER}/Libs/strings.lib.sh"
source "${HOME_ORDNER}/Libs/kassenkommunikationssystem_AUF_Definition.lib.sh"
source "${HOME_ORDNER}/Libs/kassenkommunikationssystem_io.lib.sh"
source "${HOME_ORDNER}/Libs/kassenkommunikationssystem_sftp.lib.sh"
source "${HOME_ORDNER}/Libs/kassenkommunikationssystem_pki.lib.sh"

function usage {
cat <<EOF
Aufruf: ./${0##*/} <Parameter>
mögliche Parameter:
	- update
		Die Zertifikate werden von der ITSG heruntergeladen und ins Verzeichnis ${ZERTIFIKAT_ORDNER} abgespeichert.
		Jede Annahmestelle wird in eine eigene Datei geschrieben. Der Name der Datei ist die IK Nummer plus pem Suffix.
		Ein Zertifikat heißt dann z.B. 218200101.pem. Diese x509 Zertifikate werden verwendet um die Kassenausgangs-
		dateien zu verschlüsseln.
	- updateRootCerts
		Holt die Root Zertifikate von der ITSG Website und speichert sie in das Chainfile ${ZERTIFIKAT_ORDNER}/ca_chain_file.pem
	- encrypt <Abrechnungstyp: KCH oder PAR_KB_ZE> <Abrechnungszeitraum: YYYYMM oder YYYY0Q>
		Beispiel: ./${0##*/} encrypt KCH 201604
			  ./${0##*/} encrypt PAR_KB_ZE 201612
	- test
		Testet die sftp Server der Annahmestellen und gibt aus ob die Verbindung funktioniert und das Verzeichnis existiert
	- versende <Abrechnungstyp: KCH oder PAR_KB_ZE> <Abrechnungszeitraum: YYYYMM oder YYYY0Q> [Kassennummer]
		Versendet alle Kassenausgangsdateien an die entsprechenden Annahmestellen. Die Informationen kommen aus den
		Stammdaten. Ist eine Übertragung fehlerhaft, muss das Skript nochmals mit den gleichen Parametern aufgerufen werden.
		Das Skript überträgt dann nur die fehlerhaften Dateien neu.
		Soll nur eine Kassennummer geschickt werden muss der optionale Parameter [Kassennummer] mit angegeben werden.
		Beispiele: ./${0##*/} versende KCH 201604
		           ./${0##*/} versende PAR_KB_ZE 201612
		           ./${0##*/} versende PAR_KB_ZE 201612 1040
	- versendeEinzelneDatei <absoluter Pfad> <Verfahren> <Empfänger IK>
		Beispiel: ./${0##*/} versendeEinzelneDatei /filesysteme/oradb_tmp/kzv_tmp/test.txt E1Z10 108310400
	- print <Auftragsdatei>
		Beispiel: ./${0##*/} print /home/dta_kk/tmp/Z119561G.AUF
	- check <Auftragsdatei>
		Beispiel: ./${0##*/} check /home/dta_kk/tmp/Z119561G.AUF
	- schreibe <Auftragsdatei> <Wert> <Bezeichner>
		Beispiel: ./${0##*/} schreibe /home/dta_kk/tmp/Z119561G.AUF beispiel.csv DATEI_BEZEICHNUNG
EOF
exit 1
}
function cleanup {
	echo "=> aufräumen..."
	cd ~
	rm -f "${TEMP_ORDNER_OPENSSL}/"*.sig # lösche übrige signierte Kassenausgangsdateien
	rm -f "${TEMP_ORDNER_OPENSSL}/"*.comp.gz # lösche übrige komprimierte Kassenausgangsdateien
	#rm -f "${TEMP_ORDNER}/"*.AUF # beim Einzelversand von Dateien werden hier die temporären AUF Dateien abgelegt 
	exit
}
trap cleanup INT TERM

#^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^
# Kassenausgangsdateien verschlüsseln oder versenden)>
#^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^-^
function verschluesseleOderVersendeDateien {
	VERSENDEN_ODER_VERSCHLUESSELN="${1}"
	ABRECHNUNGSTYP=${2^^}
	ABRECHUNGSZEITRAUM=${3^^}
	EINZELNE_KASSE=${4} # optionaler Parameter
	# benötigte Informationen zu den Annahmestellen aus der Datenbank holen
	if [[ ! "${ABRECHNUNGSTYP}" =~ KCH|PAR_KB_ZE ]] || [[ -z ${ABRECHUNGSZEITRAUM} ]]; then
		usage
	fi
	init_KassenAdressenDatei
	if [[ "${VERSENDEN_ODER_VERSCHLUESSELN}" == "versende" ]]; then
		local vorhandeneAnnahmestellen=$(awk '{FS=";"} $20 == "ja" {print $22}' "${KASSEN_ADRESSEN}" | awk '!x[$0]++' | tr '.,' '_' | sed 's/^/var/')
		# hier werden dynamische Variablen generiert wie hier beschrieben: http://stackoverflow.com/a/16553351
		# Wenn im Counter-File nicht vorhanden hinzufügen und mit 1 anlegen, ansonsten dort rausgrepen und auch die variable Variable erstellen
		for i in $(echo -e ${vorhandeneAnnahmestellen}); do
			if [[ -z "$(grep ${i} ${TRANSFERNUMMER_COUNTER_DATEI})" ]]; then
				#echo "${i} wird zur Datei ${TRANSFERNUMMER_COUNTER_DATEI} hinzugefügt"
				echo "${i}=1" >> ${TRANSFERNUMMER_COUNTER_DATEI}
				declare -x "${i}=1"
			else
				#echo "counter für ${i} wird aus der Datei ${TRANSFERNUMMER_COUNTER_DATEI} ausgelesen"
				declare -x "${i}=$(grep ${i} ${TRANSFERNUMMER_COUNTER_DATEI} | cut -d"=" -f2)"
			fi	
			#echo "Variablennamen ${i} | Variablenwert ${!i}"
		done
	fi
	declare -a alleLogDateien
	local tempGesamtAdressen=$(sed 's/$/\\n/' "${KASSEN_ADRESSEN}" | tr -d "\r\n")
	MONAT_ODER_QUARTAL=$(echo ${ABRECHUNGSZEITRAUM} | cut -c 5-6)
	JAHR=$(echo ${ABRECHUNGSZEITRAUM} | cut -c 1-4)
	local bundesaersche_counter=0
	for i in $(echo -n ${ABRECHNUNGSTYP,,} | tr '_' ' '); do
		if [[ "${i}" == "kch" ]]; then
			PFAD_ZU_DTA_DATEIEN="/exp_sich/ausgang/smk/kch/${JAHR}${MONAT_ODER_QUARTAL}"
		else
			PFAD_ZU_DTA_DATEIEN="/nfs_fs1/puffer/${i}/${MONAT_ODER_QUARTAL}${JAHR}/kassenausgang"
		fi
		checkIfExists "${PFAD_ZU_DTA_DATEIEN}" || { echo -e "\033[31mKassenausgangsverzeichnis ${PFAD_ZU_DTA_DATEIEN} existiert nicht, breche ab.\033[0m"; exit 1; }
		GENERAL_LOG="${LOG_ORDNER}/${i^^}_${ABRECHUNGSZEITRAUM}_${VERSENDEN_ODER_VERSCHLUESSELN}$([[ ! -z ${EINZELNE_KASSE} ]] && echo -n "_${EINZELNE_KASSE}_${STARTZEIT}").txt"
		if [[ "${VERSENDEN_ODER_VERSCHLUESSELN,,}" == "encrypt" ]]; then > "${GENERAL_LOG}"; fi
		# checken, ob die Logdatei schon angelegt ist, wenn ja dann schauen, ob sie ein EOF als letzte Zeile hat oder noch unvollständig ist
		if [[ "${VERSENDEN_ODER_VERSCHLUESSELN}" == "versende" ]]; then
			if [[ -e "${GENERAL_LOG}" ]] && [[ "$(tail -n 1 "${GENERAL_LOG}")" == ${EOF_INDIKATOR} ]] && [[ -z "$(grep "wurde fehlerhaft am .* um .* gesendet" "${GENERAL_LOG}")" ]]; then
				echo "für ${i^^} ${ABRECHUNGSZEITRAUM} wurde schon alles hochgeladen. Es gibt nur noch die Möglichkeit einzelne Kassen erneut forciert hochzuladen."
				continue
			elif [[ -e "${GENERAL_LOG}" ]] && [[ ! -z "$(grep "wurde fehlerhaft am .* um .* gesendet" "${GENERAL_LOG}")" ]]; then
				local fehlerhafteLogeintraege="$(grep "wurde fehlerhaft am .* um .* gesendet" "${GENERAL_LOG}" | sed -e '/^$/d' -e 's/$/\\n/')"
				local fehlerhafteNutzdateien="$(echo -ne ${fehlerhafteLogeintraege} | sed -e 's/.*Nutzdatei \(.*\) und.*/\1/' -e '/^$/d' -e 's/$/\\n/')"
			fi
			if [[ -e "${GENERAL_LOG}" ]]; then
				local erfolgreicheLogeintrage="$(grep "wurde erfolgreich am .* um .* gesendet" "${GENERAL_LOG}" | sed 's/$/\\n/')"
			fi
		fi
		alleLogDateien+=("${GENERAL_LOG}")
		# hier die Kassennummern aus der Ordnerstruktur auslesen
		if [[ -z ${EINZELNE_KASSE} ]]; then
			local tempOrdner="$(ls -1 "${PFAD_ZU_DTA_DATEIEN}" | sed -re '/^[0-9]{4}$/!d' | tr '\n' ' ')"
		else
			local tempOrdner="${EINZELNE_KASSE}"
		fi
		for kassen_nr in ${tempOrdner}; do
			kassen_nr=$(removeLeadingAndTrailingSpaces ${kassen_nr})
			local kassenInformationen=$(konvertiereZuCharset "$(echo -e "${tempGesamtAdressen}" | grep $([ "${ABRECHNUNGSTYP}" = "KCH" ] && echo KCH- || echo ZE-ABR) | sed -e '/^'${kassen_nr}'/!d' | tr -d '\r\n')" "${LANG_FUER_IO}" "${LANG_FUER_AUSGABE}")
			local kassenNrEncryptedPfad="${PFAD_ZU_DTA_DATEIEN}/${kassen_nr}${ENCRYPTED_ORDNER_SUFFIX}"
			if [[ "${VERSENDEN_ODER_VERSCHLUESSELN,,}" == "encrypt" ]]; then
				###################
				# Verschlüsselung 
				###################
				# wenn die Kasse keine Verschlüsselten Dateien annimmt, wird der Ordner einfach übersprungen
				if [[ "$(echo -n "${kassenInformationen}" | cut -d\; -f 21)" == "nein" ]]; then continue; fi
				# Ordner für die verschlüsselten Dateien anlegen
				mkdir -m 2775 -p "${kassenNrEncryptedPfad}"
				if [[ -z $(find "${PFAD_ZU_DTA_DATEIEN}/${kassen_nr}/" -type f) ]]; then
					echo -e "${kassen_nr}:\n\tkeine Dateien vorhanden" | tee -a "${GENERAL_LOG}"
				else
					echo "${kassen_nr}:" | tee -a "${GENERAL_LOG}"
					# ausgeben der Annahmestelle
					local tempAnnahmestelle=$(echo -n "${kassenInformationen}" | cut -d\; -f 7-9 | sed 's#;# - #g')
					local tempCompress=$(echo -n "${kassenInformationen}" | cut -d\; -f 26)
					echo -e "\t\033[94mAnnahmestelle: ${tempAnnahmestelle}\033[0m" | tee -a "${GENERAL_LOG}"
					local tempZertifikat="$(echo -n "${kassenInformationen}" | grep ^${kassen_nr} | cut -d\; -f 2 | tr -d [:alpha:])"
					local tempZertifikatInhalt="$(echo -n "${kassenInformationen}" | grep ^${kassen_nr} | cut -d\; -f 28)"
					# Ausnahme für die Bundespolizei und Bundeswehr hinzufügen, weil diese ihren Public Key nicht auf der ITSG Seite hat oder unter einer anderen IK
					if [[ ! -z "${tempZertifikatInhalt}" ]]; then
						echo -n "${tempZertifikatInhalt}" | sed -e 's/-----BEGIN CERTIFICATE-----/&\r\n/g' -e 's/-----END CERTIFICATE-----/\r\n&/g' | sed 's/.\{64\}/&\r\n/g' > "${ZERTIFIKAT_ORDNER}/${tempZertifikat}${ZERTIFIKAT_SUFFIX}"
					fi
					# eine weitere Ausnahme für die DAK hinzufügen, weil in der Nutzdatei und STD IK101560000 und in der AUF 104593971 drin steht.
					if [[ "${kassen_nr}" == "6000" ]]; then
						tempZertifikat="104593971"
					fi
					# überprüfen, ob ein Zertifikat vorhanden ist, ansonsten gleich abbrechen, denn das dürfte nicht passieren
					if [[ ! -e "${ZERTIFIKAT_ORDNER}/${tempZertifikat}${ZERTIFIKAT_SUFFIX}" ]]; then
						echo -e "\033[31m${kassen_nr}: kein Zertifikat für die Annahmestelle gefunden. Erst im STD klären, ob für ${kassen_nr} eine Annahmestelle eingetragen ist, die am DFÜ DTA teilnimmt.\033[0m"; exit 1
					else
						tempZertifikat="${ZERTIFIKAT_ORDNER}/${tempZertifikat}${ZERTIFIKAT_SUFFIX}"
					fi
					echo -e "\tverwendetes Zertifikat: ${tempZertifikat}" | tee -a "${GENERAL_LOG}"
					# kopiere AUF Dateien in den entsprechenden _enc Ordner
					\cp -p "${PFAD_ZU_DTA_DATEIEN}/${kassen_nr}/"*.AUF "${kassenNrEncryptedPfad}/"
					# verschlüssele Nutzdateien und speicher diese Dateien in den entsprechenden _enc Ordner
					local tempDateien=$(find "${PFAD_ZU_DTA_DATEIEN}/${kassen_nr}/" -type f ! -iname "*.AUF")
					IFS=$'\n'
					for einzelneAbrDatei in ${tempDateien}; do
						local einzelneAbrDateiEncrypted="$(echo -n ${kassenNrEncryptedPfad}/${einzelneAbrDatei##*/})"
						local einzelneAbrDateiAufEncrypted="${einzelneAbrDateiEncrypted}.AUF"
						# die AUF Datei umbenennen, damit sie so heißt: <logischerDateiname>.AUF
						if [[ ! -e ${einzelneAbrDateiAufEncrypted} ]]; then
							mv -f "${einzelneAbrDateiEncrypted%%.*}.AUF" "${einzelneAbrDateiAufEncrypted}"
						fi
						# Ausnahme für die Bundespolizei und Bundeswehr hinzufügen, die werden noch per CD beliefert und dort können die Transfernamen nicht "on the fly" generiert werden
						if [[ "${kassen_nr}" == "9301" ]] || [[ "${kassen_nr}" == "0034" ]]; then
							((bundesaersche_counter++))
							einzelneAbrDateiEncrypted="${kassenNrEncryptedPfad}/$(leseVonAufDatei "${einzelneAbrDateiAufEncrypted}" "VERFAHREN_KENNUNG" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}")$(printf "%03d" "${bundesaersche_counter}")"
							mv -f "${einzelneAbrDateiAufEncrypted}" "${einzelneAbrDateiEncrypted%%.*}.AUF"
							einzelneAbrDateiAufEncrypted="${einzelneAbrDateiEncrypted}.AUF"
						fi
						if [[ ${tempCompress} == "ja" ]]; then
							printf "\t% -82s" "=> komprimiere ${einzelneAbrDatei}..." | tee -a "${GENERAL_LOG}"
							cat "${einzelneAbrDatei}" | gzip --best > "${TEMP_ORDNER_OPENSSL}/${einzelneAbrDatei##*/}.comp.gz"
							if [[ $? != 0 ]]; then
								echo -e "\033[31mfehlgeschlagen\033[0m" | tee -a "${GENERAL_LOG}"
							else
								echo -e "\033[32merfolgreich\033[0m" | tee -a "${GENERAL_LOG}"
							fi
							# schreibe in die AUF Datei, dass komprimiert wurde
							# 02 = gzip laut https://www.gkv-datenaustausch.de/media/dokumente/standards_und_normen/technische_spezifikationen/Anlage_2_-_Auftragsdatei.pdf
							schreibeInAufDatei "${einzelneAbrDateiAufEncrypted}" "02" "KOMPRIMIERUNG" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
							printf "\t% -82s" "=> signiere ${TEMP_ORDNER_OPENSSL}/${einzelneAbrDatei##*/}.comp.gz..." | tee -a "${GENERAL_LOG}"
							openssl cms -sign -binary -in "${TEMP_ORDNER_OPENSSL}/${einzelneAbrDatei##*/}.comp.gz" -nodetach -outform ${OUTFORM} -from "${EMAIL_FROM}" -signer "${EIGENES_ZERTIFIKAT}" -inkey "${PRIVATE_KEY}" -certfile "${EIGENES_ZERTIFIKAT_CAs}" -out "${TEMP_ORDNER_OPENSSL}/${einzelneAbrDatei##*/}${SIGNIERT_SUFFIX}"
							local signierResult=$?
						else
							printf "\t% -82s" "=> signiere ${einzelneAbrDatei}..." | tee -a "${GENERAL_LOG}"
							openssl cms -sign -binary -in ${einzelneAbrDatei} -nodetach -outform ${OUTFORM} -from "${EMAIL_FROM}" -signer "${EIGENES_ZERTIFIKAT}" -inkey "${PRIVATE_KEY}" -certfile "${EIGENES_ZERTIFIKAT_CAs}" -out "${TEMP_ORDNER_OPENSSL}/${einzelneAbrDatei##*/}${SIGNIERT_SUFFIX}"
							local signierResult=$?
						fi
						if [[ ${signierResult} != 0 ]]; then
							echo -e "\033[31mfehlgeschlagen\033[0m" | tee -a "${GENERAL_LOG}"
						else
							echo -e "\033[32merfolgreich\033[0m" | tee -a "${GENERAL_LOG}"
						fi
						printf "\t% $((-82-$(getByteDifferenceBetweenCharsets "=> verschlüssele ${TEMP_ORDNER_OPENSSL}/${einzelneAbrDatei##*/}${SIGNIERT_SUFFIX}..." "${LANG}")))s" "=> verschlüssele ${TEMP_ORDNER_OPENSSL}/${einzelneAbrDatei##*/}${SIGNIERT_SUFFIX}..." | tee -a "${GENERAL_LOG}"
						openssl cms -encrypt -binary -in "${TEMP_ORDNER_OPENSSL}/${einzelneAbrDatei##*/}${SIGNIERT_SUFFIX}" ${OPENSSL_CIPHER_SWITCH} -outform ${OUTFORM} -out "${einzelneAbrDateiEncrypted}" "${tempZertifikat}"
						if [[ $? != 0 ]]; then
							echo -e "\033[31mfehlgeschlagen\033[0m" | tee -a "${GENERAL_LOG}"
						else
							echo -e "\033[32merfolgreich\033[0m\n\t\tZiel: ${einzelneAbrDateiEncrypted}" | tee -a "${GENERAL_LOG}"
							# schreibe die IK Nummer beim ABSENDER rein statt KZV11
							schreibeInAufDatei "${einzelneAbrDateiAufEncrypted}" "${EIGENE_IK_NUMMER}" "ABSENDER_EIGNER" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
							schreibeInAufDatei "${einzelneAbrDateiAufEncrypted}" "${EIGENE_IK_NUMMER}" "ABSENDER_PHYSIKALISCH" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
							# schreibe die größe der signierten und verschlüsselten Nutzdatei in die AUF Datei
							schreibeInAufDatei "${einzelneAbrDateiAufEncrypted}" $(du -b "${einzelneAbrDateiEncrypted}" | awk '{print $1}' | tr -d '\n') "DATEIGROESSE_UEBERTRAG" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
							# schreibe in die AUF Datei, dass die Daten jetzt signiert und verschlüsselt sind
							schreibeInAufDatei "${einzelneAbrDateiAufEncrypted}" "03" "VERSCHLUESSELUNGSART" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
							schreibeInAufDatei "${einzelneAbrDateiAufEncrypted}" "03" "ELEKTRONISCHE_UNTERSCHR" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
							# schreibe die Emailadresse in die AUF Datei
							schreibeInAufDatei "${einzelneAbrDateiAufEncrypted}" "${EMAIL_FROM}" "DATEINAME_PHYSIK" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
						fi
					done
					unset IFS
				fi
			else
				# wenn die Kasse nicht am DTA DFÜ teilnimmt wird der Ordner einfach übersprungen
				if [[ "$(echo -n "${kassenInformationen}" | cut -d\; -f 20)" == "nein" ]]; then continue; fi
				##########
				# Versand 
				##########
				transferLog="${LOG_ORDNER}/${i^^}_${ABRECHUNGSZEITRAUM}$([[ ! -z ${EINZELNE_KASSE} ]] && echo -n "_${EINZELNE_KASSE}")_sftp_sessions_${STARTZEIT}.txt"
				if [[ -z $(find "${PFAD_ZU_DTA_DATEIEN}/${kassen_nr}_enc/" -type f) ]]; then
					if [[ -e ${GENERAL_LOG} ]]; then
						echo -e "${kassen_nr}:\n\tkeine Dateien vorhanden"
					else
						echo -e "${kassen_nr}:\n\tkeine Dateien vorhanden" | tee -a "${GENERAL_LOG}"
					fi
				else
					local displayOnce=true
					# ausgeben der Annahmestelle
					local tempAnnahmestelle=$(echo -n "${kassenInformationen}" | cut -d\; -f 7-9 | sed 's#;# - #g')
					#local tempIP="datentausch2.intern.kzvb.de"
					local tempIP=($(echo -n "${kassenInformationen}" | cut -d\; -f 22 | tr ',' ' '))
					#local tempPort=3322
					local tempPort=$(echo -n "${kassenInformationen}" | cut -d\; -f 23)
					#local tempPfad="/"
					local tempPfad=$(echo -n "${kassenInformationen}" | cut -d\; -f 24)
					#local tempBenutzer="kubusit"
					local tempBenutzer=$(echo -n "${kassenInformationen}" | cut -d\; -f 25)
					local tempPasswort=$(echo -n "${kassenInformationen}" | cut -d\; -f 27); [[ "${tempPasswort}" == "" ]] && tempPasswort=" "
					local tempAnnahmestelleIK="$(echo -n "${kassenInformationen}" | grep ^${kassen_nr} | cut -d\; -f 22 | tr '.,' '_' | sed 's/^/var/')"
					# nun die Nutzdaten hochladen, die AUF anpassen und dann hochladen und Counterstand abspeichern
					local tempDateien=$(find "${PFAD_ZU_DTA_DATEIEN}/${kassen_nr}_enc/" -type f ! -iname "*.AUF")
					IFS=$'\n'
					for einzelneAbrDatei in ${tempDateien}; do
						local einzelneAbrDateiEncrypted="$(echo -n ${kassenNrEncryptedPfad}/${einzelneAbrDatei##*/})"
						local einzelneAbrDateiAufEncrypted="${einzelneAbrDateiEncrypted}.AUF"
						erneuterVersuch=false
						if [[ ! -z "$(echo -e ${fehlerhafteNutzdateien} | grep ${einzelneAbrDatei##*/})" ]]; then
							erneuterVersuch=true
							displayOnce=false # bei erneuten Versuchen auch nur den erneuten Versuch anzeigen
							echo "erneuter Versuch bei Datei: $(echo -e ${fehlerhafteNutzdateien} | grep ${einzelneAbrDatei##*/})"
						elif [[ ! -z "$(echo -e ${erfolgreicheLogeintrage} | grep ${einzelneAbrDatei##*/})" ]]; then
							displayOnce=false # bei unvollständigen Ausführen soll die Kassennr und Annahmestelle auch nicht gelogt werden
							continue # die Datei wurde schon erfolgreich übertragen, überspringen...
						fi
						if [[ ${displayOnce} == true ]]; then { echo "${kassen_nr}:" | tee -a "${GENERAL_LOG}"; echo -e "\t\033[94mAnnahmestelle: ${tempAnnahmestelle} | IP: ${tempIP[@]} | Port: ${tempPort} | Upload-Ordner: ${tempPfad} \033[0m" | tee -a "${GENERAL_LOG}"; displayOnce=false; }; fi
						if [[ -z ${TESTVERFAHREN} ]]; then
							local transferNamen="$(leseVonAufDatei "${einzelneAbrDateiAufEncrypted}" "VERFAHREN_KENNUNG" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}")$(printf "%03d" "${!tempAnnahmestelleIK}")"
						else
							local transferNamen="TKZV0$(printf "%03d" "${!tempAnnahmestelleIK}")"
							schreibeInAufDatei "${einzelneAbrDateiAufEncrypted}" "TKZV0" "VERFAHREN_KENNUNG" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
						fi
						local uebertragungszeitpunkt=$(date +%Y%m%d%H%M%S)
						local versandResultatNutzdatei=""
						# wenn es eine erneute Übertragung ist, hole aus der Logdatei den Transfernamen raus und sende es damit neu
						if [[ "${erneuterVersuch}" == true ]]; then
							printf "\t% $((-110-$(getByteDifferenceBetweenCharsets "=> versende ${einzelneAbrDatei} als $(echo -e ${fehlerhafteLogeintraege} | grep "${einzelneAbrDatei##*/}" | awk '{FS=" "} {print $7}')..." "${LANG}")))s" "=> versende ${einzelneAbrDatei} als $(echo -e ${fehlerhafteLogeintraege} | grep "${einzelneAbrDatei##*/}" | awk '{FS=" "} {print $7}')..."
							versendePerSFTP "${einzelneAbrDatei}" "tempIP" ${tempPort} "${tempPfad}" "${tempBenutzer}" "${tempPasswort}" "$(echo -e ${fehlerhafteLogeintraege} | grep "${einzelneAbrDatei##*/} " | awk '{FS=" "} {print $7}')" "${transferLog}"
							versandResultatNutzdatei=$?
						else
							printf "\t% $((-110-$(getByteDifferenceBetweenCharsets "=> versende ${einzelneAbrDatei} als ${transferNamen}..." "${LANG}")))s" "=> versende ${einzelneAbrDatei} als ${transferNamen}..." | tee -a "${GENERAL_LOG}"
							versendePerSFTP "${einzelneAbrDatei}" "tempIP" ${tempPort} "${tempPfad}" "${tempBenutzer}" "${tempPasswort}" "${transferNamen}" "${transferLog}"
							versandResultatNutzdatei=$?
						fi
						if [[ "${erneuterVersuch}" == true ]]; then
							if [[ ${versandResultatNutzdatei} -ne 0 ]]; then
								echo -e "\033[31mfehlgeschlagen\033[0m"
								sed -i '/\/'"${einzelneAbrDatei##*/} als"'/ s#\.\.\..*$#...         '$(echo -en "\033[31mfehlgeschlagen\033[0m")'#' "${GENERAL_LOG}"
							else
								echo -e "\033[32merfolgreich\033[0m"
								sed -i '/\/'"${einzelneAbrDatei##*/} als"'/ s#\.\.\..*$#...         '$(echo -en "\033[32merfolgreich\033[0m")'#' "${GENERAL_LOG}"
							fi
						else
							# die Transfernummer in die AUF Datei schreiben, damit sie später noch vorhanden ist
							schreibeInAufDatei "${einzelneAbrDateiAufEncrypted}" ${!tempAnnahmestelleIK} "TRANSFER_NUMMER" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
							# zähle den Counter für die Annahmestelle hoch
							declare -x "${tempAnnahmestelleIK}=$((${!tempAnnahmestelleIK}+1))"
							# schreibe den Transfercounter zurück in die Transfernummerndatei
							if [[ ${!tempAnnahmestelleIK} -eq 1000 ]]; then 
								declare -x "${tempAnnahmestelleIK}=1"
							fi
							sed -i '/^'${tempAnnahmestelleIK}'/ s/[0-9]*$/'${!tempAnnahmestelleIK}'/' ${TRANSFERNUMMER_COUNTER_DATEI}
							if [[ ${versandResultatNutzdatei} -ne 0 ]]; then
								echo -e "\033[31mfehlgeschlagen\033[0m" | tee -a "${GENERAL_LOG}"
							else
								echo -e "\033[32merfolgreich\033[0m" | tee -a "${GENERAL_LOG}"
							fi
						fi
						#echo -e "\tDateitransfer Nummer: ${!tempAnnahmestelleIK} für Annahmestelle ${tempAnnahmestelleIK}" | tee -a "${GENERAL_LOG}"
						schreibeInAufDatei "${einzelneAbrDateiAufEncrypted}" "${uebertragungszeitpunkt}" "DATUM_UEBER_GESENDET" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
						local versandResultatAufDatei=""
						if [[ "${erneuterVersuch}" == true ]]; then
							printf "\t% $((-110-$(getByteDifferenceBetweenCharsets "=> versende ${einzelneAbrDateiAufEncrypted} als $(echo -e ${fehlerhafteLogeintraege} | grep "${einzelneAbrDatei##*/}" | awk '{FS=" "} {print $7}').AUF..." "${LANG}")))s" "=> versende ${einzelneAbrDateiAufEncrypted} als $(echo -e ${fehlerhafteLogeintraege} | grep "${einzelneAbrDatei##*/}" | awk '{FS=" "} {print $7}').AUF..."
							versendePerSFTP "${einzelneAbrDateiAufEncrypted}" "tempIP" ${tempPort} "${tempPfad}" "${tempBenutzer}" "${tempPasswort}" "$(echo -e ${fehlerhafteLogeintraege} | grep "${einzelneAbrDatei##*/}" | awk '{FS=" "} {print $7}').AUF" "${transferLog}"
							versandResultatAufDatei=$?
						else
							printf "\t% $((-110-$(getByteDifferenceBetweenCharsets "=> versende ${einzelneAbrDateiAufEncrypted} als ${transferNamen}.AUF..." "${LANG}")))s" "=> versende ${einzelneAbrDateiAufEncrypted} als ${transferNamen}.AUF..." | tee -a "${GENERAL_LOG}"
							versendePerSFTP "${einzelneAbrDateiAufEncrypted}" "tempIP" ${tempPort} "${tempPfad}" "${tempBenutzer}" "${tempPasswort}" "${transferNamen}.AUF" "${transferLog}"
							versandResultatAufDatei=$?
						fi
						if [[ "${erneuterVersuch}" == true ]]; then
							if [[ ${versandResultatAufDatei} -ne 0 ]]; then
								echo -e "\033[31mfehlgeschlagen\033[0m"
								sed -i '/\/'"$(echo -n ${einzelneAbrDatei##*/} | cut -f1 -d'.').AUF "'/ s#\.\.\..*$#... '$(echo -en "\033[31mfehlgeschlagen\033[0m")'#' "${GENERAL_LOG}"
							else
								echo -e "\033[32merfolgreich\033[0m"
								sed -i '/\/'"$(echo -n ${einzelneAbrDatei##*/} | cut -f1 -d'.').AUF "'/ s#\.\.\..*$#... '$(echo -en "\033[32merfolgreich\033[0m")'#' "${GENERAL_LOG}"
							fi
						else
							if [[ ${versandResultatAufDatei} != 0 ]]; then
								echo -e "\033[31mfehlgeschlagen\033[0m" | tee -a "${GENERAL_LOG}"
							else
								echo -e "\033[32merfolgreich\033[0m" | tee -a "${GENERAL_LOG}"
							fi
						fi
						if [[ "${erneuterVersuch}" == true ]]; then
							if [[ ${versandResultatAufDatei} -eq 0 ]] || [[ ${versandResultatNutzdatei} -eq 0 ]]; then
								sed -i '/Tupel mit Nutzdatei '"${einzelneAbrDatei##*/}"'/ s#.*$#'$(echo -en "\t\033[32mTupel mit Nutzdatei ${einzelneAbrDatei##*/} und Transfernamen $(echo -e ${fehlerhafteLogeintraege} | grep "${einzelneAbrDatei##*/}" | awk '{FS=" "} {print $7}') wurde erfolgreich am $(date +%Y-%m-%d) um $(date +%H:%M:%S) gesendet\033[0m")'#' "${GENERAL_LOG}"
							else
								sed -i '/Tupel mit Nutzdatei '"${einzelneAbrDatei##*/}"'/ s#.*$#'$(echo -en "\t\033[31mTupel mit Nutzdatei ${einzelneAbrDatei##*/} und Transfernamen $(echo -e ${fehlerhafteLogeintraege} | grep "${einzelneAbrDatei##*/}" | awk '{FS=" "} {print $7}') wurde fehlerhaft am $(date +%Y-%m-%d) um $(date +%H:%M:%S) gesendet\033[0m")'#' "${GENERAL_LOG}"
							fi
						else
							if [[ ${versandResultatAufDatei} -eq 0 ]] || [[ ${versandResultatNutzdatei} -eq 0 ]]; then
								echo -e "\t\033[32mTupel mit Nutzdatei ${einzelneAbrDatei##*/} und Transfernamen ${transferNamen} wurde erfolgreich am $(date +%Y-%m-%d) um $(date +%H:%M:%S) gesendet\033[0m" | tee -a "${GENERAL_LOG}"
							else
								echo -e "\t\033[31mTupel mit Nutzdatei ${einzelneAbrDatei##*/} und Transfernamen ${transferNamen} wurde fehlerhaft am $(date +%Y-%m-%d) um $(date +%H:%M:%S) gesendet\033[0m"  | tee -a "${GENERAL_LOG}"
							fi
						fi
					done
					unset IFS
				fi
			fi
		done
		if [[ "$(tail -n1 "${GENERAL_LOG}")" != "${EOF_INDIKATOR}" ]]; then echo -n "${EOF_INDIKATOR}" >> "${GENERAL_LOG}"; fi
	done
	# zwinge den Ausführer die Logs anzuschauen
	if [[ ! ${#alleLogDateien[@]} -eq 0 ]]; then
		less -r ${alleLogDateien[@]}
	fi
}
function versendeEinzelneDatei {
	if [[ $# -ne 3 ]]; then
		usage
	fi
	if [[ ! -r "${1}" ]]; then
		echo -e "\033[31mFile existiert nicht oder kann nicht gelesen werden.\033[0m"
		usage
	fi
	local dateipfadEinzeldatei="${1}"
	local isValidVerfahren=1
	for validVerfahren in ${ERLAUBTE_VERFAHREN[@]}; do # ERLAUBTE_VERFAHREN wird durch kassenkommunikationssystem_AUF_Definition.lib.sh gesetzt
		if [[ ! -z "$(echo -n "${2}" | grep -E "${validVerfahren}")" ]]; then
			isValidVerfahren=0
		fi
	done
	if [[ ${isValidVerfahren} -ne 0 ]]; then
		echo -e "\033[31m${2} ist ein nicht erlaubtes Verfahren. Erlaubt sind: ${ERLAUBTE_VERFAHREN[@]}\033[0m"; exit 1
	fi
	local verfahrensbezeichnung="${2}"
	TRANSFERNUMMER_COUNTER_EINZELDATEI="${EIGENE_DATEN_ORDNER}/Transfernummern_${verfahrensbezeichnung}.txt"; checkIfExists ${TRANSFERNUMMER_COUNTER_EINZELDATEI} || touch ${TRANSFERNUMMER_COUNTER_EINZELDATEI}
	local transferLogEinzelFile="${LOG_ORDNER}/Transferlog_${verfahrensbezeichnung}.txt"
	if [[ -z "$(echo -n "${3}" | grep -E "${EMPFAENGER_PHYSIKALISCH[5]}")" ]]; then
		echo -e "\033[31mIK Nummer ist neunstellig.\033[0m"; exit 1
	fi
	local empfaengerIK=${3}
	if [[ ! -r "${ZERTIFIKAT_ORDNER}/${empfaengerIK}${ZERTIFIKAT_SUFFIX}" ]]; then
		echo -e "\033[31mZertifikt für die angegebene IK Nummer ist nicht vorhanden.\033[0m"; exit 1
	fi
	local temporaereAufDatei="${TEMP_ORDNER}/${dateipfadEinzeldatei##*/}.AUF"

	# Empfänger herausfinden
	init_KassenAdressenDatei
	if [[ -z "$(grep "IK${3}" ${KASSEN_ADRESSEN})" ]]; then
		echo -e "\033[31mZur IK ${3} wurden keine Adressinformationen gefunden :(.\033[0m"; exit 1
	fi
	local kassenInformationen=$(konvertiereZuCharset "$(grep "IK${3}" ${KASSEN_ADRESSEN} | grep KCH- | tr -d '\r\n')" "${LANG_FUER_IO}" "${LANG_FUER_AUSGABE}")
	local tempAnnahmestelle=$(echo -n "${kassenInformationen}" | cut -d\; -f 7-9 | sed 's#;# - #g')
	local tempIP="datentausch2.intern.kzvb.de"
	#local tempIP=($(echo -n "${kassenInformationen}" | cut -d\; -f 22 | tr ',' ' '))
	local tempPort=3322
	#local tempPort=$(echo -n "${kassenInformationen}" | cut -d\; -f 23)
	local tempPfad="/"
	#local tempPfad=$(echo -n "${kassenInformationen}" | cut -d\; -f 24)
	local tempBenutzer="generischer_sftp"
	#local tempBenutzer=$(echo -n "${kassenInformationen}" | cut -d\; -f 25)
	local tempPasswort=$(echo -n "${kassenInformationen}" | cut -d\; -f 27); [[ "${tempPasswort}" == "" ]] && tempPasswort=" "
	local tempPasswort="vh0iKo54JcVlPxDGzMnX"
	local tempAnnahmestelleIK="$(echo -n "${kassenInformationen}" | cut -d\; -f 22 | tr '.,' '_' | sed 's/^/var/')"

	if [[ ! -z "${tempIP}" ]]; then
		if [[ -z "$(grep ${tempAnnahmestelleIK} ${TRANSFERNUMMER_COUNTER_EINZELDATEI})" ]]; then
			#echo "${tempAnnahmestelleIK} wird zur Datei ${TRANSFERNUMMER_COUNTER_EINZELDATEI} hinzugefügt"
			echo "${tempAnnahmestelleIK}=1" >> ${TRANSFERNUMMER_COUNTER_EINZELDATEI}
			declare -x "${tempAnnahmestelleIK}=1"
		else
			#echo "counter für ${tempAnnahmestelleIK} wird aus der Datei ${TRANSFERNUMMER_COUNTER_EINZELDATEI} ausgelesen"
			declare -x "${tempAnnahmestelleIK}=$(grep ${tempAnnahmestelleIK} ${TRANSFERNUMMER_COUNTER_EINZELDATEI} | cut -d"=" -f2)"
		fi	
		#echo "Variablennamen ${tempAnnahmestelleIK} | Variablenwert ${!tempAnnahmestelleIK}"
	else
		echo -e "\033[31mkeine Adresse gefunden, breche ab\033[0m"; exit 1
	fi

	# generelle AUF erstellen
	for aufFeld in ${AUFTRAGSDATEI_BEZEICHNER_ARRAY[@]}; do
		local tempAufKonstante="${aufFeld}[5]"
		local tempAufValidChars="${aufFeld}[3]"
		if ! [[ ${!tempAufKonstante} =~ \[.*\]|\(.*\)|\{.*\} ]]; then # wenn ein regulärer Ausdruck gefunden wird überspringen
			echo ${!tempAufKonstante}
			schreibeInAufDatei "${temporaereAufDatei}" "${!tempAufKonstante}" "${aufFeld}" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
		else
			if [[ "${!tempAufValidChars}" == "[:digit:]" ]]; then
				schreibeInAufDatei "${temporaereAufDatei}" "0" "${aufFeld}" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
			else
				schreibeInAufDatei "${temporaereAufDatei}" " " "${aufFeld}" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
			fi
		fi
	done
	# Verfahrensspezifische Informationen in AUF schreiben
	schreibeInAufDatei "${temporaereAufDatei}" "${EIGENE_IK_NUMMER}" "ABSENDER_EIGNER" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
	schreibeInAufDatei "${temporaereAufDatei}" "${EIGENE_IK_NUMMER}" "ABSENDER_PHYSIKALISCH" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
	schreibeInAufDatei "${temporaereAufDatei}" "${empfaengerIK}" "EMPFAENGER_NUTZER" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
	schreibeInAufDatei "${temporaereAufDatei}" "${empfaengerIK}" "EMPFAENGER_PHYSIKALISCH" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
	schreibeInAufDatei "${temporaereAufDatei}" "${verfahrensbezeichnung}" "VERFAHREN_KENNUNG" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
	schreibeInAufDatei "${temporaereAufDatei}" "$(du -b ${dateipfadEinzeldatei} | awk '{print $1}' | tr -d '\n')" "DATEIGROESSE_NUTZDATEN" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
	schreibeInAufDatei "${temporaereAufDatei}" "${dateipfadEinzeldatei##*/}" "" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
	
	# compress + sign + encrypt
	if [[ "$(echo -n "${kassenInformationen}" | cut -d\; -f 26)" == "ja" ]]; then
		echo "=> komprimiere ${dateipfadEinzeldatei}"
		cat "${dateipfadEinzeldatei}" | gzip --best > "${TEMP_ORDNER_OPENSSL}/${dateipfadEinzeldatei##*/}"
		dateipfadEinzeldatei="${TEMP_ORDNER_OPENSSL}/${dateipfadEinzeldatei##*/}"
		schreibeInAufDatei "${temporaereAufDatei}" "02" "KOMPRIMIERUNG" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
	fi
	echo "signiere ${dateipfadEinzeldatei}"
	openssl cms -sign -binary -in "${dateipfadEinzeldatei}" -nodetach -outform ${OUTFORM} -signer "${EIGENES_ZERTIFIKAT}" -inkey "${PRIVATE_KEY}" -certfile "${EIGENES_ZERTIFIKAT_CAs}" -out "${TEMP_ORDNER_OPENSSL}/${dateipfadEinzeldatei##*/}${SIGNIERT_SUFFIX}"
	local signierResult=$? 
	openssl cms -encrypt -binary -in "${TEMP_ORDNER_OPENSSL}/${dateipfadEinzeldatei##*/}${SIGNIERT_SUFFIX}" ${OPENSSL_CIPHER_SWITCH} -outform ${OUTFORM} -out "${TEMP_ORDNER_OPENSSL}/${dateipfadEinzeldatei##*/}.singleFileEncrypted" "${ZERTIFIKAT_ORDNER}/${empfaengerIK}${ZERTIFIKAT_SUFFIX}"
	if [[ $? != 0 ]]; then 
		echo -e "\033[31mEncryption fehlgeschlagen\033[0m" | tee -a "${GENERAL_LOG}" 
		exit 1
	else 
		schreibeInAufDatei "${temporaereAufDatei}" $(du -b "${TEMP_ORDNER_OPENSSL}/${dateipfadEinzeldatei##*/}.singleFileEncrypted" | awk '{print $1}' | tr -d '\n') "DATEIGROESSE_UEBERTRAG" "${LANG_FUER_AUSGABE}" "${LANG_FUER_IO}"
	fi
	versendePerSFTP "${TEMP_ORDNER_OPENSSL}/${dateipfadEinzeldatei##*/}.singleFileEncrypted" "tempIP" ${tempPort} "${tempPfad}" "${tempBenutzer}" "${tempPasswort}" "${verfahrensbezeichnung}${!tempIP}" "${transferLogEinzelFile}"
	if [[ $? -ne 0 ]]; then
		echo -e "\033[31mVersand der Datei ${dateipfadEinzeldatei} als "${verfahrensbezeichnung}${!tempIP}" an ${tempAnnahmestelle} fehlgeschlagen\033[0m"
	else
		echo -e "\033[32mVersand der Datei ${dateipfadEinzeldatei} als "${verfahrensbezeichnung}${!tempIP}" an ${tempAnnahmestelle} erfolgreich\033[0m"
	fi
	versendePerSFTP "${temporaereAufDatei}" "tempIP" ${tempPort} "${tempPfad}" "${tempBenutzer}" "${tempPasswort}" "${verfahrensbezeichnung}${!tempIP}.AUF" "${transferLogEinzelFile}"
	if [[ $? -ne 0 ]]; then
		echo -e "\033[31mVersand der Datei ${temporaereAufDatei} als "${verfahrensbezeichnung}${!tempIP}.AUF" an ${tempAnnahmestelle} fehlgeschlagen\033[0m"
	else
		echo -e "\033[32mVersand der Datei ${temporaereAufDatei} als "${verfahrensbezeichnung}${!tempIP}.AUF" an ${tempAnnahmestelle} erfolgreich\033[0m"
	fi
}

case ${1} in
	update)
		updateGesamtZertifikate "${ZERTIFIKATS_ADRESSE}" "${ZERTIFIKAT_ORDNER}"
		;;
	updateRootCerts)
		getRootCerts "${ZERTIFIKAT_ORDNER}"
		;;
	print)
		printAufDatei "${2}" "${LANG_FUER_IO}" "${LANG_FUER_AUSGABE}"
		;;
	check)
		checkAufDatei "${2}"
		;;
	encrypt)
		verschluesseleOderVersendeDateien "${1}" "${2}" "${3}"
		;;
	versende)
		verschluesseleOderVersendeDateien "${1}" "${2}" "${3}" "${4}"
		;;
	versendeEinzelneDatei)
		versendeEinzelneDatei "${2}" "${3}" "${4}"
		;;
	test)
		testeSftpVerbindungen
		;;
	schreibe)
		schreibeInAufDatei "${2}" "${3}" "${4}" "${LANG_FUER_IO}" "${LANG_FUER_AUSGABE}"
		;;
	*)
		usage
		exit 1
		;;
esac

# restore default exit command
cleanup
trap - INT TERM EXIT
