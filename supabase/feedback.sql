-- =====================================================================
-- Cantierometro - Tabella dei suggerimenti e delle segnalazioni
-- Da eseguire UNA volta in Supabase > SQL Editor > New query > Run.
-- I messaggi si leggono in Table Editor > feedback.
-- =====================================================================

create table public.feedback (
    id          uuid primary key default gen_random_uuid(),
    creato_il   timestamptz not null default now(),
    user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
    impresa_id  uuid references public.imprese(id) on delete cascade,
    tipo        text not null check (tipo in ('suggerimento', 'problema', 'altro')),
    messaggio   text not null check (char_length(messaggio) between 1 and 2000),
    dispositivo text check (char_length(dispositivo) <= 300)
);

alter table public.feedback enable row level security;

-- Gli utenti possono solo INVIARE messaggi a nome proprio e della propria impresa.
-- Nessuno può leggerli dall'app: li leggi tu da Supabase.
create policy "feedback: invio i miei messaggi"
    on public.feedback for insert to authenticated
    with check (
        user_id = auth.uid()
        and (impresa_id is null or public.is_membro(impresa_id))
    );

revoke all on public.feedback from anon;
grant insert on public.feedback to authenticated;
