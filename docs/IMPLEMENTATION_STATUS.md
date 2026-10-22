# Athlete OS: stav verze 1.2.0+3

## Implementováno

- Offline Flutter tracker: plány, volný trénink, 54 katalogových a vlastní cviky, pracovní/rozcvičovací série, váha, opakování, volitelné RIR, časovač, historie a grafy. Rozcvičení se nepočítá do objemu, PR ani progrese.
- Samostatné typy měření: váha/opakování, vlastní váha s volitelnými přidanými kg, dopomoc a čas v sekundách. Grafy oddělují jednotky; objem kg × opakování, odhad 1RM a automatické návrhy váhy se týkají vážených cviků. Historické záznamy bez typu zůstávají vážené a nejsou zpětně přepsané katalogem.
- Supersety se ukládají v plánu, tréninku i opakované historii. Pauza začne po dokončení kola; kratší cvik neblokuje další kola delšího cviku. Rozcvičení asistovaných cviků automaticky nesnižuje dopomoc.
- Krátké tříkrokové nastavení první instalace, režimy Simple/Standard/Advanced a tři rozvržení: Přehledný, Detailní, Soustředěný. Změna režimu nemaže historii.
- Záloha/obnova do JSON souboru, CSV pro český Excel, poznámky k tréninku i cvikům, editace dokončeného tréninku. Editace i smazání přepočítají PR v jedné databázové transakci; neplatná dokončená série se neuloží.
- Cvik v aktivním tréninku lze přesunout, odebrat a nahradit. Náhrada je povolená před první dokončenou sérií; jinak aplikace nabídne přidání alternativy. Odebrání zaznamenaných sérií vyžaduje potvrzení. Náhradní cvik nepřebírá progresi původního plánu ani při opakování historie.
- Vysvětlené návrhy váhy vyžadují potvrzení. Změna cílových opakování, pravidla, kroku nebo váhy zneplatní dřívější návrh. Přijetí návrhu a změna plánu se uloží atomicky.
- Více rozepsaných tréninků z různých zařízení zůstává přístupných přes výběr; reload zachovává právě zvolený trénink. Záloha umí tento stav obnovit. Dokončený trénink má deterministické ID odvozené od active ID, aby dvě zařízení nevytvořila dva různé záznamy téže session.
- Supabase synchronizace používá úplnou kontrolu záznamů a stránkuje podle stabilního ID. Pro malé V1 účty upřednostňujeme správnost před úsporou přenesených dat. Revize chrání souběžné úpravy; odhlášení uzamyká místní data účtu. Smazání dat ze zařízení také lokálně odhlásí účet, takže synchronizace data hned nevrátí.
- PWA spustí Flutter teprve po získání zámku jediného okna. Povinné offline soubory musí být stažené všechny; neúspěšná aktualizace zachová předchozí cache. Cache používá soubory jedné verze. Aktualizační tlačítko čeká na uložení tréninku.
- FastAPI Machine Scan, ověření účtu, katalogový filtr a denní limit mají serverovou implementaci. Bez konfigurace cloudu/skenu funguje místní tracker.

## Review Claudeových změn

Opravené nálezy: druhá záložka zapisovala pod překryvným varováním; offsetové stránkování podle updated_at mohlo přeskočit záznam; smazaná místní data se automaticky vracela; neúplná nová offline cache mohla nahradit funkční starou. Dále doplněna validace historie a přepočet PR po smazání.

## Testerské kolo 2026-10-22

Opraveno: autosave po dokončení tréninku už neoživí smazaný rozpracovaný trénink; číslování pracovních sérií nepočítá rozcvičky; české skloňování („2 cviky“) a desetinná čárka všude (formatNumber); hledání cviků bez diakritiky a podle českých aliasů v katalogu; prázdný stav hledání; segmentové přepínače se na 375 px nelámou; editor plánu hlídá neuložené změny a neplatné cíle sérií; přehled plánu ukazuje údaje podle typu měření; CSV má BOM a místní čas; sken má timeout a hlášku o denním limitu; potvrzení odhlášení; čitelné chybové hlášky a ošetřené výjimky u mazání, opakování, kopírování a archivace; poškozená záloha hlásí srozumitelnou chybu; časovač pauzy vibruje a pípne; hlavička tréninku ukazuje délku.

Zbývá: cíl z onboardingu se nikde nepoužívá; archivované plány nejde zobrazit ani obnovit; vlastní cviky nejde upravit ani smazat; názvy cviků jsou anglicky; osa grafu progresu je pořadí, ne datum; režimy Simple/Standard/Advanced jsou anglicky; plány se řadí podle poslední úpravy; po odebrání cviku zůstane neplatné supersetId; superset není vidět na kartě cviku; schema.sql `create policy` není idempotentní; kvóta skenu se odečte i při chybě vision volání; každá série zabírá dva řádky, trénink je dlouhý.

## Co ještě není finále

1. Živá Supabase synchronizace, RLS, smazání účtu a Machine Scan na reálných strojích nejsou potvrzené. Nastavení a měření provozních nákladů vyžadují skutečný projekt a server.
2. iPhone PWA přes HTTPS, fyzický Android, instalace a aktualizace v reálném zařízení nejsou potvrzené. Nativní iOS/TestFlight odkládáme. APK zatím používá vývojový podpis.
3. V tomto review byl pokus o nové browserové ověření localhost náhledu odmítnut oprávněním. Automatické testy a kompilace tuto zkoušku nenahrazují.

## Ověření

Aktuální výsledky automatických kontrol a sestavení jsou zaznamenané v docs/REVIEW_AND_NEXT_VERSION.md. Build není důkaz testu na telefonu.

## Další pořadí

Nakonfigurovat cloud a scan, provést živou zkoušku účtů/konfliktů a fyzický Android + iPhone PWA test. Teprve po jejich úspěchu pozvat testery. Místní funkce V1 jsou implementované; označení téměř finální verze vyžaduje ještě praktickou zkoušku těchto toků.

Beta zůstává zdarma. Premium a ceny se budou rozhodovat až z použití a nákladů. Jednorázový offline nákup může financovat místní funkce; průběžné AI/cloud náklady potřebují předplatné nebo omezené kredity. V této verzi není implementovaný platební systém.
