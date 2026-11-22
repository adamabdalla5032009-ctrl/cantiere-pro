-- =====================================================================
-- Cantierometro - Accessi per il capocantiere
-- Da eseguire UNA volta in Supabase > SQL Editor > New query > Run
-- (dopo schema.sql e feedback.sql).
--
-- Il capocantiere:
--   - entra con un codice invito creato dal titolare;
--   - vede solo i nomi di operai e cantieri aperti e segna le presenze;
--   - NON può leggere paghe, preventivi, spese o previsioni: i dati completi
--     sono leggibili solo dal titolare, anche chiamando il database direttamente.
-- =====================================================================


-- 1. Data di ingresso dei membri ----------------------------------------
alter table public.membri add column if not exists aggiunto_il timestamptz not null default now();


-- 2. Chi è il titolare --------------------------------------------------
create or replace function public.is_titolare(p_impresa uuid)
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
          and ruolo = 'titolare'
    );
$$;


-- 3. I dati completi li legge e modifica solo il titolare ----------------
drop policy if exists "dati: leggo i dati della mia impresa" on public.dati_impresa;
drop policy if exists "dati: modifico i dati della mia impresa" on public.dati_impresa;

create policy "dati: il titolare legge"
    on public.dati_impresa for select to authenticated
    using (public.is_titolare(impresa_id));

create policy "dati: il titolare modifica"
    on public.dati_impresa for update to authenticated
    using (public.is_titolare(impresa_id))
    with check (public.is_titolare(impresa_id));


-- 4. Codici invito ------------------------------------------------------
create table if not exists public.inviti (
    codice     text primary key,
    impresa_id uuid not null references public.imprese(id) on delete cascade,
    ruolo      text not null default 'capocantiere' check (ruolo in ('capocantiere')),
    creato_da  uuid not null references auth.users(id) on delete cascade,
    creato_il  timestamptz not null default now(),
    scade_il   timestamptz not null default (now() + interval '7 days'),
    usato_da   uuid references auth.users(id) on delete set null,
    usato_il   timestamptz
);

alter table public.inviti enable row level security;
-- Nessun accesso diretto: solo tramite le funzioni qui sotto.
revoke all on public.inviti from anon, authenticated;


-- 5. Funzioni per il titolare --------------------------------------------

-- Impresa di cui l'utente collegato è titolare (null se non lo è)
create or replace function public.mia_impresa_titolare()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select impresa_id from public.membri
    where user_id = auth.uid() and ruolo = 'titolare'
    limit 1;
$$;

create or replace function public.crea_invito()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    v_impresa uuid := public.mia_impresa_titolare();
    v_codice  text;
begin
    if v_impresa is null then
        raise exception 'Solo il titolare può creare un codice invito';
    end if;
    if (select count(*) from public.inviti
        where impresa_id = v_impresa and usato_da is null and scade_il > now()) >= 20 then
        raise exception 'Troppi codici ancora attivi: annullane qualcuno';
    end if;
    loop
        v_codice := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
        exit when not exists (select 1 from public.inviti where codice = v_codice);
    end loop;
    insert into public.inviti (codice, impresa_id, creato_da)
    values (v_codice, v_impresa, auth.uid());
    return v_codice;
end;
$$;

create or replace function public.inviti_attivi()
returns table (codice text, scade_il timestamptz)
language sql
stable
security definer
set search_path = public
as $$
    select i.codice, i.scade_il from public.inviti i
    where i.impresa_id = public.mia_impresa_titolare()
      and i.usato_da is null
      and i.scade_il > now()
    order by i.creato_il desc;
$$;

create or replace function public.annulla_invito(p_codice text)
returns void
language sql
security definer
set search_path = public
as $$
    delete from public.inviti
    where codice = upper(trim(p_codice))
      and impresa_id = public.mia_impresa_titolare()
      and usato_da is null;
$$;

create or replace function public.membri_impresa()
returns table (user_id uuid, email text, ruolo text, aggiunto_il timestamptz)
language sql
stable
security definer
set search_path = public
as $$
    select m.user_id, u.email::text, m.ruolo, m.aggiunto_il
    from public.membri m
    join auth.users u on u.id = m.user_id
    where m.impresa_id = public.mia_impresa_titolare()
    order by m.ruolo desc, m.aggiunto_il;
$$;

