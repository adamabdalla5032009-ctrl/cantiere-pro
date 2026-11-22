# Cantierometro – Configurazione del cloud (Fase 1)

Da questa versione i dati non stanno più solo nel browser: ogni impresa ha un account
(email + password) e i dati sono salvati su **Supabase**, quindi si ritrovano su ogni
telefono o computer. La demo funziona come prima.

Finché non completi i passi qui sotto, il sito mostra "Accesso non ancora configurato"
e si può usare solo la demo.

---

## 1. Crea il progetto Supabase (10 minuti)

1. Vai su [supabase.com](https://supabase.com) e crea un account (piano **Free**).
2. **New project**:
   - Name: `cantiere-pro`
   - Database password: generane una forte e **salvala** (es. nel gestore password).
   - Region: **Central EU (Frankfurt)**, per tenere i dati in Europa (GDPR).
3. Aspetta 1–2 minuti che il progetto sia pronto.

## 2. Crea le tabelle e le regole di sicurezza

1. Nel menu a sinistra: **SQL Editor** → **New query**.
2. Apri il file `supabase/schema.sql` di questa cartella, copia tutto il contenuto e incollalo.
3. Premi **Run**. Deve comparire "Success. No rows returned".

Lo script crea:
- `imprese`: un cliente = un'impresa (con i campi per l'abbonamento della fase 2);
- `membri`: quali account possono entrare in quale impresa;
- `dati_impresa`: i dati dell'app (operai, cantieri, presenze, documenti);
- le regole per cui **ogni impresa vede e modifica solo i propri dati**;
- la creazione automatica dell'impresa quando qualcuno si registra.

## 3. Impostazioni di accesso

In **Authentication**:

1. **URL Configuration**
   - Site URL: `https://adamabdalla5032009-ctrl.github.io/cantiere-pro/`
   - Redirect URLs → Add URL: lo stesso indirizzo.
2. **Sign In / Providers → Email**
   - Email provider: attivo.
   - Minimum password length: `8`.
   - Confirm email: vedi il punto 5.

## 4. Collega il sito a Supabase

1. In **Project Settings → API Keys** (o **Data API**) copia:
   - il **Project URL** (tipo `https://abcdefgh.supabase.co`);
   - la chiave **anon public** oppure **publishable** (MAI la `service_role` / `secret`).
2. Apri `index.html` e cerca `CONFIGURAZIONE SUPABASE`. Compila le due righe:

   ```js
   const SUPABASE_URL = 'https://abcdefgh.supabase.co';
   const SUPABASE_ANON_KEY = 'la-tua-chiave-anon-o-publishable';
   ```

La chiave anon/publishable è pensata per stare nel sito: i dati sono protetti dalle
regole del punto 2, non dalla segretezza della chiave. La chiave `service_role` invece
non va **mai** messa nel sito.

## 5. Email di conferma e recupero password

Il servizio email incluso in Supabase è solo per i test: manda pochissime email l'ora e
solo agli indirizzi dei membri del tuo team Supabase. Finché usi solo quello, tieni
**Confirm email** spento (Authentication → Sign In / Providers).

Prima di aprire ad altre imprese serve un servizio email vero, altrimenti "Password
dimenticata?" non arriva ai clienti. Consiglio **Resend** (gratis fino a 3.000 email al mese).

### 5.1 Un dominio tuo
Resend (come ogni servizio serio) manda email solo da un dominio che possiedi, non da Gmail.
Registra un dominio, per esempio `cantierometro.it` (circa 10–15 €/anno), con un registrar
come Aruba, Register.it, OVH o Cloudflare. Ti servirà anche per l'indirizzo del sito.

