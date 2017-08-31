if [[ -z "$(command -v holeUndErstelleKassenAdressenDatei)" ]]; then echo -e "\033[31m=> datenbank.lib.sh muss vorher gesourced werden.\033[0m"; exit 1; fi
if [[ -z "$(command -v init_KassenAdressenDatei)" ]]; then echo -e "\033[31m=> datenbank.lib.sh muss vorher gesourced werden.\033[0m"; exit 1; fi
if [[ -z "$(command -v konvertiereZuCharset)" ]]; then echo -e "\033[31m=> strings.lib.sh muss vorher gesourced werden.\033[0m"; exit 1; fi
if [[ -z "$(command -v getByteDifferenceBetweenCharsets)" ]]; then echo -e "\033[31m=> kassenkommunikationssystem_io.lib.sh muss vorher gesourced werden.\033[0m"; exit 1; fi
# https://securetransfer.cns.gov/doc/en/MOVEitDMZ_FTP_SpecificClients_cURL.htm
# curl -1 -k -v -c cookie2.txt "https://moveit.niedersachsen.aok.de/human.aspx?transaction=signon&username=ik218200101&password=srcvtqxdz9" # -1 weil curl zu alt ist 
# curl -b cookie2.txt -1 -k -v --data-binary @/home/dta_kk/tmp/test.txt -H "Content-Type: multipart/form-data" -H "X-siLock-AgentBrand: cURL" -H "X-siLock-AgentVersion: 4.32" -H "X-siLock-FolderID: 1823151434" -H "X-siLock-OriginalFilename: test.txt" -H "X-siLock-FileSize: $(du -b /home/dta_kk/tmp/test.txt | awk '{print $1}')" "https://moveit.niedersachsen.aok.de/moveitisapi/moveitisapi.dll?action=upload"
# curl -k -v -b cookie2.txt "https://i.stdnet.com/human.aspx?transaction=signoff"
# falscher Ordner: < HTTP/1.1 503 Service Unavailable
SFTP_RETRIES=3
SFTP_COMPRESSION_LEVEL="9"
EXPECT_BIN="$(which expect)"
if [[ -z "${EXPECT_BIN}" ]]; then echo -e "\033[31m=> expect nicht installiert? yum install expect\033[0m"; exit 1; fi
SFTP_BIN="$(which sftp)"
if [[ -z "${SFTP_BIN}" ]]; then echo -e "\033[31m=> sftp Befehl nicht vorhanden?\033[0m"; exit 1; fi
# $1 = Datei, die hochgeladen werden soll
# $2 = SFTP IP Adresse
#      Hier wird der Array Name übergeben. Anders kann man keine Array in Bash "übergeben". Für jede IP wird die Verbindung ${SFTP_RETRIES} mal versucht
# $3 = SFTP Port
# $4 = SFTP Uploadordner
# $5 = SFTP Benutzer
# $6 = SFTP Passwort, wenn keines vorhanden ein gequotetes Space übergeben
# $7 = Dateinamen, mit dem die Datei $1 auf den Server hochgeladen werden soll (Transfernamen)
# $8 = absoluter Pfad zur Transferlogdatei
# gibt 0 für erfolgreichen Transfer zurück und !=0 für Fehler
function versendePerSFTP {
	local result
	local uploadOrdner="${4}"
	local transferLog="${8}"
	local tempPreferredAuthentication=""
	# wenn ein Passwort in der Datei steht, immer das nehmen und keine publickey Authentifizierung probieren
        if [[ "${6}" != " " ]]; then tempPreferredAuthentication="-oPreferredAuthentications=password -oPubkeyAuthentication=no"; fi
	sftpIPArray="$2[@]" # den Arraynamen mit [@] zusammenfügen, um dann mit ${!sftpIPArray} drauf zugreifen zu können
	if [[ "${uploadOrdner}" == "/" ]]; then uploadOrdner="" ; fi
	for sftp_ip in ${!sftpIPArray}; do
		for (( versende_counter=1; versende_counter<=${SFTP_RETRIES}; versende_counter++ )); do
			${EXPECT_BIN} -f - <<-________________________EOFEXPECT 2>>"${transferLog}"
				#exp_internal 1
				set timeout -1
				log_file -a "${transferLog}"
				log_user 0
				spawn ${SFTP_BIN} ${tempPreferredAuthentication} -oPort=${3} -oCompressionLevel=${SFTP_COMPRESSION_LEVEL} ${5}@${sftp_ip}
				expect {
					# wenn das erste Mal verbunden wird muss der Hostkey akzeptiert werden
					"Are you sure you want to continue connecting (yes/no)? " {
					send "yes\r"
					exp_continue
					}
					"*password:" {
						send "${6}\r"
						exp_continue
					}
					"sftp> " {
					send "put ${1} ${uploadOrdner}/${7}\r"
					}
				}
				expect {
					#Check for progress, note does not work with all versions of SFTP
					#If a match is found restart expect loop
					-re "\[0-9\]*%" {
					exp_continue
					}
					#Check for common errors, by no means all of them
					# Couldn't read packet: Connection reset by peer
					-re "Couldn't(.*)|(.*)disconnect(.*)|(.*)stalled(.*)" {
					#puts "Dateitransfer nicht erfolgreich"
					exit 1
					}
					-re "stat(.*): No such file or directory" {
					#puts "Datei konnte nicht gefunden und von daher nicht hochgeladen werden"
					exit 2
					}
					-re "Connection closed" {
					#puts "Verbindung unterbrochen"
					exit 3
					}
					"sftp>" {
					#puts "Dateitransfer erfolgreich abgeschlossen"; send \"bye\n\"
					exit 0
					}
				}
________________________EOFEXPECT
			result=$?
			if [[ ${result} -eq 0 ]]; then
				return ${result}
			fi
		done
	done
	return ${result}
}
# Funktion ist momentan nur so gebaut, dass sie im versendeKassenausgang.sh Skript läuft bzw. es wird davon ausgegangen, dass ${KASSEN_ADRESSEN}, ${LANG_FUER_IO} und ${LANG_FUER_AUSGABE} gesetzt sind.
function testeSftpVerbindungen {
	holeUndErstelleKassenAdressenDatei "${DB_USER}"
	if [ ! -e "${KASSEN_ADRESSEN}" ]; then
		echo -e "\033[31mKann die Adressen nicht aus der Datenbank holen. SQL Query Output:\033[0m"
		echo "${SQL_RESULT}"
		exit 1
	fi
	init_KassenAdressenDatei
	local vorhandeneAnnahmestellen=$(konvertiereZuCharset "$(awk '{FS=";"} $20 == "ja" {print $7 ";" $8 ";" $9 ";" $22 ";" $23 ";" $24 ";" $25 ";" $27}' "${KASSEN_ADRESSEN}" | awk '!x[$0]++' | sort | sed 's/$/\\n/' | tr -d "\r\n")" "${LANG_FUER_IO}" "${LANG_FUER_AUSGABE}")
	IFS=$'\n'
	for annahmestellenZeile in $(echo -e ${vorhandeneAnnahmestellen} | sed '/^$/d'); do
		unset IFS
		local tempAnnahmestelle=$(echo -n "${annahmestellenZeile}" | cut -d\; -f 1-2 | sed -e 's#;# - #g' -e 's#[/()]##g')
		local tempIP=($(echo -n "${annahmestellenZeile}" | cut -d\; -f 4 | tr ',' ' '))
		local tempPort=$(echo -n "${annahmestellenZeile}" | cut -d\; -f 5)
		local tempPfad=$(echo -n "${annahmestellenZeile}" | cut -d\; -f 6)
		local tempBenutzer=$(echo -n "${annahmestellenZeile}" | cut -d\; -f 7)
		local tempPassword="$(echo -n "${annahmestellenZeile}" | cut -d\; -f 8)"
		local tempPreferredAuthentication=""
		# wenn ein Passwort in der Datei steht, immer das nehmen und keine publickey Authentifizierung probieren
		if [[ ! -z "${tempPassword}" ]]; then tempPreferredAuthentication="-oPreferredAuthentications=password -oPubkeyAuthentication=no"; fi
		for sftp_ip in ${tempIP[@]}; do
			${EXPECT_BIN} -f - <<-________________EOFEXPECT
				set timeout 5
				#log_file -a "${transferLog}"
				log_user 0
				puts -nonewline "$(LC_ALL="" printf "% $((-80-$(getByteDifferenceBetweenCharsets "=> teste ${tempAnnahmestelle}" "${LANG}")))s % -75s" "=> ${tempAnnahmestelle}" "${SFTP_BIN##*/} -oPort=${tempPort} ${tempBenutzer}@${sftp_ip}:${tempPfad}")"
				spawn ${SFTP_BIN} ${tempPreferredAuthentication} -oPort=${tempPort} -oCompressionLevel=${SFTP_COMPRESSION_LEVEL} ${tempBenutzer}@${sftp_ip}
				expect {
					# wenn das erste Mal verbunden wird muss der Hostkey akzeptiert werden
					"Are you sure you want to continue connecting (yes/no)? " {
						send "yes\r"
						exp_continue
					}
					"*password:" {
						send "${tempPassword}\r"
						exp_continue
					}
					"sftp> " {
						puts -nonewline "\033\[32mLogin $(echo -en "\xE2\x9C\x93"), \033\[0m"
					}
					timeout {
						puts "\033\[31mLogin $(echo -en "\xe2\x9A\xA1")\033\[0m"; exit 1
					}
					"Couldn't*" {
						puts "\033\[31mLogin $(echo -en "\xe2\x9A\xA1")\033\[0m"; exit 1
					}
					"Connection closed by remote host" {
						puts "\033\[31mLogin $(echo -en "\xe2\x9A\xA1")\033\[0m"; exit 1
					}
				}
				send "ls ${tempPfad}\r"
				expect {
					"Couldn't stat remote file*" {
						puts "\033\[31mVerzeichnis $(echo -en "\xe2\x9A\xA1")\033\[0m"; send "bye\n"
						exit 1
					}
					"sftp> " {
						puts "\033\[32mVerzeichnis $(echo -en "\xE2\x9C\x93")\033\[0m"; send "bye\n"
					}
	#				"${tempPfad}.*" {
	#					puts "\033\[32mVerzeichnis $(echo -en "\xE2\x9C\x93")\033\[0m"; send "bye\n"
					}
				}
	________________EOFEXPECT
		done
	done
}
