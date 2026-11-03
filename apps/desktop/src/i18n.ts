// Translations for the desktop app. Keys are the English text; {name} placeholders are filled in by t().
// Counts use separate "one" keys ending in "#1" for the singular.

type Lang = "fr" | "es" | "it" | "de" | "nl";

const strings: Record<string, Record<Lang, string>> = {
  "Protected": { fr: "Protégées", es: "Protegidas", it: "Protette", de: "Geschützt", nl: "Beveiligd" },
  "All types": { fr: "Tous les types", es: "Todos los tipos", it: "Tutti i tipi", de: "Alle Typen", nl: "Alle types" },
  "Videos": { fr: "Vidéos", es: "Vídeos", it: "Video", de: "Videos", nl: "Video's" },
  "Newest first": { fr: "Plus récentes d'abord", es: "Más recientes primero", it: "Più recenti prima", de: "Neueste zuerst", nl: "Nieuwste eerst" },
  "Oldest first": { fr: "Plus anciennes d'abord", es: "Más antiguas primero", it: "Più vecchie prima", de: "Älteste zuerst", nl: "Oudste eerst" },
  "Type": { fr: "Type", es: "Tipo", it: "Tipo", de: "Typ", nl: "Type" },
  "Order": { fr: "Ordre", es: "Orden", it: "Ordine", de: "Reihenfolge", nl: "Volgorde" },
  "Thumbnail size": { fr: "Taille des vignettes", es: "Tamaño de las miniaturas", it: "Dimensione miniature", de: "Miniaturgröße", nl: "Miniatuurgrootte" },
  "Open folder": { fr: "Ouvrir le dossier", es: "Abrir carpeta", it: "Apri cartella", de: "Ordner öffnen", nl: "Map openen" },
  "{speed}/s · {left} left": { fr: "{speed}/s · encore {left}", es: "{speed}/s · quedan {left}", it: "{speed}/s · mancano {left}", de: "{speed}/s · noch {left}", nl: "{speed}/s · nog {left}" },
  "Settings": { fr: "Réglages", es: "Ajustes", it: "Impostazioni", de: "Einstellungen", nl: "Instellingen" },
  "Disconnect": { fr: "Déconnecter", es: "Desconectar", it: "Scollega", de: "Trennen", nl: "Verbreken" },
  "All": { fr: "Tout", es: "Todo", it: "Tutto", de: "Alle", nl: "Alles" },
  "Not imported": { fr: "Non importées", es: "No importadas", it: "Non importate", de: "Nicht importiert", nl: "Niet geïmporteerd" },
  "Show": { fr: "Afficher", es: "Mostrar", it: "Mostra", de: "Anzeigen", nl: "Tonen" },
  "Connect your camera": { fr: "Connectez votre appareil", es: "Conecta tu cámara", it: "Collega la fotocamera", de: "Kamera verbinden", nl: "Verbind je camera" },
  "Looking for the camera on your Wi-Fi network…": { fr: "Recherche de l'appareil sur votre réseau Wi-Fi…", es: "Buscando la cámara en tu red Wi-Fi…", it: "Ricerca della fotocamera sulla rete Wi-Fi…", de: "Suche nach der Kamera im WLAN…", nl: "Camera zoeken op je wifinetwerk…" },
  "On the camera, press <b>Playback</b>, then choose <b>Wireless Communication</b>.": {
    fr: "Sur l'appareil, appuyez sur <b>Lecture</b>, puis choisissez <b>Communication sans fil</b>.",
    es: "En la cámara, pulsa <b>Reproducción</b> y elige <b>Comunicación inalámbrica</b>.",
    it: "Sulla fotocamera, premi <b>Riproduzione</b>, poi scegli <b>Comunicazione wireless</b>.",
    de: "Drücke an der Kamera <b>Wiedergabe</b> und wähle <b>Drahtlose Kommunikation</b>.",
    nl: "Druk op de camera op <b>Weergave</b> en kies <b>Draadloze communicatie</b>." },
  "On this computer, join the camera's Wi-Fi network (named <b>FUJIFILM-…</b>).": {
    fr: "Sur cet ordinateur, rejoignez le réseau Wi-Fi de l'appareil (nommé <b>FUJIFILM-…</b>).",
    es: "En este ordenador, conéctate a la red Wi-Fi de la cámara (llamada <b>FUJIFILM-…</b>).",
    it: "Su questo computer, collegati alla rete Wi-Fi della fotocamera (chiamata <b>FUJIFILM-…</b>).",
    de: "Verbinde diesen Computer mit dem WLAN der Kamera (Name <b>FUJIFILM-…</b>).",
    nl: "Verbind deze computer met het wifinetwerk van de camera (genaamd <b>FUJIFILM-…</b>)." },
  "Fuji Import connects automatically. Press <b>OK</b> on the camera if it asks.": {
    fr: "Fuji Import se connecte automatiquement. Appuyez sur <b>OK</b> sur l'appareil s'il le demande.",
    es: "Fuji Import se conecta automáticamente. Pulsa <b>OK</b> en la cámara si te lo pide.",
    it: "Fuji Import si collega automaticamente. Premi <b>OK</b> sulla fotocamera se lo chiede.",
    de: "Fuji Import verbindet sich automatisch. Drücke <b>OK</b> an der Kamera, wenn sie fragt.",
    nl: "Fuji Import maakt automatisch verbinding. Druk op <b>OK</b> op de camera als die erom vraagt." },
  "Connect": { fr: "Connecter", es: "Conectar", it: "Collega", de: "Verbinden", nl: "Verbinden" },
  "Stop": { fr: "Arrêter", es: "Detener", it: "Interrompi", de: "Stoppen", nl: "Stoppen" },
  "Import to": { fr: "Importer dans", es: "Importar a", it: "Importa in", de: "Importieren nach", nl: "Importeren naar" },
  "Choose a folder": { fr: "Choisissez un dossier", es: "Elige una carpeta", it: "Scegli una cartella", de: "Ordner wählen", nl: "Kies een map" },
  "Choose…": { fr: "Choisir…", es: "Elegir…", it: "Scegli…", de: "Auswählen…", nl: "Kiezen…" },
  "Presets:": { fr: "Préréglages :", es: "Preajustes:", it: "Preimpostazioni:", de: "Vorlagen:", nl: "Voorinstellingen:" },
  "Pictures folder": { fr: "Dossier Images", es: "Carpeta Imágenes", it: "Cartella Immagini", de: "Bilder-Ordner", nl: "Map Afbeeldingen" },
  "A folder my photo app watches…": { fr: "Un dossier surveillé par mon app photo…", es: "Una carpeta que vigila mi app de fotos…", it: "Una cartella controllata dalla mia app di foto…", de: "Ein Ordner, den meine Foto-App überwacht…", nl: "Een map die mijn foto-app bewaakt…" },
  "Subfolders": { fr: "Sous-dossiers", es: "Subcarpetas", it: "Sottocartelle", de: "Unterordner", nl: "Submappen" },
  "Year / Date": { fr: "Année / Date", es: "Año / Fecha", it: "Anno / Data", de: "Jahr / Datum", nl: "Jaar / Datum" },
  "Date": { fr: "Date", es: "Fecha", it: "Data", de: "Datum", nl: "Datum" },
  "Year / Month": { fr: "Année / Mois", es: "Año / Mes", it: "Anno / Mese", de: "Jahr / Monat", nl: "Jaar / Maand" },
  "No subfolders": { fr: "Pas de sous-dossiers", es: "Sin subcarpetas", it: "Nessuna sottocartella", de: "Keine Unterordner", nl: "Geen submappen" },
  "Rename files (optional)": { fr: "Renommer les fichiers (facultatif)", es: "Renombrar archivos (opcional)", it: "Rinomina file (facoltativo)", de: "Dateien umbenennen (optional)", nl: "Bestanden hernoemen (optioneel)" },
  "Import new photos automatically after connecting": { fr: "Importer automatiquement les nouvelles photos après la connexion", es: "Importar automáticamente las fotos nuevas al conectar", it: "Importa automaticamente le nuove foto dopo il collegamento", de: "Neue Fotos nach dem Verbinden automatisch importieren", nl: "Nieuwe foto's automatisch importeren na verbinden" },
  "Leave videos out of “Import New”": { fr: "Exclure les vidéos de « Importer les nouvelles »", es: "Excluir los vídeos de «Importar nuevas»", it: "Escludi i video da «Importa nuove»", de: "Videos bei „Neue importieren“ auslassen", nl: "Video's overslaan bij ‘Nieuwe importeren’" },
  "Start at login": { fr: "Lancer à l'ouverture de session", es: "Abrir al iniciar sesión", it: "Avvia al login", de: "Bei der Anmeldung starten", nl: "Starten bij inloggen" },
  "Also upload to Immich (optional)": { fr: "Envoyer aussi vers Immich (facultatif)", es: "Subir también a Immich (opcional)", it: "Carica anche su Immich (facoltativo)", de: "Zusätzlich zu Immich hochladen (optional)", nl: "Ook uploaden naar Immich (optioneel)" },
  "Server": { fr: "Serveur", es: "Servidor", it: "Server", de: "Server", nl: "Server" },
  "API key": { fr: "Clé API", es: "Clave de API", it: "Chiave API", de: "API-Schlüssel", nl: "API-sleutel" },
  "Album": { fr: "Album", es: "Álbum", it: "Album", de: "Album", nl: "Album" },
  "Done": { fr: "OK", es: "Listo", it: "Fine", de: "Fertig", nl: "Gereed" },
  "Windows Photos, OneDrive, Shotwell and GNOME Photos pick up photos in your Pictures folder. Lightroom Classic (Auto Import), Photoshop Elements (watched folders), digiKam and darktable can watch a folder: choose it here and set Subfolders to “No subfolders” for Lightroom. Tokens: {yyyy} {MM} {dd} {HH} {mm} {ss} {camera} {original}.": {
    fr: "Photos Windows, OneDrive, Shotwell et GNOME Photos récupèrent les photos de votre dossier Images. Lightroom Classic (importation automatique), Photoshop Elements (dossiers surveillés), digiKam et darktable peuvent surveiller un dossier : choisissez-le ici et réglez Sous-dossiers sur « Pas de sous-dossiers » pour Lightroom. Jetons : {yyyy} {MM} {dd} {HH} {mm} {ss} {camera} {original}.",
    es: "Fotos de Windows, OneDrive, Shotwell y GNOME Fotos recogen las fotos de tu carpeta Imágenes. Lightroom Classic (importación automática), Photoshop Elements (carpetas vigiladas), digiKam y darktable pueden vigilar una carpeta: elígela aquí y pon Subcarpetas en «Sin subcarpetas» para Lightroom. Variables: {yyyy} {MM} {dd} {HH} {mm} {ss} {camera} {original}.",
    it: "Foto di Windows, OneDrive, Shotwell e GNOME Foto prendono le foto dalla cartella Immagini. Lightroom Classic (importazione automatica), Photoshop Elements (cartelle controllate), digiKam e darktable possono controllare una cartella: sceglila qui e imposta Sottocartelle su «Nessuna sottocartella» per Lightroom. Variabili: {yyyy} {MM} {dd} {HH} {mm} {ss} {camera} {original}.",
    de: "Windows Fotos, OneDrive, Shotwell und GNOME Fotos übernehmen Fotos aus deinem Bilder-Ordner. Lightroom Classic (automatischer Import), Photoshop Elements (überwachte Ordner), digiKam und darktable können einen Ordner überwachen: wähle ihn hier und stelle für Lightroom Unterordner auf „Keine Unterordner“. Platzhalter: {yyyy} {MM} {dd} {HH} {mm} {ss} {camera} {original}.",
    nl: "Windows Foto's, OneDrive, Shotwell en GNOME Foto's pakken foto's op uit je map Afbeeldingen. Lightroom Classic (automatisch importeren), Photoshop Elements (bewaakte mappen), digiKam en darktable kunnen een map bewaken: kies die hier en zet Submappen op ‘Geen submappen’ voor Lightroom. Variabelen: {yyyy} {MM} {dd} {HH} {mm} {ss} {camera} {original}." },
  "Talking to the camera at {address}…": { fr: "Communication avec l'appareil à {address}…", es: "Comunicando con la cámara en {address}…", it: "Comunicazione con la fotocamera a {address}…", de: "Verbindung mit der Kamera unter {address}…", nl: "Verbinden met de camera op {address}…" },
  "Press OK on the camera to allow this computer.": { fr: "Appuyez sur OK sur l'appareil pour autoriser cet ordinateur.", es: "Pulsa OK en la cámara para permitir este ordenador.", it: "Premi OK sulla fotocamera per consentire questo computer.", de: "Drücke OK an der Kamera, um diesen Computer zuzulassen.", nl: "Druk op OK op de camera om deze computer toe te laten." },
  "Importing {file} — {index} of {total}": { fr: "Importation de {file} — {index} sur {total}", es: "Importando {file} — {index} de {total}", it: "Importazione di {file} — {index} di {total}", de: "{file} wird importiert — {index} von {total}", nl: "{file} importeren — {index} van {total}" },
  "Imported {n} items#1": { fr: "1 élément importé", es: "1 elemento importado", it: "1 elemento importato", de: "1 Objekt importiert", nl: "1 item geïmporteerd" },
  "Imported {n} items": { fr: "{n} éléments importés", es: "{n} elementos importados", it: "{n} elementi importati", de: "{n} Objekte importiert", nl: "{n} items geïmporteerd" },
  " (stopped)": { fr: " (arrêté)", es: " (detenido)", it: " (interrotto)", de: " (gestoppt)", nl: " (gestopt)" },
  ". {n} failed: {list}": { fr: ". {n} en échec : {list}", es: ". {n} con error: {list}", it: ". {n} non riusciti: {list}", de: ". {n} fehlgeschlagen: {list}", nl: ". {n} mislukt: {list}" },
  "Import finished": { fr: "Importation terminée", es: "Importación terminada", it: "Importazione completata", de: "Import abgeschlossen", nl: "Importeren voltooid" },
  "Camera connected": { fr: "Appareil connecté", es: "Cámara conectada", it: "Fotocamera collegata", de: "Kamera verbunden", nl: "Camera verbonden" },
  "{n} new items to import#1": { fr: "1 nouvel élément à importer", es: "1 elemento nuevo para importar", it: "1 nuovo elemento da importare", de: "1 neues Objekt zum Importieren", nl: "1 nieuw item om te importeren" },
  "{n} new items to import": { fr: "{n} nouveaux éléments à importer", es: "{n} elementos nuevos para importar", it: "{n} nuovi elementi da importare", de: "{n} neue Objekte zum Importieren", nl: "{n} nieuwe items om te importeren" },
  "Camera": { fr: "Appareil photo", es: "Cámara", it: "Fotocamera", de: "Kamera", nl: "Camera" },
  "{n} items · {m} not imported": { fr: "{n} éléments · {m} non importés", es: "{n} elementos · {m} sin importar", it: "{n} elementi · {m} non importati", de: "{n} Objekte · {m} nicht importiert", nl: "{n} items · {m} niet geïmporteerd" },
  "Import {n} Selected": { fr: "Importer la sélection ({n})", es: "Importar {n} seleccionadas", it: "Importa {n} selezionate", de: "{n} ausgewählte importieren", nl: "{n} geselecteerde importeren" },
  "Import {n} New": { fr: "Importer {n} nouvelles", es: "Importar {n} nuevas", it: "Importa {n} nuove", de: "{n} neue importieren", nl: "{n} nieuwe importeren" },
  "No New Items": { fr: "Rien de nouveau", es: "Nada nuevo", it: "Niente di nuovo", de: "Nichts Neues", nl: "Niets nieuws" },
  "Importing into {folder}": { fr: "Importation dans {folder}", es: "Importando en {folder}", it: "Importazione in {folder}", de: "Import nach {folder}", nl: "Importeren naar {folder}" },
  "No import folder chosen": { fr: "Aucun dossier d'importation choisi", es: "No se ha elegido carpeta de importación", it: "Nessuna cartella di importazione scelta", de: "Kein Importordner gewählt", nl: "Geen importmap gekozen" },
  "Everything is imported.": { fr: "Tout est importé.", es: "Todo está importado.", it: "È tutto importato.", de: "Alles ist importiert.", nl: "Alles is geïmporteerd." },
  "No photos on the card.": { fr: "Aucune photo sur la carte.", es: "No hay fotos en la tarjeta.", it: "Nessuna foto sulla scheda.", de: "Keine Fotos auf der Karte.", nl: "Geen foto's op de kaart." },
  "Unknown date": { fr: "Date inconnue", es: "Fecha desconocida", it: "Data sconosciuta", de: "Unbekanntes Datum", nl: "Onbekende datum" },
  "Select": { fr: "Sélectionner", es: "Seleccionar", it: "Seleziona", de: "Auswählen", nl: "Selecteren" },
  "Deselect": { fr: "Désélectionner", es: "Deseleccionar", it: "Deseleziona", de: "Abwählen", nl: "Deselecteren" },
  "Photo": { fr: "Photo", es: "Foto", it: "Foto", de: "Foto", nl: "Foto" },
  "Video": { fr: "Vidéo", es: "Vídeo", it: "Video", de: "Video", nl: "Video" },
  "Imported": { fr: "Importée", es: "Importada", it: "Importata", de: "Importiert", nl: "Geïmporteerd" },
  ", imported": { fr: ", importée", es: ", importada", it: ", importata", de: ", importiert", nl: ", geïmporteerd" },
  "Choose a folder to import into first.": { fr: "Choisissez d'abord un dossier d'importation.", es: "Elige primero una carpeta de importación.", it: "Scegli prima una cartella di importazione.", de: "Wähle zuerst einen Importordner.", nl: "Kies eerst een map om naar te importeren." },
  "Choose where to put imported photos": { fr: "Choisissez où placer les photos importées", es: "Elige dónde guardar las fotos importadas", it: "Scegli dove salvare le foto importate", de: "Wähle, wohin importierte Fotos kommen", nl: "Kies waar geïmporteerde foto's komen" },
  "Choose the folder Lightroom, Photoshop Elements, digiKam or darktable watches": { fr: "Choisissez le dossier surveillé par Lightroom, Photoshop Elements, digiKam ou darktable", es: "Elige la carpeta que vigila Lightroom, Photoshop Elements, digiKam o darktable", it: "Scegli la cartella controllata da Lightroom, Photoshop Elements, digiKam o darktable", de: "Wähle den Ordner, den Lightroom, Photoshop Elements, digiKam oder darktable überwacht", nl: "Kies de map die Lightroom, Photoshop Elements, digiKam of darktable bewaakt" },

  // Bluetooth pairing (newer cameras)
  "Pair over Bluetooth": { fr: "Jumeler en Bluetooth", es: "Emparejar por Bluetooth", it: "Abbina via Bluetooth", de: "Über Bluetooth koppeln", nl: "Koppelen via Bluetooth" },
  "On the camera, open <b>Bluetooth/Smartphone Setting</b> and choose <b>Pairing Registration</b>.": {
    fr: "Sur l'appareil, ouvrez <b>Réglages Bluetooth/smartphone</b> et choisissez <b>Enregistrement du jumelage</b>.",
    es: "En la cámara, abre <b>Ajustes Bluetooth/smartphone</b> y elige <b>Registro de emparejamiento</b>.",
    it: "Sulla fotocamera, apri <b>Impostazioni Bluetooth/smartphone</b> e scegli <b>Registrazione abbinamento</b>.",
    de: "Öffne an der Kamera <b>Bluetooth/Smartphone-Einstellungen</b> und wähle <b>Kopplungsregistrierung</b>.",
    nl: "Open op de camera <b>Bluetooth/smartphone-instellingen</b> en kies <b>Koppelingsregistratie</b>." },
  "Choose the camera below. Your computer may ask you to confirm the pairing.": {
    fr: "Choisissez l'appareil ci-dessous. Votre ordinateur peut vous demander de confirmer le jumelage.",
    es: "Elige la cámara abajo. Puede que tu ordenador te pida confirmar el emparejamiento.",
    it: "Scegli la fotocamera qui sotto. Il computer potrebbe chiederti di confermare l'abbinamento.",
    de: "Wähle unten die Kamera. Dein Computer fragt eventuell, ob du die Kopplung bestätigst.",
    nl: "Kies hieronder de camera. Je computer vraagt misschien om de koppeling te bevestigen." },
  "Search again": { fr: "Rechercher à nouveau", es: "Buscar de nuevo", it: "Cerca di nuovo", de: "Erneut suchen", nl: "Opnieuw zoeken" },
  "Join this Wi-Fi network on your computer, then press Connect.": {
    fr: "Rejoignez ce réseau Wi-Fi sur votre ordinateur, puis appuyez sur Connecter.",
    es: "Conéctate a esta red Wi-Fi en tu ordenador y pulsa Conectar.",
    it: "Collega il computer a questa rete Wi-Fi, poi premi Collega.",
    de: "Verbinde deinen Computer mit diesem WLAN und drücke dann Verbinden.",
    nl: "Verbind je computer met dit wifinetwerk en druk dan op Verbinden." },
  "The network may be hidden: add it by name rather than picking it from the list.": {
    fr: "Le réseau peut être masqué : ajoutez-le par son nom au lieu de le choisir dans la liste.",
    es: "Puede que la red esté oculta: añádela por su nombre en lugar de elegirla de la lista.",
    it: "La rete potrebbe essere nascosta: aggiungila per nome invece di sceglierla dall'elenco.",
    de: "Das Netzwerk ist eventuell versteckt: füge es über den Namen hinzu, statt es aus der Liste zu wählen.",
    nl: "Het netwerk is mogelijk verborgen: voeg het toe op naam in plaats van het uit de lijst te kiezen." },
  "Network": { fr: "Réseau", es: "Red", it: "Rete", de: "Netzwerk", nl: "Netwerk" },
  "Password": { fr: "Mot de passe", es: "Contraseña", it: "Password", de: "Passwort", nl: "Wachtwoord" },
  "Copy": { fr: "Copier", es: "Copiar", it: "Copia", de: "Kopieren", nl: "Kopiëren" },
  "Copied": { fr: "Copié", es: "Copiado", it: "Copiato", de: "Kopiert", nl: "Gekopieerd" },
  "Close": { fr: "Fermer", es: "Cerrar", it: "Chiudi", de: "Schließen", nl: "Sluiten" },
  "Looking for cameras in pairing mode…": { fr: "Recherche d'appareils en mode jumelage…", es: "Buscando cámaras en modo de emparejamiento…", it: "Ricerca di fotocamere in modalità abbinamento…", de: "Suche nach Kameras im Kopplungsmodus…", nl: "Camera's in koppelmodus zoeken…" },
  "No camera found. Make sure it's in pairing mode and close by.": { fr: "Aucun appareil trouvé. Vérifiez qu'il est en mode jumelage et à proximité.", es: "No se ha encontrado ninguna cámara. Comprueba que está en modo de emparejamiento y cerca.", it: "Nessuna fotocamera trovata. Controlla che sia in modalità abbinamento e vicina.", de: "Keine Kamera gefunden. Achte darauf, dass sie im Kopplungsmodus und in der Nähe ist.", nl: "Geen camera gevonden. Zorg dat die in koppelmodus staat en dichtbij is." },
  "Ready to pair": { fr: "Prêt pour le jumelage", es: "Lista para emparejar", it: "Pronta per l'abbinamento", de: "Bereit zum Koppeln", nl: "Klaar om te koppelen" },
  "Not nearby": { fr: "Pas à proximité", es: "No está cerca", it: "Non nelle vicinanze", de: "Nicht in der Nähe", nl: "Niet in de buurt" },
  "Pair": { fr: "Jumeler", es: "Emparejar", it: "Abbina", de: "Koppeln", nl: "Koppelen" },
  "Forget": { fr: "Oublier", es: "Olvidar", it: "Dimentica", de: "Entfernen", nl: "Vergeten" },
  "Looking for {camera}…": { fr: "Recherche de {camera}…", es: "Buscando {camera}…", it: "Ricerca di {camera}…", de: "Suche nach {camera}…", nl: "{camera} zoeken…" },
  "Connecting over Bluetooth…": { fr: "Connexion en Bluetooth…", es: "Conectando por Bluetooth…", it: "Collegamento via Bluetooth…", de: "Verbindung über Bluetooth…", nl: "Verbinden via Bluetooth…" },
  "Pairing with the camera…": { fr: "Jumelage avec l'appareil…", es: "Emparejando con la cámara…", it: "Abbinamento con la fotocamera…", de: "Kopplung mit der Kamera…", nl: "Koppelen met de camera…" },
  "Asking the camera to turn on its Wi-Fi…": { fr: "Activation du Wi-Fi de l'appareil…", es: "Pidiendo a la cámara que active su Wi-Fi…", it: "Attivazione del Wi-Fi della fotocamera…", de: "Kamera schaltet ihr WLAN ein…", nl: "Camera vragen om wifi aan te zetten…" },
  "Joining {ssid}…": { fr: "Connexion à {ssid}…", es: "Conectando a {ssid}…", it: "Collegamento a {ssid}…", de: "Verbindung mit {ssid}…", nl: "Verbinden met {ssid}…" },
  // Errors from the Rust side (bluetooth.rs, wifi.rs); the keys must match exactly.
  "No Bluetooth adapter found. Turn Bluetooth on and try again.": {
    fr: "Aucun adaptateur Bluetooth trouvé. Activez le Bluetooth et réessayez.",
    es: "No se ha encontrado ningún adaptador Bluetooth. Activa el Bluetooth y vuelve a intentarlo.",
    it: "Nessun adattatore Bluetooth trovato. Attiva il Bluetooth e riprova.",
    de: "Kein Bluetooth-Adapter gefunden. Schalte Bluetooth ein und versuche es erneut.",
    nl: "Geen bluetoothadapter gevonden. Zet Bluetooth aan en probeer het opnieuw." },
  "Bluetooth isn't available on this computer.": { fr: "Le Bluetooth n'est pas disponible sur cet ordinateur.", es: "El Bluetooth no está disponible en este ordenador.", it: "Il Bluetooth non è disponibile su questo computer.", de: "Bluetooth ist auf diesem Computer nicht verfügbar.", nl: "Bluetooth is niet beschikbaar op deze computer." },
  "Couldn't find the camera. Make sure it's on and nearby, then try again.": {
    fr: "Appareil introuvable. Vérifiez qu'il est allumé et à proximité, puis réessayez.",
    es: "No se encuentra la cámara. Comprueba que está encendida y cerca y vuelve a intentarlo.",
    it: "Fotocamera non trovata. Controlla che sia accesa e vicina, poi riprova.",
    de: "Kamera nicht gefunden. Achte darauf, dass sie eingeschaltet und in der Nähe ist, und versuche es erneut.",
    nl: "Camera niet gevonden. Zorg dat die aan staat en dichtbij is en probeer het opnieuw." },
  "The camera isn't in pairing mode anymore. Choose Pairing Registration on the camera and search again.": {
    fr: "L'appareil n'est plus en mode jumelage. Choisissez Enregistrement du jumelage sur l'appareil et relancez la recherche.",
    es: "La cámara ya no está en modo de emparejamiento. Elige Registro de emparejamiento en la cámara y busca de nuevo.",
    it: "La fotocamera non è più in modalità abbinamento. Scegli Registrazione abbinamento sulla fotocamera e cerca di nuovo.",
    de: "Die Kamera ist nicht mehr im Kopplungsmodus. Wähle an der Kamera Kopplungsregistrierung und suche erneut.",
    nl: "De camera staat niet meer in koppelmodus. Kies Koppelingsregistratie op de camera en zoek opnieuw." },
  "Couldn't connect to the camera over Bluetooth.": { fr: "Impossible de se connecter à l'appareil en Bluetooth.", es: "No se ha podido conectar con la cámara por Bluetooth.", it: "Impossibile collegarsi alla fotocamera via Bluetooth.", de: "Keine Bluetooth-Verbindung zur Kamera möglich.", nl: "Kan geen verbinding maken met de camera via Bluetooth." },
  "This computer isn't paired with the camera yet. Put the camera in pairing mode, pair it in your computer's Bluetooth settings, then try again.": {
    fr: "Cet ordinateur n'est pas encore jumelé avec l'appareil. Mettez l'appareil en mode jumelage, jumelez-le dans les réglages Bluetooth de votre ordinateur, puis réessayez.",
    es: "Este ordenador aún no está emparejado con la cámara. Pon la cámara en modo de emparejamiento, emparéjala en los ajustes de Bluetooth de tu ordenador y vuelve a intentarlo.",
    it: "Questo computer non è ancora abbinato alla fotocamera. Metti la fotocamera in modalità abbinamento, abbinala nelle impostazioni Bluetooth del computer, poi riprova.",
    de: "Dieser Computer ist noch nicht mit der Kamera gekoppelt. Versetze die Kamera in den Kopplungsmodus, kopple sie in den Bluetooth-Einstellungen deines Computers und versuche es erneut.",
    nl: "Deze computer is nog niet gekoppeld met de camera. Zet de camera in koppelmodus, koppel hem in de Bluetooth-instellingen van je computer en probeer het opnieuw." },
  "The camera didn't accept this computer. Pair it again from the camera's Bluetooth menu.": {
    fr: "L'appareil n'a pas accepté cet ordinateur. Jumelez-le à nouveau depuis le menu Bluetooth de l'appareil.",
    es: "La cámara no ha aceptado este ordenador. Vuelve a emparejarla desde el menú Bluetooth de la cámara.",
    it: "La fotocamera non ha accettato questo computer. Abbinala di nuovo dal menu Bluetooth della fotocamera.",
    de: "Die Kamera hat diesen Computer nicht akzeptiert. Kopple sie erneut über das Bluetooth-Menü der Kamera.",
    nl: "De camera heeft deze computer niet geaccepteerd. Koppel opnieuw via het Bluetooth-menu van de camera." },
  "This camera can't share its Wi-Fi over Bluetooth.": { fr: "Cet appareil ne peut pas partager son Wi-Fi en Bluetooth.", es: "Esta cámara no puede compartir su Wi-Fi por Bluetooth.", it: "Questa fotocamera non può condividere il suo Wi-Fi via Bluetooth.", de: "Diese Kamera kann ihr WLAN nicht über Bluetooth weitergeben.", nl: "Deze camera kan zijn wifi niet via Bluetooth delen." },
  "The camera is busy. Switch it to shooting mode and try again.": { fr: "L'appareil est occupé. Passez en mode prise de vue et réessayez.", es: "La cámara está ocupada. Cambia al modo de disparo y vuelve a intentarlo.", it: "La fotocamera è occupata. Passa alla modalità di scatto e riprova.", de: "Die Kamera ist beschäftigt. Wechsle in den Aufnahmemodus und versuche es erneut.", nl: "De camera is bezig. Schakel naar de opnamemodus en probeer het opnieuw." },
  "The camera stopped answering over Bluetooth. Try again.": { fr: "L'appareil ne répond plus en Bluetooth. Réessayez.", es: "La cámara ha dejado de responder por Bluetooth. Vuelve a intentarlo.", it: "La fotocamera non risponde più via Bluetooth. Riprova.", de: "Die Kamera antwortet nicht mehr über Bluetooth. Versuche es erneut.", nl: "De camera reageert niet meer via Bluetooth. Probeer het opnieuw." },
  "Couldn't join the camera's network.": { fr: "Impossible de rejoindre le réseau de l'appareil.", es: "No se ha podido conectar a la red de la cámara.", it: "Impossibile collegarsi alla rete della fotocamera.", de: "Verbindung mit dem WLAN der Kamera nicht möglich.", nl: "Kan niet verbinden met het netwerk van de camera." },
  "NetworkManager (nmcli) isn't installed, so the network can't be joined automatically.": {
    fr: "NetworkManager (nmcli) n'est pas installé : impossible de rejoindre le réseau automatiquement.",
    es: "NetworkManager (nmcli) no está instalado, así que no es posible conectarse a la red automáticamente.",
    it: "NetworkManager (nmcli) non è installato, quindi non è possibile collegarsi alla rete automaticamente.",
    de: "NetworkManager (nmcli) ist nicht installiert, daher kann das Netzwerk nicht automatisch verbunden werden.",
    nl: "NetworkManager (nmcli) is niet geïnstalleerd, dus het netwerk kan niet automatisch worden verbonden." },
  "Joining the network automatically isn't supported on this system.": { fr: "Rejoindre le réseau automatiquement n'est pas pris en charge sur ce système.", es: "Conectarse a la red automáticamente no es compatible con este sistema.", it: "Il collegamento automatico alla rete non è supportato su questo sistema.", de: "Automatisches Verbinden mit dem Netzwerk wird auf diesem System nicht unterstützt.", nl: "Automatisch verbinden met het netwerk wordt op dit systeem niet ondersteund." },
};

const lang = (navigator.language || "en").slice(0, 2) as Lang;

/** Translates `english`, filling {placeholders}. With a `count`, picks the singular ("#1") form when count is 1. */
export function t(english: string, vars: Record<string, string | number> = {}, count?: number): string {
  const key = count === 1 && strings[english + "#1"] ? english + "#1" : english;
  let text = strings[key]?.[lang] ?? (count === 1 ? english.replace("items", "item").replace("{n} ", "1 ") : english);
  for (const [name, value] of Object.entries(vars)) text = text.split(`{${name}}`).join(String(value));
  return text;
}

/** Translates elements marked with data-i18n (their HTML), and placeholders marked with data-i18n-placeholder. */
export function translatePage() {
  document.documentElement.lang = lang;
  document.querySelectorAll<HTMLElement>("[data-i18n]").forEach((el) => (el.innerHTML = t(el.innerHTML.trim().replace(/\s+/g, " "))));
  document.querySelectorAll<HTMLInputElement>("[data-i18n-placeholder]").forEach((el) => (el.placeholder = t(el.placeholder)));
  document.querySelectorAll<HTMLElement>("[data-i18n-label]").forEach((el) => el.setAttribute("aria-label", t(el.getAttribute("aria-label") ?? "")));
}
