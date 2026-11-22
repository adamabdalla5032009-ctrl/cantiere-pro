// Cantierometro - service worker
// Rende l'app installabile e le permette di aprirsi anche senza segnale.
// Le pagine si scaricano sempre dalla rete quando c'è (così gli aggiornamenti arrivano subito);
// la copia salvata serve solo quando la rete non risponde.
// I dati (Supabase) non passano mai da qui: vanno sempre letti e salvati online.

const CACHE = 'cantierometro-v1';
const FILE_APP = [
    './',
    './index.html',
    './privacy.html',
    './termini.html',
    './manifest.json',
    './icone/icona-192.png',
    './icone/icona-512.png',
    './icone/apple-touch-icon.png',
    'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.49.4/dist/umd/supabase.js'
];

self.addEventListener('install', (evento) => {
    evento.waitUntil(
        caches.open(CACHE)
            .then((cache) => cache.addAll(FILE_APP))
            .then(() => self.skipWaiting())
    );
});

self.addEventListener('activate', (evento) => {
    evento.waitUntil(
        caches.keys()
            .then((nomi) => Promise.all(nomi.filter((n) => n !== CACHE).map((n) => caches.delete(n))))
            .then(() => self.clients.claim())
    );
});

function salvaInCache(richiesta, risposta) {
    if (risposta && risposta.ok) {
        const copia = risposta.clone();
        caches.open(CACHE).then((cache) => cache.put(richiesta, copia));
    }
    return risposta;
}

self.addEventListener('fetch', (evento) => {
    const richiesta = evento.request;
    if (richiesta.method !== 'GET') return;

    const url = new URL(richiesta.url);
    if (url.hostname.endsWith('supabase.co')) return;   // dati e login: sempre online

    // File dell'app (stesso sito): prima la rete, poi la copia salvata
    if (url.origin === self.location.origin) {
        evento.respondWith(
            fetch(richiesta)
                .then((risposta) => salvaInCache(richiesta, risposta))
                .catch(() => caches.match(richiesta, { ignoreSearch: true })
                    .then((salvata) => salvata || (richiesta.mode === 'navigate' ? caches.match('./index.html') : undefined)))
        );
        return;
    }

    // Librerie esterne con versione fissa: prima la copia salvata
    evento.respondWith(
        caches.match(richiesta).then((salvata) => salvata || fetch(richiesta).then((risposta) => salvaInCache(richiesta, risposta)))
    );
});
