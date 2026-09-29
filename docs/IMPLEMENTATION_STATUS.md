# Athlete OS: stav po M1 a další pořadí

## Co už funguje v kódu

- Lokální plány i volný trénink bez plánu, katalog 53 cviků, vlastní cvik, aktivní trénink a historie. Cvik lze přidat i do rozepsaného tréninku.
- Pracovní a rozcvičovací série jsou oddělené. Rozcvičení se nepočítá do PR, objemu ani návrhu progrese. Plánované pracovní cíle zůstávají snímkem plánu při startu tréninku.
- Poznámka k tréninku, přidání a odebrání pracovní série, časovač, základní grafy, vysvětlené návrhy další váhy.
- Drift SQLite lokálně, ruční JSON záloha/obnova přes schránku, synchronizační protokol a server Machine Scan mají implementaci. Bez nakonfigurovaných externích služeb funguje pouze lokální režim.
- Android debug APK a webový build lze sestavit na Windows. Web má vlastní offline cache; skutečný iPhone zatím nebyl ověřen.

## Co brání označení „téměř hotová beta“

1. **Data uživatele:** Ruční záloha přes schránku je funkční základ, ale je potřeba ji uložit do vlastního souboru; schránka sama data neuchová. Chybí pohodlný souborový export/import a ověřená cloudová záloha na reálném projektu.
2. **Web/PWA:** Ověřit čerstvou instalaci, aktualizaci service workeru, offline otevření a uložení/obnovení rozpracovaného tréninku na skutečném iPhonu přes HTTPS. Test na localhostu toto nenahrazuje.
3. **Úplnost gym toku:** Chybí bezpečná editace dokončeného tréninku, poznámky k jednotlivým cvikům, náhrada cviku během tréninku, podpora supersetů a promyšlené bodyweight záznamy. Stávající návrh váhy pracuje v kg a pro cviky s vlastní vahou automatický návrh nevytváří.
4. **Cloud a sken:** Supabase schéma, RLS, konflikty a limity skenu musí projít živým integračním testem; sken je třeba měřit na skutečných strojích. API klíče patří jen na server.
5. **Distribuce:** Android APK je sestavitelné, fyzický Android a iPhone PWA nebyly tímto krokem potvrzeny. Nativní iPhone sestavení odkládáme.

## Pořadí pokračování

Nejdřív souborový export/import a editace historie, pak dokončení aktivního tréninkového toku. Potom ověřený cloud a sken, fyzická PWA/Android zkouška a teprve následně pozvání dalších lidí.

Monetizaci technicky nepředstíráme: beta zůstává zdarma. Offline tracker může být jednorázový nákup nebo bezplatný základ; nákladné cloudové/AI funkce potřebují průběžné financování (předplatné nebo měřené kredity). Konkrétní cenu, hranici premium a obchodní model určí až měření používání a provozních nákladů mimo první malou skupinu.

## Aktualizace (Claude, verze 1.1.0+2)

Přistálo: oprava perzistence webu (Drift na hlavním vlákně + flush po commitu; drift worker se do IndexedDB nedostal), SW upgrade banner a zámek jednoho okna, souborová záloha/obnova a CSV, detail a úprava dokončeného tréninku s přepočtem PR, poznámky ke cvikům, sync přes `RemoteApi` s inkrementálním pull kurzorem `last_pull_at` (7 testů s fake klientem), `supabase/migrations/002_v1_1.sql` (index + `delete_my_account`), smazání účtu a dat v zařízení.

Zbývá: náhrada cviku uprostřed tréninku, typy cviků (bodyweight/assisted/time), supersety, více `active` řádků z různých zařízení, živý test Supabase + skenu, iPhone PWA přes HTTPS, fyzický Android.
