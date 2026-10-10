# DoubleMeet

Gör en gammal Double 2 till en mötesrobot för Google Meet.

- **ios/**: iPad-app. Visar Google Meet i helskärm (WKWebView) och kör basen via Doubles Basic Control SDK.
- **web/index.html**: styrsida för den som kör på distans. Har körknappar, tangentbordsstyrning, höjd, parkering och möteslänk.
- **Supabase Realtime** (broadcast) är kanalen mellan dem. Inga tabeller eller servrar behövs.

```
[Webbläsare: web/index.html] --broadcast--> [Supabase Realtime] --> [iPad: DoubleMeet] --ExternalAccessory--> [Double-basen]
            ^------------------------- status varje sekund ---------------------|
```

Den som kör sitter själv med i mötet från sin dator och har styrsidan öppen bredvid.

## Krav

- iPad med **iPadOS 15 eller senare** (iPad Air 2, mini 4, iPad 5:e generationen eller nyare). iPad Air 1 och mini 2/3 stannar på iOS 12 och fungerar inte, eftersom kamera i webbvyn kräver nyare iOS.
- Mac med Xcode och [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- Ett Supabase-projekt. Gratisnivån räcker.

## 1. Supabase

1. Skapa ett projekt, eller använd ett befintligt.
2. Under *Project Settings → API*: kopiera **Project URL** och **anon**- eller **publishable**-nyckeln.
3. Under *Realtime → Settings*: kontrollera att publika kanaler är tillåtna. Om bara privata kanaler är påslaget blir joinen nekad.
4. Hitta på ett **rum**: en lång slumpsträng, till exempel från `openssl rand -hex 16` med `double-` framför. Rummet fungerar som lösenord. Den som känner till det kan köra roboten.

## 2. iPad-appen

```sh
cd ios
cp DoubleMeet/Config.example.plist DoubleMeet/Config.plist   # fyll i URL, nyckel, rum och Meet-länk
xcodegen generate
open DoubleMeet.xcodeproj
```

I Xcode väljer du ditt team under *Signing & Capabilities*. Byt bundle-id om `com.glanser.doublemeet` krockar. Bygg sedan till iPaden med kabel.

- Bygg mot en riktig enhet. SDK:t saknar simulator-arkitektur.
- Med ett gratis Apple-ID slutar appen fungera efter 7 dagar och måste byggas om. Med ett betalt utvecklarkonto gäller den i ett år.
- Första gången frågar iPaden om kamera och mikrofon. Svara Tillåt.

Alla inställningar kan ändras i appen utan ombyggnad: **håll fingret 2 sekunder på statusrutan** längst ned till vänster.

Lägg till appen under *Inställningar → Hjälpmedel → Guidad åtkomst* och lås iPaden i appen, så kan ingen råka stänga den på kontoret.

## 3. Styrsidan

`web/index.html` är en fristående fil. Du kan öppna den direkt i Chrome eller lägga upp den på valfri statisk hosting, till exempel Vercel eller Netlify.

Fyll i URL, nyckel och rum under *Anslutning*. Med **Kopiera länk med inställningar** får du en länk som du kan skicka till kollegor. Inställningarna ligger i URL-fragmentet, sparas lokalt i webbläsaren och tas sedan bort ur adressfältet.

Styrning:

- **W A S D** eller piltangenterna kör. **Shift** ger full fart.
- **R** och **F** höjer och sänker pollen.
- **Mellanslag** stannar.
- På mobil håller du inne knapparna på skärmen.

Om roboten är parkerad fälls stöden in automatiskt när du börjar köra.

## Säkerhet i körningen

- Styrsidan skickar kommandon tio gånger per sekund medan en tangent hålls nere. Om iPaden inte får något kommando på 0,5 sekunder stannar basen, både hjulen och pollen. Det skyddar mot nätavbrott, en stängd flik och tappad fokus.
- Basen stannar också när kanalen kopplas ner eller när appen lämnar förgrunden.

## Kända risker

- **Meet i webbvy**: Google stödjer officiellt bara Meet i Safari och i Meet-appen, inte i inbäddade webbvyer. Appen presenterar sig som desktop-Safari, men Google kan ändra något som bryter det. Gå med som gäst och låt någon släppa in roboten, eller logga in med ett eget Google-konto för roboten.
- **Auto-join** letar efter knapparna "Gå med nu" och "Be om att få delta" (på svenska och engelska) i upp till 60 sekunder efter att en möteslänk har laddats. Om Google byter text slutar det fungera. Knappen *Tryck "Gå med"* på styrsidan kör samma försök igen.
- **SDK:t** (Double Basic Control SDK 0.9.1, från 2021) ligger i `ios/Vendor` under Apache 2.0. Det är en statisk binär för armv7 och arm64. Om en framtida Xcode slutar länka den finns ingen källkod att bygga om från.

## Felsökning

| Symptom | Trolig orsak |
|---|---|
| Statusrutan visar "Bas –" | Basen är avstängd eller inte parkopplad. Para basen under iPadens Bluetooth-inställningar och starta om appen. |
| "Styrning …" blinkar hela tiden | Fel URL eller nyckel, eller så tillåter Realtime bara privata kanaler. Se Xcode-loggen efter `[realtime]`. |
| Styrsidan visar "iPaden svarar inte" | Appen är i bakgrunden, eller så har iPaden och styrsidan olika rum. |
| Meet säger att webbläsaren inte stöds | Se *Kända risker*. Testa en annan Meet-länk eller logga in med ett konto. |
