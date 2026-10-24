# Athlete OS

Mobilní beta gym trackeru. Tréninkové plány, offline zápis sérií, historie, progres a návrh další váhy fungují lokálně. Účet, synchronizace a Machine Scan vyžadují vlastní nastavení služeb.

Verze 1.2 přidává vlastní váhu, dopomoc a časové cviky s oddělenými jednotkami, supersety v plánech i tréninku, bezpečnou náhradu a přesouvání cviků, krátké úvodní nastavení a tři rozvržení. Starší historie zachovává původní způsob měření.

## Spuštění aplikace

1. Nainstaluj Flutter SDK a Android SDK; ověř `flutter doctor -v`.
2. V kořeni projektu spusť `flutter pub get` a `flutter run` na Android zařízení nebo emulátoru.
3. Pro Android APK použij `flutter build apk --debug`. Výstup je v `build/app/outputs/flutter-apk/`.

Pro rychlejší testovací sestavení použij `flutter build apk --release --split-per-abi`; běžné současné Android telefony používají `app-arm64-v8a-release.apk`. Release je zatím podepsaný vývojovým klíčem a není připravený pro publikaci v obchodě.

Bez dalších proměnných aplikace ukládá data jen do lokální SQLite databáze telefonu. Data před smazáním aplikace nebo telefonu zálohuj; lokální instalace není náhrada cloudu.

V Nastavení lze zálohu uložit do souboru (JSON), obnovit ji ze souboru v prázdné instalaci a exportovat série do CSV (oddělovač `;`, desetinná čárka pro český Excel). Záloha zahrnuje i poznámky. Schránka zůstává jako záložní varianta.

## Web / PWA (iPhone)

Spusť `flutter build web --release` a potom `python scripts/stamp_web_build.py`. Druhý krok ověří povinné offline soubory a vytvoří unikátní cache podle obsahu sestavení; je nutný při každém novém buildu. Obsah `build/web` nahraj na HTTPS hosting a otevři v Safari → Sdílet → Přidat na plochu. Data jsou v IndexedDB prohlížeče, **nejsou trvalá záloha** – pravidelně ukládej zálohu do souboru. Service worker používá kompletní cache jedné verze; aktualizace se nabídne lištou a před načtením uloží rozepsaný trénink. Pokud se povinné soubory nové verze nestáhnou, zůstává předchozí offline verze. Flutter se spustí až po získání zámku jednoho okna; druhé okno nezačne zapisovat databázi. Web vyžaduje prohlížeč s Web Locks a HTTPS (nebo localhost při vývoji).

Pozor při vývoji: po `flutter build web` restartuj lokální server, jinak servíruje smazanou složku.

## Účet a synchronizace

Vytvoř Supabase projekt a spusť SQL z `supabase/schema.sql` (jde spustit opakovaně). Existující projekt aktualizuj migracemi ze `supabase/migrations/` ve vzestupném pořadí. V Supabase Auth nastav redirect URL `athleteos://login-callback/` a povol přihlášení e-mailem. Aplikaci sestav s:

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Tréninky vznikají lokálně a synchronizují se po přihlášení. Serverová funkce `push_entity` kontroluje revizi každého záznamu. Při souběžné úpravě stejného záznamu se objeví volba mezi místní a cloudovou verzí. Jedna instalace se z bezpečnostních důvodů váže na jeden účet; předání telefonu jinému člověku vyžaduje odstranění lokálních dat aplikace. Přihlášení do jiného účtu na stejné instalaci je zablokováno pro synchronizaci. Smazání dat ze zařízení lokálně odhlásí účet; cloudová kopie zůstává. Více rozepsaných tréninků lze přepínat bez ztráty záznamů. Synchronizace V1 načítá všechny záznamy podle stabilního ID a kontroly revize.

## Machine Scan

Vytvoř Python prostředí a nainstaluj `server/requirements.txt`. Server vyžaduje `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` a `OPENAI_API_KEY`. Volitelný `OPENAI_VISION_MODEL` má výchozí hodnotu `gpt-4o-mini`.

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --use-deprecated=legacy-certs -r server\requirements.txt
$env:SUPABASE_URL='https://YOUR_PROJECT.supabase.co'
$env:SUPABASE_PUBLISHABLE_KEY='YOUR_PUBLISHABLE_KEY'
$env:OPENAI_API_KEY='YOUR_API_KEY'
.\.venv\Scripts\python.exe -m uvicorn server.main:app --host 127.0.0.1 --port 8000
```

Na fyzickém telefonu musí `SCAN_API_URL` ukazovat na dostupnou HTTPS adresu serveru. Sestav aplikaci s `--dart-define=SCAN_API_URL=https://YOUR_SERVER`. Pro beta provoz nastav limit výdajů a monitoruj počet skenů. Fotografii aplikace neposílá do tréninkové historie; server ji nezapisuje do souboru ani databáze. Externí poskytovatel ji zpracuje podle svých podmínek.

## Ověření a beta

`flutter analyze`, `flutter test`, `node --test test/web_runtime_test.cjs` a `python -m pytest server -q` jsou automatické kontroly. Před pozváním testerů na fyzických telefonech projdi vytvoření plánu, záznam a obnovení rozepsaného tréninku bez signálu, následnou synchronizaci, konflikt na dvou telefonech a skeny strojů z reálného gymu. Poznamenej počet správných návrhů, chyb a čas odpovědi.

Android lze sestavit na Windows. Pro první vlastní používání na iPhonu počítáme s webovou PWA: `flutter build web --release`, nasazení přes HTTPS a přidání stránky na plochu v Safari. Lokální `http://127.0.0.1` není adresa dostupná z iPhonu. Offline režim a trvalé uložení na iPhonu je nutné ověřit na skutečném zařízení; vymazání dat Safari/PWA může odstranit lokální tréninky. Nativní iOS aplikace a TestFlight později vyžadují Mac s Xcode a odpovídající vývojářský účet.

Aktuální stav implementace a zbývající práce jsou v `docs/IMPLEMENTATION_STATUS.md`.

První dva týdny sleduj, kolik ze šesti lidí dobrovolně zaznamená několik tréninků a chce pokračovat. Rozhovory s nimi určují další opravy; placenou nabídku testuj až na větším vzorku mimo první skupinu.
