export ORACLE_HOME="/pfad/zu/oracle/home"
SQLPLUS_PATH="${ORACLE_HOME}/bin/sqlplus"
PROD_SID="PROD"
TEST_SID="TEST"
if [[ "$(hostname -s | grep -i test | grep -i abr)" != "" ]]; then
	if [[ "$(hostname -s | sed -ne '/.*2$/p')" != ""  ]]; then
		export ORACLE_SID=${TEST_SID}
	else
		export ORACLE_SID=$(echo ${TEST_SID} | sed -re 's/(.{4})(.*)/\2\1/')
	fi
elif [[ "$(hostname -s | grep -i prod | grep -i abr)" != "" ]]; then
	if [[ "$(hostname -s | sed -ne '/.*2$/p')" != ""  ]]; then
		export ORACLE_SID=${PROD_SID}
	else
		export ORACLE_SID=$(echo ${PROD_SID} | sed -re 's/(.{4})(.*)/\2\1/')
	fi
fi

# Diese Funktion legt die Datei /pfad/zu/Adressen.csv ab, in der Adressen und weitere Informationen für den Kassenausgang stehen
# Anhang des Hostnamens wird entschieden, auf welche Datenbank verbunden wird. Soll das überschrieben werden muss das der Funktion übergeben werden
# Parameter:
# $1 = Schema      (muss)
# $2 = Datenbank   (optional, default=Anhand des Hostnamens festgelegt. Funktioniert nur, wenn das Skript auf abrprod|abrtest ausgeführt wird.)
function holeUndErstelleKassenAdressenDatei {
	# execute an SQL procedure that writes the required postal adresses to ${KASSEN_ADRESSEN}
	SQL_RESULT="$(${SQLPLUS_PATH} -s SCHEMA/pw@ABRECHNUNGSDB <<-________________EOSQL
		set echo off
		set heading off
		set feedback off
		set verify off
		set pagesize 0
		set linesize 200
		exec SCHEMA.Versandadressen;
		exit;
________________EOSQL
	)"
}
# Diese Funktion _sollte_ ;) nur temporär existieren, weil irgendwann die Zusatzinformationen wie IP usw. aus den Stammdaten kommt
# Die Funktion dürfte nur mit dem versendeDateien Skript funktionieren, weil sie verschiedene Variablen als gesetzt voraussetzt.
function init_KassenAdressenDatei {
	holeUndErstelleKassenAdressenDatei "${DB_USER}"
	if [ ! -e "${KASSEN_ADRESSEN}" ]; then
		echo -e "\033[31mKann die Adressen nicht aus der Datenbank holen. SQL Query Output:\033[0m"
		echo "${SQL_RESULT}"
		exit 1
	fi
	IFS=$'\n'
	local tempLineMergeCounter=1
	cp "${KASSEN_ADRESSEN}" ${EIGENE_DATEN_ORDNER}
	KASSEN_ADRESSEN="${EIGENE_DATEN_ORDNER}/Adressen.csv"
	dos2unix "${KASSEN_ADRESSEN}"
	for zusatzLine in $(cat "${ZUSATZ_INFOS}"); do
		unset IFS
		if [[ ${tempLineMergeCounter} -ge 2 && -z "$(grep -E "$(echo -n ${zusatzLine} | cut -d";" -f 1);[ja|nein]+" "${KASSEN_ADRESSEN}")" ]]; then
			addressLines=$(grep -n "$(echo -n ${zusatzLine} | cut -d";" -f 1)" "${KASSEN_ADRESSEN}" | cut -f1 -d: | paste -s -d' ')
			if [[ ! -z "${addressLines}" ]]; then
				for lines in ${addressLines}; do
					tmpAdressLine=$(awk "NR==${lines}" "${KASSEN_ADRESSEN}")
					sed -i "${lines}"'c\'"${tmpAdressLine}${zusatzLine}" "${KASSEN_ADRESSEN}"
				done
			else
				echo "In der Zusatzdatei ist $(echo -n ${zusatzLine} | cut -d";" -f 1) drin aber nicht in der Adressdatei aus der Datenbank, das darf nicht sein, breche ab..."; exit 1
			fi
		fi
		((tempLineMergeCounter++))
	done
	if [[ $(wc -l "${ZUSATZ_INFOS}" | awk '{print $1}') -ne $(wc -l "${KASSEN_ADRESSEN}" | awk '{print $1}') ]]; then
		echo "In den Adressdatei sind mehr Adressen als in der Zusatzdatei, das darf nicht sein, breche ab..."; exit 1
	fi
}
