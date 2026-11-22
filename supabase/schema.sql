-- =====================================================================
-- Cantierometro - Schema database Supabase (Fase 1)
-- Da eseguire UNA volta in Supabase > SQL Editor > New query > Run.
-- =====================================================================

-- 1. TABELLE ----------------------------------------------------------

-- Un'impresa = un cliente (un abbonamento).
create table public.imprese (
    id                uuid primary key default gen_random_uuid(),
    nome              text not null,
    -- Usati nella Fase 2 (abbonamenti Stripe). Gli utenti NON possono modificarli:
    -- non esiste nessuna policy di UPDATE su questa tabella.
    stato_abbonamento text not null default 'prova'
        check (stato_abbonamento in ('prova', 'attivo', 'scaduto', 'disdetto')),
    prova_fino_al     timestamptz not null default (now() + interval '14 days'),
    creata_il         timestamptz not null default now()
);

-- Chi può accedere a quale impresa (titolare, e in futuro capocantiere).
create table public.membri (
    impresa_id uuid not null references public.imprese(id) on delete cascade,
    user_id    uuid not null references auth.users(id) on delete cascade,
    ruolo      text not null default 'titolare'
        check (ruolo in ('titolare', 'capocantiere')),
    primary key (impresa_id, user_id)
);

create index membri_user_id_idx on public.membri(user_id);

-- Tutti i dati dell'app (operai, cantieri, presenze, documenti) di un'impresa,
-- nello stesso formato del file di backup. "versione" evita che due dispositivi
-- si sovrascrivano a vicenda.
create table public.dati_impresa (
    impresa_id    uuid primary key references public.imprese(id) on delete cascade,
    dati          jsonb not null default '{"operai":[],"cantieri":[],"presenze":[],"documenti":[]}'::jsonb,
    versione      integer not null default 0,
    aggiornato_il timestamptz not null default now()
);


-- 2. FUNZIONE DI CONTROLLO --------------------------------------------

-- true se l'utente collegato è membro dell'impresa indicata.
create or replace function public.is_membro(p_impresa uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.membri
        where impresa_id = p_impresa
          and user_id = auth.uid()
    );
$$;


-- 3. SICUREZZA: ogni impresa vede e modifica solo i propri dati --------

alter table public.imprese      enable row level security;
alter table public.membri       enable row level security;
alter table public.dati_impresa enable row level security;

create policy "membri: vedo le mie appartenenze"
    on public.membri for select to authenticated
    using (user_id = auth.uid());

create policy "imprese: vedo la mia impresa"
    on public.imprese for select to authenticated
    using (public.is_membro(id));

create policy "dati: leggo i dati della mia impresa"
    on public.dati_impresa for select to authenticated
    using (public.is_membro(impresa_id));

create policy "dati: modifico i dati della mia impresa"
    on public.dati_impresa for update to authenticated
    using (public.is_membro(impresa_id))
    with check (public.is_membro(impresa_id));

-- Permessi minimi: nessun accesso per chi non ha fatto login.
revoke all on public.imprese, public.membri, public.dati_impresa from anon;
grant select         on public.imprese, public.membri to authenticated;
grant select, update on public.dati_impresa           to authenticated;


-- 4. REGISTRAZIONE: alla creazione di un account nasce la sua impresa --

create or replace function public.nuovo_utente()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    nuova_impresa uuid;
begin
    insert into public.imprese (nome)
    values (coalesce(
        nullif(trim(new.raw_user_meta_data ->> 'nome_impresa'), ''),
        split_part(new.email, '@', 1)
    ))
    returning id into nuova_impresa;

    insert into public.membri (impresa_id, user_id, ruolo)
    values (nuova_impresa, new.id, 'titolare');

    insert into public.dati_impresa (impresa_id)
    values (nuova_impresa);

    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.nuovo_utente();
