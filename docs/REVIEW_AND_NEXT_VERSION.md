# Review a dokončení místní V1

Výchozí verze: Claude 1.1.0+2, commit 652dfb5. Cíl tohoto pokračování je uzavřít místní gym tok a chyby ochrany dat před živým testem služeb a telefonů.

## Rozsah a pořadí

1. Review nové synchronizace, záloh, historie a PWA. Opravit doložené chyby: start druhého okna, neúplná cache, přeskočení řádku při pullu, automatický návrat smazaných dat.
2. Aktivní trénink: bezpečná náhrada, odebrání a pořadí cviků, validace polí, více rozepsaných tréninků; opakování zachová jednotky, poznámky a oddělení od původního plánu.
3. Typy měření: váha/opakování, vlastní váha s volitelnou přidanou zátěží, dopomoc, sekundy. Jednotky nemíchat v grafech, objemu ani odhadu 1RM. Automatická progrese váhy zůstává pouze pro vážené cviky. Starší historie se nepřekládá podle nové katalogové metadata.
4. Supersety: seskupení cviků, ukládání v plánu/historii, časovač až po dokončení kola. Krátké nastavení první instalace a tři konkrétní presety rozhraní.
5. Regresní testy, statická analýza, serverové testy, kontrola webového zámku/cache a Android/PWA sestavení. Review nových změn před lokálním commitem.

## Nálezy a rozhodnutí

- Druhé okno musí získat zámek před načtením Flutteru; překryv UI není ochrana databáze.
- Aktualizace musí stáhnout všechny povinné offline soubory a nesmí smažovat funkční cache při selhání. Tlačítko aktualizace čeká na flush rozepsaného tréninku.
- V1 synchronizace provádí úplnou kontrolu se stabilním ID stránkováním. Timestampy transakcí nejsou spolehlivý pořadník commitů; omezený časový překryv nezaručí stažení pozdě potvrzeného záznamu.
- Místní wipe odhlásí účet; cloudovou kopii nemaže. Smazání účtu je samostatná explicitně potvrzovaná akce.
- Dokončení stejného active na dvou zařízeních používá stejnou identitu session; odlišné výsledky potřebují řešení konfliktu, nikoliv dvě samostatné kopie historie.
- Asistovaný cvik nepovažuje větší dopomoc za vyšší rekord. Čas ani vlastní váha se nepočítají jako objem kg × opakování.

## Automatické ověření

Verze 1.2.0+3, 30. 9. 2026:

- 69 Flutter testů prošlo (výchozí verze měla 40). Pokrývají obnovu a synchronizaci, historii/PR, platnost návrhů, nové jednotky, ovládání cviků, onboarding, lock účtu a supersety včetně dialogu.
- 2 Node testy zámku/cache, 2 Python testy verzování webové cache a 3 serverové Python testy prošly.
- Statická analýza Flutteru bez nálezů; závěrečný read-only review neodhalil další konkrétní correctness blocker.
- Web release sestavení prošlo; povinné offline soubory byly ověřené a cache označena podle obsahu pomocí `scripts/stamp_web_build.py`.
- Android release APK pro arm64 (20,3 MB), armeabi-v7a (17,9 MB) a x86_64 (21,7 MB) sestavené. Výstup: `build/app/outputs/flutter-apk/`. Podpis je dosud vývojový, určený k instalaci pro testování, ne k publikaci v obchodě.

SDK launcher hlásí chybějící `update_engine_version.ps1`; Gradle hlásí upozornění Java native access. Přesto kontroly a sestavení skončily úspěšně. Případná údržba SDK není součástí změn projektu. Po sestavení proběhlo pouze formátování Dart kódu a oprava očekávání testů, bez změny chování aplikace.

## Živé ověření a hranice

Nový browserový náhled na http://127.0.0.1:8770 byl odmítnut kontrolou oprávnění. Živý test nové PWA tak není dokončený. Skutečné telefony, HTTPS iPhone PWA, Supabase RLS/konflikty/smazání účtu a Machine Scan vyžadují samostatnou živou zkoušku. Sestavení APK samo neprokazuje fungování na telefonu.

Platby, Elite, výživa, sporty, komunita a AI Coach do této lokální V1 nepatří. Premium nabídku lze rozhodnout až po ověření používání a nákladů. Není implementováno ani předstíráno aktivní předplatné.
