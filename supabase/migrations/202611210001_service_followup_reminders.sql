-- Recordatorios de seguimiento por correo para servicios firmados.
-- Se crean solo al completar las firmas del técnico y del cliente; los servicios
-- históricos no generan correos retroactivos.

create table if not exists public.service_followup_reminders (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services(id) on delete cascade,
  reminder_kind text not null check (reminder_kind in ('15_days', '1_month')),
  due_date date not null,
  status text not null default 'pending' check (status in ('pending', 'processing', 'sent', 'failed', 'cancelled')),
  attempts integer not null default 0,
  locked_at timestamptz,
  sent_at timestamptz,
  resend_email_id text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (service_id, reminder_kind)
);

create index if not exists service_followup_reminders_due_idx
  on public.service_followup_reminders (due_date, status);

alter table public.service_followup_reminders enable row level security;
revoke all on public.service_followup_reminders from anon, authenticated;
alter table public.service_followup_reminders drop constraint if exists service_followup_reminders_status_check;
alter table public.service_followup_reminders add constraint service_followup_reminders_status_check check (status in ('pending', 'processing', 'sent', 'failed', 'cancelled'));

create or replace function public.schedule_service_followup_reminders()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  was_eligible boolean := false;
  is_eligible boolean;
begin
  is_eligible := new.certificate_signed_at is not null
    and nullif(trim(coalesce(new.technician_signature, '')), '') is not null
    and nullif(trim(coalesce(new.client_signature, '')), '') is not null;

  if tg_op = 'UPDATE' then
    was_eligible := old.certificate_signed_at is not null
      and nullif(trim(coalesce(old.technician_signature, '')), '') is not null
      and nullif(trim(coalesce(old.client_signature, '')), '') is not null;
  end if;

  if tg_op = 'INSERT' and is_eligible then
    update public.service_followup_reminders r set status = 'cancelled', updated_at = now()
      from public.services prior
     where r.service_id = prior.id and prior.client_id = new.client_id
       and prior.id <> new.id and r.status = 'pending';
    insert into public.service_followup_reminders (service_id, reminder_kind, due_date)
    values
      (new.id, '15_days', new.service_date + 15),
      (new.id, '1_month', (new.service_date + interval '1 month')::date)
    on conflict (service_id, reminder_kind) do nothing;
  elsif tg_op = 'UPDATE' and is_eligible then
    if not was_eligible then
      update public.service_followup_reminders r set status = 'cancelled', updated_at = now()
        from public.services prior
       where r.service_id = prior.id and prior.client_id = new.client_id
         and prior.id <> new.id and r.status = 'pending';
      insert into public.service_followup_reminders (service_id, reminder_kind, due_date)
      values
        (new.id, '15_days', new.service_date + 15),
        (new.id, '1_month', (new.service_date + interval '1 month')::date)
      on conflict (service_id, reminder_kind) do nothing;
    elsif new.service_date is distinct from old.service_date then
      update public.service_followup_reminders
         set due_date = case reminder_kind
               when '15_days' then new.service_date + 15
               when '1_month' then (new.service_date + interval '1 month')::date
             end,
             updated_at = now()
       where service_id = new.id and status = 'pending';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists services_schedule_followup_reminders on public.services;
create trigger services_schedule_followup_reminders
after insert
on public.services
for each row execute function public.schedule_service_followup_reminders();
drop trigger if exists services_reschedule_followup_reminders on public.services;
create trigger services_reschedule_followup_reminders
after update of certificate_signed_at, technician_signature, client_signature, service_date
on public.services
for each row execute function public.schedule_service_followup_reminders();

create or replace function public.claim_service_followup_reminders(p_token text, p_limit integer default 50)
returns table (
  id uuid,
  service_id uuid,
  reminder_kind text,
  due_date date,
  attempts integer
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_expected_token text;
begin
  select decrypted_secret into v_expected_token
    from vault.decrypted_secrets
   where name = 'rokelux_reminders_secret'
   limit 1;
  if v_expected_token is null or p_token is distinct from v_expected_token then
    raise exception 'Unauthorized scheduled reminder request' using errcode = '42501';
  end if;

  return query
  with candidates as (
    select r.id
      from public.service_followup_reminders r
     where r.due_date <= (now() at time zone 'America/Guayaquil')::date
       and r.attempts < 5
       and (r.status = 'pending' or (r.status = 'processing' and r.locked_at < now() - interval '20 minutes'))
     order by r.due_date, r.created_at
     for update skip locked
     limit least(greatest(coalesce(p_limit, 50), 1), 100)
  )
  update public.service_followup_reminders r
     set status = 'processing', attempts = r.attempts + 1,
         locked_at = now(), updated_at = now(), last_error = null
    from candidates c
   where r.id = c.id
  returning r.id, r.service_id, r.reminder_kind, r.due_date, r.attempts;
end;
$$;

create or replace function public.finish_service_followup_reminder(
  p_id uuid,
  p_sent boolean,
  p_email_id text default null,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.service_followup_reminders
     set status = case when p_sent then 'sent' when attempts >= 5 or coalesce(p_error, '') like 'FINAL:%' then 'failed' else 'pending' end,
         sent_at = case when p_sent then now() else sent_at end,
         resend_email_id = case when p_sent then p_email_id else resend_email_id end,
         last_error = case when p_sent then null else left(coalesce(p_error, 'No se pudo enviar'), 1000) end,
         locked_at = null,
         updated_at = now()
   where id = p_id and status = 'processing';
end;
$$;

revoke all on function public.claim_service_followup_reminders(text, integer) from public, anon, authenticated;
revoke all on function public.finish_service_followup_reminder(uuid, boolean, text, text) from public, anon, authenticated;
grant execute on function public.claim_service_followup_reminders(text, integer) to service_role;
grant execute on function public.finish_service_followup_reminder(uuid, boolean, text, text) to service_role;

-- La clave de 256 bits se genera y permanece dentro del Vault del proyecto.
-- El endpoint no acepta solicitudes de terceros sin esa clave.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'rokelux_reminders_secret') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
      'rokelux_reminders_secret',
      'Clave interna para autorizar el cron de recordatorios ROKELUX'
    );
  end if;
end;
$$;

create or replace function public.invoke_service_followup_reminders()
returns bigint
language plpgsql
security definer
set search_path = public, vault, extensions, pg_temp
as $$
declare
  v_url text;
  v_secret text;
  v_request_id bigint;
begin
  v_url := 'https://xrtiwmvvzewlglbmlufm.supabase.co/functions/v1/enviar-recordatorios';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'rokelux_reminders_secret' limit 1;
  if v_secret is null then
    raise exception 'Faltan secretos de programación de recordatorios en Vault';
  end if;
  select net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'sb_publishable_8vYzQJ29K4TmG_Z2ViR1zQ_-GTg8t9F',
      'Authorization', 'Bearer sb_publishable_8vYzQJ29K4TmG_Z2ViR1zQ_-GTg8t9F',
      'x-rokelux-cron-secret', v_secret
    ),
    body := jsonb_build_object('source', 'daily-schedule')
  ) into v_request_id;
  return v_request_id;
end;
$$;
revoke all on function public.invoke_service_followup_reminders() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'rokelux-service-followup-reminders') then
    perform cron.unschedule('rokelux-service-followup-reminders');
  end if;
  perform cron.schedule(
    'rokelux-service-followup-reminders',
    '15 13 * * *',
    'select public.invoke_service_followup_reminders();'
  );
end;
$$;

