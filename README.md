# Athlete OS

Mobilní beta gym trackeru. Tréninkové plány, offline zápis sérií, historie, progres a návrh další váhy fungují lokálně. Účet, synchronizace a Machine Scan vyžadují vlastní nastavení služeb.

## Spuštění aplikace

1. Nainstaluj Flutter SDK a Android SDK; ověř `flutter doctor -v`.
2. V kořeni projektu spusť `flutter pub get` a `flutter run` na Android zařízení nebo emulátoru.
3. Pro Android APK použij `flutter build apk --debug`. Výstup je v `build/app/outputs/flutter-apk/`.

Bez dalších proměnných aplikace ukládá data jen do lokální SQLite databáze telefonu. Data před smazáním aplikace nebo telefonu zálohuj; lokální instalace není náhrada cloudu.

## Účet a synchronizace

Vytvoř Supabase projekt a spusť SQL z `supabase/schema.sql`. V Supabase Auth nastav redirect URL `athleteos://login-callback/` a povol přihlášení e-mailem. Aplikaci sestav s:

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Tréninky vznikají lokálně a synchronizují se po přihlášení. Serverová funkce `push_entity` kontroluje revizi každého záznamu. Při souběžné úpravě stejného záznamu se objeví volba mezi místní a cloudovou verzí. Jedna instalace se z bezpečnostních důvodů váže na jeden účet; předání telefonu jinému člověku vyžaduje odstranění lokálních dat aplikace. Přihlášení do jiného účtu na stejné instalaci je zablokováno pro synchronizaci.

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

`flutter analyze`, `flutter test` a `python -m pytest server -q` jsou automatické kontroly. Před pozváním testerů na fyzických telefonech projdi vytvoření plánu, záznam a obnovení rozepsaného tréninku bez signálu, následnou synchronizaci, konflikt na dvou telefonech a skeny strojů z reálného gymu. Poznamenej počet správných návrhů, chyb a čas odpovědi.

Android lze sestavit na Windows. Pro iPhone sestavení a TestFlight je potřeba Mac s Xcode a Apple Developer Program. iOS sestavení ani distribuce zatím nebyly ověřeny.

První dva týdny sleduj, kolik ze šesti lidí dobrovolně zaznamená několik tréninků a chce pokračovat. Rozhovory s nimi určují další opravy; placenou nabídku testuj až na větším vzorku mimo první skupinu.
