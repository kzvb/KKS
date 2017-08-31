# $1 = Text	  (muss)
# $2 = Quellcharset  (muss)
# $3 = Zielcharset   (muss)
function konvertiereZuCharset {
	if [[ $# -ne 3 ]]; then echo -e "\033[31m=> ${FUNCNAME}: Nicht alle Parameter angegeben. \$1 = Text, \$2 = Quellcharset, \$3 = Zielcharset\033[0m"; exit 1; fi
	echo -n "$(iconv -f "${2}" -t "${3}" <<<"${1}")" # viel Quotes, sonst werden die Spaces gefressen
}
# $1 = Text (muss)
function removeLeadingAndTrailingSpaces {
	echo -n "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# $1 = Text (muss)
# gibt Input ohne führende Nullen aus
function removeLeadingZeroes {
	if [[ $# -ne 1 ]]; then echo -e "\033[31m=> ${FUNCNAME}: Nicht alle Parameter angegeben. \$1 = Text (muss)\033[0m"; exit 1; fi
	echo ${1} | sed -r 's/^0+//g'
}

# zeigt einen "drehenden Strich" an um anzuzeigen, dass im Hintergrund noch etwas läuft
# $1 = pid des Prozesses, auf den gewartet wird
function waitSpinner {
	local pid=$1
	local delay=0.75
	local spinArray=('|' '/' '-' '\')
	local spinCounter=0
	local startTime=$(date +%s)
	#local startTime=$(($(date +%s) - 1))
	local timeString="Sekunde(n)"
	local timeElapsedDevisorMinute=60 # um Sekunden in Minuten umzurechnen
	local timeElapsedDevisorHour=24;
	while [ "$(ps a | awk '{print $1}' | grep ${pid})" ]; do
		if [[ ${spinCounter} -gt 3 ]]; then spinCounter=0; fi
		local timeDifference=$(( $(date +%s) - ${startTime} ))
		printf "[%c] vergangene Zeit: %02dh:%02dm:%02ds" "${spinArray[${spinCounter}]}" "$(( ${timeDifference} / 3600 ))" "$(( (${timeDifference} % 3600 ) / 60 ))" "$(( ${timeDifference} % 60 ))"
		sleep ${delay}
		printf "%0.s\b" $(seq 1 32)
		((spinCounter++))
	done
	unset spinCounter
}
