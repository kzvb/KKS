# Allgemeine Beschreibung
Um es für andere Interessierte einfacher zu machen sich selbst eine Lösung zu bauen, habe ich die Dateien hier hochgeladen.
Das Skript erledigt für uns die Aufgabe des Kassenausgangsversands nach den Definitionen, die auf der gkv Spitzenverband Webseite [hier](https://gkv-datenaustausch.de/leistungserbringer/zahnaerzte/zahnaerzte.jsp) drinstehen.

Da die Dateien alle verschlüsselt werden müssen, wird von der ITSG ein Zertifikat angefordert.
Die öffentlichen Schlüssel sind dann [dort](http://www.itsg.de/oeffentliche-services/trust-center/oeffentliche-schluesselverzeichnisse-le/) zu finden.

Aus irgendwelchen unerfindlichen Gründen sind die Keys ohne die normalerweise umschließenden -----BEGIN CERTIFICATE----- und -----END CERTIFICATE-----
Um ein CSR in openssl zu erstellen, kann man [diese](http://www.itsg.de/wp-content/uploads/2017/03/tc_howto_p10_openssl.txt) ITSG Anleitung hernehmen:

Die [Tinyheb Software](https://github.com/tinyheb/tinyheb/wiki/Zertifikatsbehandlung,-Signierung-und-Verschl%C3%BCsselung) hat beim verstehen der openssl Befehler geholfen.

Die Ordnerstruktur:
* Eigene_Daten
Dort ist das Zertifikat in verschiedenen Formen abgespeichert (pem, der) und andere Konfigurationsdateien untergebracht
* Libs
hier sind augelagerte Codeteile
* Logs
Hier werden die Logdateien für den Verschlüsselungsvorgang und Dateitransfer abgelegt
* tmp
temporäres Verzeichnis
* Zertifikate
Dort werden [die Zertifikate](https://trustcenter-data.itsg.de/dale/gesamt-pkcs.key) der ITSG gespeichert. Jedes Zertifikat wird aus der Gesamtdatei extrahiert und abgespeichert als <IKnummer>.pem

Der Ablauf ist folgender:
1. Update der Zertifikate. Dieses wird in einem ramfs gemacht, da viel I/O stattfindet
2. Komprimieren, signieren und encrypten der Dateien mit den entsprechenden Empfängerzertifikaten
3. Versenden der Dateien

Der Aufruf des Skriptes gibt folgende Hilfe von sich:
[hostname:benutzer]/home/verzeichnis $ ./versendeDateien.sh
Aufruf: ./versendeDateien.sh <Parameter>
mögliche Parameter:
        - update
                Die Zertifikate werden von der ITSG heruntergeladen und ins Verzeichnis /home/verzeichnis/Zertifikate abgespeichert.
                Jede Annahmestelle wird in eine eigene Datei geschrieben. Der Name der Datei ist die IK Nummer plus pem Suffix.
                Ein Zertifikat heißt dann z.B. 218200101.pem. Diese x509 Zertifikate werden verwendet um die Kassenausgangs-
                dateien zu verschlüsseln.
        - updateRootCerts
                Holt die Root Zertifikate von der ITSG Website und speichert sie in das Chainfile /home/verzeichnis/Zertifikate/ca_chain_file.pem
        - encrypt <Abrechnungstyp: KCH oder PAR_KB_ZE> <Abrechnungszeitraum: YYYYMM oder YYYY0Q>
                Beispiel: ./versendeDateien.sh encrypt KCH 201604
                          ./versendeDateien.sh encrypt PAR_KB_ZE 201612
        - test
                Testet die sftp Server der Annahmestellen und gibt aus, ob die Verbindung funktioniert und das Verzeichnis existiert
        - versende <Abrechnungstyp: KCH oder PAR_KB_ZE> <Abrechnungszeitraum: YYYYMM oder YYYY0Q> [Kassennummer]
                Versendet alle Kassenausgangsdateien an die entsprechenden Annahmestellen. Die Informationen kommen aus den
                Stammdaten. Ist eine Übertragung fehlerhaft, muss das Skript nochmals mit den gleichen Parametern aufgerufen werden.
                Das Skript überträgt dann nur die fehlerhaften Dateien neu.
                Soll nur eine Kassennummer geschickt werden muss der optionale Parameter [Kassennummer] mit angegeben werden.
                Beispiele: ./versendeDateien.sh versende KCH 201604
                           ./versendeDateien.sh versende PAR_KB_ZE 201612
                           ./versendeDateien.sh versende PAR_KB_ZE 201612 1040
        - versendeEinzelneDatei <absoluter Pfad> <Verfahren> <Empfänger IK>
                Beispiel: ./versendeDateien.sh versendeEinzelneDatei /irgendein/pfad/test.txt E1Z10 108310400
        - print <Auftragsdatei>
                Beispiel: ./versendeDateien.sh print /home/verzeichnis/tmp/Z119561G.AUF
        - check <Auftragsdatei>
                Beispiel: ./versendeDateien.sh check /home/verzeichnis/tmp/Z119561G.AUF
        - schreibe <Auftragsdatei> <Wert> <Bezeichner>
                Beispiel: ./versendeDateien.sh schreibe /home/verzeichnis/tmp/Z119561G.AUF beispiel.csv DATEI_BEZEICHNUNG

Für den Rest studiert man wohl am Besten den Code. Das sollte zumindest genügend Anreize liefern können eine eigene Lösung basteln zu können.