create or replace function public.rimuovi_membro(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_impresa uuid := public.mia_impresa_titolare();
begin
    if v_impresa is null then
        raise exception 'Solo il titolare può togliere un accesso';
    end if;
    delete from public.membri
    where impresa_id = v_impresa and user_id = p_user and ruolo = 'capocantiere';
end;
$$;


-- 6. Controllo del codice prima della registrazione ------------------------
-- Restituisce il nome dell'impresa se il codice è valido, altrimenti null.
create or replace function public.verifica_invito(p_codice text)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select imp.nome
    from public.inviti i
    join public.imprese imp on imp.id = i.impresa_id
    where i.codice = upper(trim(p_codice))
      and i.usato_da is null
      and i.scade_il > now();
$$;


-- 7. Registrazione: con un codice valido si entra nell'impresa come capocantiere,
--    senza codice nasce una nuova impresa (come prima).
create or replace function public.nuovo_utente()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    nuova_impresa uuid;
    v_codice      text := upper(trim(coalesce(new.raw_user_meta_data ->> 'codice_invito', '')));
    v_invito      public.inviti%rowtype;
begin
    if v_codice <> '' then
        select * into v_invito from public.inviti
        where codice = v_codice and usato_da is null and scade_il > now()
        for update;
        if not found then
            raise exception 'Codice invito non valido o scaduto';
        end if;

        insert into public.membri (impresa_id, user_id, ruolo)
        values (v_invito.impresa_id, new.id, v_invito.ruolo);

        update public.inviti set usato_da = new.id, usato_il = now()
        where codice = v_codice;

        return new;
    end if;

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


-- 8. Funzioni per il capocantiere -----------------------------------------

-- Solo ciò che serve per segnare le presenze: nomi degli operai, cantieri aperti
-- e le giornate delle ultime 2 settimane (senza importi).
create or replace function public.capo_dati()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_impresa uuid;
    v_dati    jsonb;
    v_nome    text;
begin
    select m.impresa_id into v_impresa from public.membri m
    where m.user_id = auth.uid() and m.ruolo = 'capocantiere'
    limit 1;
    if v_impresa is null then
        raise exception 'Accesso non consentito';
    end if;

    select d.dati into v_dati from public.dati_impresa d where d.impresa_id = v_impresa;
    select i.nome into v_nome from public.imprese i where i.id = v_impresa;

    return jsonb_build_object(
        'impresa', v_nome,
        'operai', coalesce((
            select jsonb_agg(jsonb_build_object('id', o -> 'id', 'nome', o -> 'nome', 'ruolo', o -> 'ruolo'))
            from jsonb_array_elements(coalesce(v_dati -> 'operai', '[]'::jsonb)) o
        ), '[]'::jsonb),
        'cantieri', coalesce((
            select jsonb_agg(jsonb_build_object('id', c -> 'id', 'nome', c -> 'nome'))
            from jsonb_array_elements(coalesce(v_dati -> 'cantieri', '[]'::jsonb)) c
            where coalesce(c ->> 'stato', 'aperto') <> 'chiuso'
        ), '[]'::jsonb),
        'presenze', coalesce((
            select jsonb_agg(jsonb_build_object(
                'data', p -> 'data', 'operaioId', p -> 'operaioId', 'cantiereId', p -> 'cantiereId',
                'giorni', p -> 'giorni', 'oreExtra', p -> 'oreExtra'))
            from jsonb_array_elements(coalesce(v_dati -> 'presenze', '[]'::jsonb)) p
            where (p ->> 'data') >= to_char(current_date - 14, 'YYYY-MM-DD')
        ), '[]'::jsonb)
    );
end;
$$;

-- Aggiunge le giornate della squadra. Il costo lo calcola il database con la paga
-- dell'operaio e la maggiorazione delle ore extra, così il capocantiere non le vede.
create or replace function public.capo_salva_presenze(p_data date, p_cantiere numeric, p_righe jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_impresa uuid;
    v_dati    jsonb;
    v_magg    numeric;
    v_nuove   jsonb := '[]'::jsonb;
    v_riga    jsonb;
    v_op      jsonb;
    v_paga    numeric;
    v_giorni  numeric;
    v_extra   numeric;
    v_base    bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
    v_n       integer := 0;
begin
    select m.impresa_id into v_impresa from public.membri m
    where m.user_id = auth.uid() and m.ruolo = 'capocantiere'
    limit 1;
    if v_impresa is null then
        raise exception 'Accesso non consentito';
    end if;
    if p_data is null or p_data > current_date + 1 or p_data < current_date - 60 then
        raise exception 'Data non valida';
    end if;
    if p_righe is null or jsonb_typeof(p_righe) <> 'array'
       or jsonb_array_length(p_righe) = 0 or jsonb_array_length(p_righe) > 100 then
        raise exception 'Nessun operaio indicato';
    end if;

    -- Blocca la riga: nessun altro salvataggio in contemporanea
    select d.dati into v_dati from public.dati_impresa d where d.impresa_id = v_impresa for update;

    if not exists (
        select 1 from jsonb_array_elements(coalesce(v_dati -> 'cantieri', '[]'::jsonb)) c
        where (c ->> 'id')::numeric = p_cantiere
          and coalesce(c ->> 'stato', 'aperto') <> 'chiuso'
    ) then
        raise exception 'Cantiere non trovato o chiuso';
    end if;

    v_magg := coalesce((v_dati -> 'impostazioni' ->> 'maggiorazioneExtra')::numeric, 0);

    for v_riga in select * from jsonb_array_elements(p_righe) loop
        v_op := null;
        select o into v_op
        from jsonb_array_elements(coalesce(v_dati -> 'operai', '[]'::jsonb)) o
        where (o ->> 'id')::numeric = (v_riga ->> 'operaioId')::numeric
        limit 1;
        if v_op is null then
            raise exception 'Operaio non trovato';
        end if;

        v_giorni := coalesce((v_riga ->> 'giorni')::numeric, 0);
        v_extra  := coalesce((v_riga ->> 'oreExtra')::numeric, 0);
        if v_giorni < 0 or v_giorni > 1 or v_extra < 0 or v_extra > 16 or (v_giorni = 0 and v_extra = 0) then
            raise exception 'Giornate o ore extra non valide';
        end if;

        v_paga := coalesce((v_op ->> 'pagaGiornaliera')::numeric, 0);
        v_n := v_n + 1;
        v_nuove := v_nuove || jsonb_build_array(jsonb_build_object(
            'id',          v_base + v_n,
            'data',        to_char(p_data, 'YYYY-MM-DD'),
            'cantiereId',  p_cantiere,
            'operaioId',   v_op -> 'id',
            'giorni',      v_giorni,
            'oreExtra',    v_extra,
            'costoTotale', round(v_giorni * v_paga + v_extra * v_paga / 8 * (1 + v_magg / 100), 2),
            'note',        'Segnato dal capocantiere'
        ));
    end loop;

    update public.dati_impresa
    set dati = jsonb_set(v_dati, '{presenze}', v_nuove || coalesce(v_dati -> 'presenze', '[]'::jsonb)),
        versione = versione + 1,
        aggiornato_il = now()
    where impresa_id = v_impresa;

    return v_n;
end;
$$;


-- 9. Chi può usare le funzioni ---------------------------------------------
revoke execute on function public.is_titolare(uuid)                         from public, anon;
revoke execute on function public.mia_impresa_titolare()                    from public, anon;
revoke execute on function public.crea_invito()                             from public, anon;
revoke execute on function public.inviti_attivi()                           from public, anon;
revoke execute on function public.annulla_invito(text)                      from public, anon;
revoke execute on function public.membri_impresa()                          from public, anon;
revoke execute on function public.rimuovi_membro(uuid)                      from public, anon;
revoke execute on function public.capo_dati()                               from public, anon;
revoke execute on function public.capo_salva_presenze(date, numeric, jsonb) from public, anon;

grant execute on function public.is_titolare(uuid)                         to authenticated;
grant execute on function public.mia_impresa_titolare()                    to authenticated;
grant execute on function public.crea_invito()                             to authenticated;
grant execute on function public.inviti_attivi()                           to authenticated;
grant execute on function public.annulla_invito(text)                      to authenticated;
grant execute on function public.membri_impresa()                          to authenticated;
grant execute on function public.rimuovi_membro(uuid)                      to authenticated;
grant execute on function public.capo_dati()                               to authenticated;
grant execute on function public.capo_salva_presenze(date, numeric, jsonb) to authenticated;

-- Il controllo del codice serve anche prima del login (durante la registrazione)
grant execute on function public.verifica_invito(text) to anon, authenticated;
