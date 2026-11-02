// Translations for the desktop app. Keys are the English text; {name} placeholders are filled in by t().
// Counts use separate "one" keys ending in "#1" for the singular.

type Lang = "fr" | "es" | "it" | "de" | "nl";

const strings: Record<string, Record<Lang, string>> = {
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
