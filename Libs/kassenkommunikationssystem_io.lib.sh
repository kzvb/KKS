if [[ -z "$(command -v konvertiereZuCharset)" ]]; then echo -e "\033[31m=> strings.lib.sh muss vorher gesourced werden.\033[0m"; exit 1; fi
if [[ -z "$(command -v removeLeadingZeroes)" ]]; then echo -e "\033[31m=> strings.lib.sh muss vorher gesourced werden.\033[0m"; exit 1; fi
if [[ -z "$(command -v removeLeadingAndTrailingSpaces)" ]]; then echo -e "\033[31m=> strings.lib.sh muss vorher gesourced werden.\033[0m"; exit 1; fi
if [[ -z "$(command -v initAufDateiInformationen)" ]]; then echo -e "\033[31m=> kassenkommunikationssystem_AUF_Definition.lib.sh muss vorher gesourced werden.\033[0m"; exit 1; fi
initAufDateiInformationen
# $1 = absoluter Pfad zur AUF Datei (muss)
# $2 = Wert, der in die AUF Datei geschrieben werden soll. Da kein Leerstring als Argument gültig ist muss ein Space für alphanum und für Nummern eine 0 übergeben werden (muss)
# $3 = BEZEICHNER der Stelle in der AUF Datei. Diese stehen in der Funktion initAufDateiInformationen (muss)
# $4 = Quellcharset (muss)
# $5 = Zielcharset (muss)
function schreibeInAufDatei {
	if [[ $# -ne 5 ]]; then
		echo "Funktion schreibeInAufDatei erwartet 3 Argumente. \$1 = absoluter Pfad zur AUF Datei, \$2 = Wert, der in die AUF Datei geschrieben werden soll, \$3 = BEZEICHNER der Stelle in der AUF Datei. Diese stehen in der Funktion initAufDateiInformationen, \$4 = Quellcharset, \$5 = Zielcharset"
	else
		local LANG_QUELLE="$4"
		local LANG_ZIEL="$5"
		local tempOffsetBytes="${3}[0]"; local tempLengthBytes="${3}[1]"; local tempArt="${3}[2]"; local tempValidChars="${3}[3]";
		local tempMussOderKann="${3}[4]"; local tempMusswertWennKonstante="${3}[5]"; local tempBeschreibung="${3}[6]"
		# wenn eine Nummer geschrieben werden soll, wird die Zahl mit führenden Nullen aufgefüllt
		# bei 00000348 kommt -bash: printf: 00000348: Ungültige Oktalzahl. Laut https://stackoverflow.com/a/11804275 kann man die Zahl base 10 machen und dann geht es
		if [[ -z "$(echo -n ${2} | tr -d "${!tempValidChars}")" ]] && [[ "${!tempValidChars}" == "[:digit:]" ]]; then
			printf "%0${!tempLengthBytes}d" "$(( 10#${2} ))" | dd of=${1} seek=${!tempOffsetBytes} bs=1 count=${!tempLengthBytes} conv=notrunc status=none
		# wenn es alphanumerisch oder alpha ist mit blanks nach dem String auffüllen, da ${2} auch Spaces beinhalten darf muss auch das beachtet werden...
		elif [[ -z "$(echo -n ${2} | tr -d "${!tempValidChars}" | tr -d '[:blank:]')" ]]; then
			printf "% -${!tempLengthBytes}s" "$(konvertiereZuCharset "${2}" "${LANG_QUELLE}" "${LANG_ZIEL}")" | dd of=${1} seek=${!tempOffsetBytes} bs=1 count=${!tempLengthBytes} conv=notrunc status=none
		else
			echo "${2} scheint nicht dem gültichen Zeichenvorrat von ${!tempValidChars} für dieses Feld zu entsprechen"
		fi
	fi
}
# $1 = absoluter Pfad zur AUF Datei                                                                   (muss)
# $2 = BEZEICHNER der Stelle in der AUF Datei. Diese stehen in der Funktion initAufDateiInformationen (muss)
# $3 = Quellcharset (muss)
# $4 = Zielcharset (muss)
# $5 = "clean" für gesäubert zurück geben. Wenn digit, dann führende Nullen wegkürzen, wenn alpha || alnum || alnum@. , dann spaces entfernen (optional)
function leseVonAufDatei {
	if [[ $# -lt 4 ]] || [[ $# -gt 5 ]]; then
		echo "Aufruf der Funktion leseVonAufDatei benötigt mindestens 4 Parameter: \$1 = absoluter Pfad zur AUF Datei, \$2 = BEZEICHNER der Stelle in der AUF Datei. Diese stehen in der Funktion initAufDateiInformationen, \$3 = Quellcharset, \$4 = Zielcharset, \$5 = \"clean\" für gesäubert zurück geben. Wenn digit, dann führende Nullen wegkürzen, wenn alpha || alnum || alnum@. , dann spaces entfernen (optional)"; return 1
	else
		local LANG_QUELLE="$3"
		local LANG_ZIEL="$4"
		local tempOffsetBytes="${2}[0]"; local tempLengthBytes="${2}[1]"; local tempArt="${2}[2]"; local tempValidChars="${2}[3]";
		local tempMussOderKann="${2}[4]"; local tempMusswertWennKonstante="${2}[5]"; local tempBeschreibung="${2}[6]"
		if [[ "$5" == "clean" ]]; then
			if [[ "${!tempValidChars}" == "[:digit:]" ]]; then
				echo -n "$(removeLeadingZeroes "$(konvertiereZuCharset "$(dd if=${1} skip=${!tempOffsetBytes} bs=1 count=${!tempLengthBytes} status=none)" "${LANG_QUELLE}" "${LANG_ZIEL}")")"
			else
				echo -n "$(removeLeadingAndTrailingSpaces "$(konvertiereZuCharset "$(dd if=${1} skip=${!tempOffsetBytes} bs=1 count=${!tempLengthBytes} status=none)" "${LANG_QUELLE}" "${LANG_ZIEL}")")"
			fi
		else
			echo -n "$(konvertiereZuCharset "$(dd if=${1} skip=${!tempOffsetBytes} bs=1 count=${!tempLengthBytes} status=none)" "${LANG_QUELLE}" "${LANG_ZIEL}")"
		fi
	fi
}
# $1 = absoluter Pfad zur AUF Datei (muss)
# $2 = Quellcharset (muss)
# $3 = Zielcharset (muss)
function printAufDatei {
        if [[ $# -ne 3 ]]; then
                echo -e "\033[31mFunktion printAufDatei erwartet folgende Parameter: \$1 = absoluter Pfad zur AUF Datei, \$2 = Quellcharset, \$3 = Zielcharset\033[0m"; exit 1
        fi
	if [[ ! -e "$1" ]]; then echo -e "\033[31mAUF Datei existiert nicht\033[0m"; fi; exit 1
	local LANG_QUELLE="$2"
	local LANG_ZIEL="$3"
        for i in ${AUFTRAGSDATEI_BEZEICHNER_ARRAY[@]}; do
                local tempOffsetBytes="${i}[0]"; local tempLengthBytes="${i}[1]"; local tempArt="${i}[2]"; local tempValidChars="${i}[3]";
                local tempMussOderKann="${i}[4]"; local tempMusswertWennKonstante="${i}[5]"; local tempBeschreibung="${i}[6]"
                printf "%-25s %0s %-46s %0s gültige Werte laut DTA: %0s\n" "${i}" "=>" "'$(leseVonAufDatei "${1}" "${i}" "${LANG_QUELLE}" "${LANG_ZIEL}")'" "<=" "${!tempMusswertWennKonstante}"
        done
}
# $1 = absoluter Pfad zur AUF Datei (muss)
function checkAufDatei {
        if [[ -z ${1} ]]; then
                echo -e "\033[31mkeine Auftragsdatei angegeben, abbrechen\033[0m"; exit 1
        fi
        for i in ${AUFTRAGSDATEI_BEZEICHNER_ARRAY[@]}; do
                local tempOffsetBytes="${i}[0]"; local tempLengthBytes="${i}[1]"; local tempArt="${i}[2]"; local tempValidChars="${i}[3]";
                local tempMussOderKann="${i}[4]"; local tempMusswertWennKonstante="${i}[5]"; local tempBeschreibung="${i}[6]"
                if [[ "${!tempMussOderKann}" == "muss" ]]; then
                        local tempFeldwert="$(removeLeadingAndTrailingSpaces "$(dd if=${1} skip=${!tempOffsetBytes} bs=1 count=${!tempLengthBytes} status=none)")"
			local gueltigerWertResult=false
			if [[ ! -z "$(echo -n "${tempFeldwert}" | grep -E "${!tempMusswertWennKonstante}")" ]]; then
				gueltigerWertResult=true
			fi
			[[ ${gueltigerWertResult} != true ]] && { echo "Feld ${i} sollte eines der Optionen \"${!tempMusswertWennKonstantei[@]}\" beinhalten, ist aber \"${tempFeldwert}\""; }

			if [[ ! -z "$(eval tr -d ${!tempValidChars} <<<${tempFeldwert})" ]]; then
				echo "Feld ${i} sollte als gültige Zeichen \"${!tempValidChars}\" haben, behinhaltet aber \"${tempFeldwert}\""
			fi
                fi
        done
}
# $1 = String
# $2 = Quellencoding
# returns den Byteunterschied zwischen zwei Encodings
function getByteDifferenceBetweenCharsets {
        if [[ $# -ne 2 ]]; then
                echo -e "\033[31mFunktion getByteDifferenceBetweenCharsets erwartet folgende Parameter: \$1 = String, \$2 = Quellencoding\033[0m"; exit 1
        fi
	# da printf nach Byteanzahl formatiert und nicht nach Buchstaben werden Zeichenketten mit Umlauten nicht so wie gewünscht formatiert, deswegen:
	echo -n "$(( $(echo -n "${1}" | LANG=C wc -m) - $(echo -n "${1}" | LANG=${2} wc -m) ))"
}
