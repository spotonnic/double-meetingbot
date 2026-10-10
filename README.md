# DoubleMeet

Gör en gammal Double 2 till en mötesrobot för Google Meet.

- **ios/**: iPad-app. Visar Google Meet i helskärm (WKWebView) och kör basen via Doubles Basic Control SDK.
- **web/index.html**: styrsida för den som kör på distans. Har körknappar, tangentbordsstyrning, höjd, parkering och möteslänk.
- **Supabase Realtime** (privat kanal) är kanalen mellan dem. Åtkomsten styrs av Google-inloggning på glanser.com och av databasregler.

```
[Webbläsare: web/index.html] --broadcast--> [Supabase Realtime] --> [iPad: DoubleMeet] --ExternalAccessory--> [Double-basen]
            ^------------------------- status varje sekund ---------------------|
```

Den som kör sitter själv med i mötet från sin dator och har styrsidan öppen bredvid.

## Krav

- iPad med **iPadOS 15 eller senare** (iPad Air 2, mini 4, iPad 5:e generationen eller nyare). iPad Air 1 och mini 2/3 stannar på iOS 12 och fungerar inte, eftersom kamera i webbvyn kräver nyare iOS.
- Mac med Xcode och [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- Ett Supabase-projekt.
- Admin-åtkomst till Glansers Google Workspace, för att skapa OAuth-klienten.

## 1. Supabase

1. Skapa projektet `double-meetingbot` i organisationen glanser, region eu-north-1.
2. Kör `supabase/migrations/0001_realtime_access.sql` i SQL-editorn. Migrationen sätter upp åtkomstreglerna för den privata kanalen `double-office`. Bara två sorters konton släpps in:
   - användare som loggat in med Google och har en e-post på glanser.com
   - robotkonton som finns i `private.double_robots`
3. Under *Realtime → Settings*: stäng av **Allow public access**. Då måste alla kanaler gå genom reglerna ovan.
4. Skapa ett robotkonto för iPaden. Kör i SQL-editorn och byt lösenordet:

```sql
with u as (
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
          'double-robot@glanser.com', extensions.crypt('BYT-TILL-ETT-LÅNGT-LÖSENORD', extensions.gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '')
  returning id, email
), i as (
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, created_at, updated_at)
  select gen_random_uuid(), id, id::text, jsonb_build_object('sub', id::text, 'email', email, 'email_verified', true),
         'email', now(), now() from u
)
insert into private.double_robots (user_id, name) select id, 'Kontoret' from u;
```

Robotkontot loggar in med lösenord, inte med Google. Kontot släpps in för att det står i `double_robots`, inte för att adressen slutar på glanser.com.

## 2. Google-inloggning (bara glanser.com)

1. Gå till Google Cloud Console i Glansers Workspace-organisation. Under *Google Auth Platform → Branding/Audience* sätter du **User type: Internal**. Då kan bara konton på glanser.com logga in.
2. Under *Clients* skapar du en **Web application** med redirect-URI `https://<projekt-ref>.supabase.co/auth/v1/callback`.
3. I Supabase går du till *Authentication → Sign In / Providers → Google*. Slå på providern och klistra in Client ID och Client Secret.
4. I Supabase går du till *Authentication → URL Configuration*. Sätt Site URL och Redirect URLs till styrsidans adress på Vercel.

Domänen kontrolleras på tre ställen: Googles Internal-läge, styrsidan (som loggar ut andra konton direkt) och databasreglerna. Det är databasreglerna som faktiskt skyddar. Styrsidan gör bara upplevelsen tydligare.

## 3. iPad-appen

```sh
cd ios
cp DoubleMeet/Config.example.plist DoubleMeet/Config.plist   # URL, publishable key, robotkontots e-post och lösenord
xcodegen generate
open DoubleMeet.xcodeproj
```

I Xcode väljer du ditt team under *Signing & Capabilities*. Byt bundle-id om `com.glanser.doublemeet` krockar. Bygg sedan till iPaden med kabel.

- Bygg mot en riktig enhet. SDK:t saknar simulator-arkitektur.
- Med ett gratis Apple-ID slutar appen fungera efter 7 dagar och måste byggas om. Med ett betalt utvecklarkonto gäller den i ett år.
- Första gången frågar iPaden om kamera och mikrofon. Svara Tillåt.

**Utanför möten** visar iPaden en viloskärm i Glanser-stil: "Ledig", styrsidans adress och status för basen och uppkopplingen. När någon skickar in roboten i ett möte från styrsidan byter den till Meet. "Lämna mötet" stänger samtalet och går tillbaka till viloskärmen.

**Robotläge** är standard under möten. Den som ringer in visas i helskärm, och Meets knappar och den egna bilden döljs. Ljudet går som vanligt. Appen hittar videon genom att lyssna på WebRTC-strömmarna (`ios/DoubleMeet/RobotMode.js`), inte genom Meets sidstruktur. Därför tål läget att Google ändrar sitt gränssnitt. Saknas video, till exempel i väntrummet eller när kameran är av, syns Meets vanliga vy. På styrsidans Möte-flik går det att:

- växla mellan Robotläge och Meet-vy
- välja Fyll skärmen eller Hela bilden (bättre när någon delar skärm)
- bläddra mellan deltagarna

Med flera deltagare visas den största bilden. Meets egen markering av vem som pratar används inte.

**Inställningar:** håll fingret 2 sekunder på viloskärmen, eller på statusraden under ett möte. Där finns också "Logga in roboten på Google", om roboten ska gå in i möten med ett eget Google-konto i stället för som gäst.

Lägg till appen under *Inställningar → Hjälpmedel → Guidad åtkomst* och lås iPaden i appen, så kan ingen råka stänga den på kontoret.

## 4. Styrsidan

`web/` publiceras som en statisk sajt på Vercel. Fyll i projektets URL och publishable key i `web/config.js`. Nyckeln är publik; skyddet ligger i inloggningen och databasreglerna.

Sidan är byggd för mobilen först. Där finns tre flikar längst ned: **Kör** (joystick, fart, höjd, parkering och stopp), **Möte** (skicka in roboten, gå med, lämna) och **Status**. På dator visas allt på en gång. Det går att klistra in en hel Meet-länk eller bara mötes-koden (abc-defg-hij).

Sidan visar:

- om roboten är online, batterinivå och om den är parkerad
- vem som kör just nu och sedan när
- vilket möte roboten är i
- vem som använde den senast
- vilka som har styrsidan öppen

En person kör åt gången. Platsen blir ledig 10 sekunder efter att föraren slutat köra. Vem som helst kan alltid trycka stopp.

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
| "Styrning: inloggning misslyckades" | Fel e-post eller lösenord för robotkontot. Se Xcode-loggen efter `[auth]`. |
| "Styrning …" blinkar hela tiden | Robotkontot saknas i `private.double_robots`, eller så är migrationen inte körd. Se Xcode-loggen efter `[realtime]`. |
| Styrsidan visar "Roboten svarar inte" | Appen är i bakgrunden, eller så har iPaden och styrsidan olika rum. |
| Styrsidan säger "Nekad eller nere" | Kontot är inte ett Google-konto på glanser.com, eller så är migrationen inte körd. |
| Meet säger att webbläsaren inte stöds | Se *Kända risker*. Testa en annan Meet-länk eller logga in med ett konto. |

## Licens och rättighetshavare

Se `NOTICE`. Double Basic Control SDK tillhör Double Robotics, Inc. och används under Apache 2.0 (`ios/Vendor/DoubleControlSDK-LICENSE`). Projektet har inget samband med Double Robotics.