### 5.2 Resend
1. Crea un account su [resend.com](https://resend.com).
2. **Domains → Add domain**: scrivi il tuo dominio e scegli la regione **EU (Ireland)**.
3. Resend mostra alcuni record DNS (TXT e MX). Aggiungili nel pannello DNS del registrar,
   copiandoli uno per uno, poi premi **Verify** (può richiedere da pochi minuti a qualche ora).
4. **API Keys → Create API key**, permesso **Sending access**. Copiala e tienila per il punto
   successivo. È segreta: non metterla nel sito e non mandarla in chat.

### 5.3 Collega Resend a Supabase
In Supabase → **Authentication → Emails → SMTP Settings** → **Enable custom SMTP**:

| Campo | Valore |
| --- | --- |
| Sender email | `noreply@iltuodominio.it` |
| Sender name | `Cantierometro` |
| Host | `smtp.resend.com` |
| Port | `465` |
| Username | `resend` |
| Password | la API key del punto 5.2 |

Premi **Save**.

### 5.4 Email in italiano
In **Authentication → Emails → Templates**:

- **Confirm signup**: oggetto `Conferma il tuo account Cantierometro`. Nel corpo cancella il
  testo inglese e incolla il contenuto di `supabase/email/conferma-account.html`.
- **Reset password**: oggetto `Reimposta la password di Cantierometro`, corpo da
  `supabase/email/reimposta-password.html`.

Salva ogni modello.

### 5.5 Riattiva la conferma email
In **Authentication → Sign In / Providers** riaccendi **Confirm email** e salva. Prova
registrandoti con un'altra email tua e controlla anche la cartella spam.

## 5-bis. Privacy e termini

Il sito ha due pagine: `privacy.html` (Informativa privacy) e `termini.html` (Termini di
servizio, con l'accordo sul trattamento dei dati degli operai). Chi si registra deve
spuntare la casella di accettazione; data e versione vengono salvate nel suo account.

1. Apri i due file e cerca le parti evidenziate in giallo `[TRA PARENTESI QUADRE]`:
   nome o ragione sociale, indirizzo, partita IVA, email di contatto, servizio email, città del foro.
2. Il **titolare** deve essere una persona maggiorenne o un'impresa. Se sei minorenne
   indica un genitore, o l'impresa che gestirà Cantierometro: decidilo con il commercialista.
3. Sono **bozze**: prima di avere clienti paganti falle rivedere da un consulente privacy o
   da un avvocato.
4. Se in futuro le modifichi, aggiorna la data in alto nelle pagine e la costante
   `VERSIONE_TERMINI` in `index.html`.

## 5-ter. Aiuto, contatti e suggerimenti

Dal **☰ Menu → Aiuto, contatti e suggerimenti** gli utenti possono scriverti un'email o
mandarti un suggerimento o una segnalazione.

1. **Attiva i suggerimenti (una volta sola):** in Supabase → SQL Editor → New query incolla
   `supabase/feedback.sql` e premi **Run**. I messaggi li leggi in **Table Editor → feedback**.
   Finché non lo fai, il modulo apre l'app email al posto dell'invio diretto.
2. **WhatsApp (facoltativo):** quando avrai un numero dedicato (consigliato WhatsApp Business),
   in `index.html` compila `WHATSAPP_NUMERO` con prefisso 39 e senza spazi, es. `'393331234567'`.
   Il tasto verde compare da solo.

## 5-quater. Accessi per il capocantiere

Il titolare può dare a un capocantiere un accesso che serve **solo a segnare le presenze**:
non vede paghe, preventivi, spese e previsioni, nemmeno provando a leggere il database.

1. **Attivazione (una volta sola):** in Supabase → SQL Editor → New query incolla
   `supabase/capocantiere.sql` e premi **Run**.
2. **Dall'app (titolare):** ☰ Menu → **Accessi capocantiere** → **Crea un codice invito** →
   **Invia su WhatsApp**. Il messaggio contiene un link già pronto con il codice.
3. **Il capocantiere** apre il link, inserisce email e password e accetta i termini: entra
   direttamente nella sua schermata "Squadra in cantiere".
4. Il codice vale **7 giorni** e **una sola volta**. Dalla stessa finestra il titolare vede chi ha
   accesso, può **togliere l'accesso** o **annullare** un codice non usato.

Le giornate segnate dal capocantiere compaiono al titolare con la nota "Segnato dal
capocantiere"; il costo lo calcola il database con la paga e la maggiorazione degli straordinari.

## 5-quinquies. App sul telefono

Il sito si può installare come un'app (☰ Menu → **Installa l'app sul telefono**) e si apre anche
senza segnale, mostrando gli ultimi dati salvati su quel telefono. Le modifiche fatte senza
segnale partono da sole quando torna la rete. I file che servono sono `manifest.json`, `sw.js`
e la cartella `icone`.

## 6. Pubblica la nuova versione su GitHub

1. Vai sul repository `cantiere-pro` su GitHub → **Add file → Upload files**.
2. Trascina `index.html`, `privacy.html` e `termini.html` (e se vuoi anche `LEGGIMI.md` e la
   cartella `supabase`), poi **Commit changes**. Non copiare il testo nell'editor di GitHub:
   carica sempre i file interi. Non caricare la cartella `.claude`.
3. Dopo circa un minuto GitHub Pages pubblica la nuova versione.

## 7. Passaggio dei dati di tuo padre

Sul **suo telefono**, nello stesso browser che usa adesso:

1. **Prima di pubblicare la nuova versione**, fagli premere **"Salva Backup"** e conserva il
   file (Drive, email). È la copia di sicurezza.
2. Dopo la pubblicazione apre il sito, sceglie **"Registrati gratis"** e crea l'account con
   la sua email e il nome dell'impresa.
3. Appena entra, l'app trova i dati della vecchia versione e chiede se importarli: **OK**.
4. Da quel momento i dati sono nel cloud: in alto vede **"☁️ Salvato"** dopo ogni modifica e
   può entrare con lo stesso account anche dal computer.

Se l'import automatico non compare (es. browser diverso), può usare **"⬆️ Ripristina"** con
il file di backup del punto 1.

---

## Da sapere

- **Piano gratuito di Supabase:** il progetto va in pausa dopo circa una settimana senza
  nessun utilizzo; con l'uso quotidiano non succede. Quando ci saranno clienti paganti
  conviene il piano Pro.
- **Due dispositivi insieme:** se due persone modificano nello stesso momento, il secondo
  salvataggio viene bloccato e l'app ricarica i dati aggiornati chiedendo di ripetere
  l'ultima modifica. Nessuno sovrascrive il lavoro dell'altro senza accorgersene.
- **Prossimo passo (fase 2):** abbonamenti con Stripe. Le colonne `stato_abbonamento` e
  `prova_fino_al` della tabella `imprese` sono già pronte.
