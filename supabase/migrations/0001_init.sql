-- =====================================================================
-- Swipey 0001_init.sql
-- Run once via Supabase dashboard SQL editor.
-- All timestamps stored UTC (timestamptz). America/New_York is applied
-- at read time and inside RPCs that need wall-clock semantics.
-- =====================================================================

-- ---------------------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------------------

create type drop_status as enum (
  'open',
  'expired',
  'completed',
  'cancelled'
);

create type claim_status as enum (
  'pending',
  'donor_confirmed',
  'eater_confirmed',
  'completed',
  'expired',
  'cancelled'
);

-- ---------------------------------------------------------------------
-- TABLES
-- ---------------------------------------------------------------------

create table public.profiles (
  id                    uuid        primary key references auth.users(id) on delete cascade,
  email                 text        not null check (email ~* '@upenn\.edu$'),
  first_name            text,
  phone                 text,
  muted_until           timestamptz,
  priority_window_start time,
  priority_window_end   time,
  priority_set_date     date,
  priority_set_at       timestamptz,
  donor_count           int         not null default 0,
  created_at            timestamptz not null default now()
);

create table public.dining_locations (
  id          uuid    primary key default gen_random_uuid(),
  name        text    not null unique,
  is_active   boolean not null default true,
  sort_order  int     not null default 0
);

create table public.drops (
  id                 uuid        primary key default gen_random_uuid(),
  donor_id           uuid        not null references public.profiles(id) on delete cascade,
  location_id        uuid        not null references public.dining_locations(id),
  total_slots        int         not null check (total_slots between 1 and 10),
  slots_remaining    int         not null check (slots_remaining >= 0),
  status             drop_status not null default 'open',
  general_notify_at  timestamptz not null,
  general_notified   boolean     not null default false,
  created_at         timestamptz not null default now(),
  expires_at         timestamptz not null
);

create table public.claims (
  id                  uuid         primary key default gen_random_uuid(),
  drop_id             uuid         not null references public.drops(id) on delete cascade,
  eater_id            uuid         not null references public.profiles(id) on delete cascade,
  status              claim_status not null default 'pending',
  was_priority        boolean      not null default false,
  claimed_at          timestamptz  not null default now(),
  claim_expires_at    timestamptz  not null,
  donor_confirmed_at  timestamptz,
  eater_confirmed_at  timestamptz,
  completed_at        timestamptz,
  unique (drop_id, eater_id)
);

create table public.push_subscriptions (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references public.profiles(id) on delete cascade,
  endpoint    text        not null unique,
  p256dh      text        not null,
  auth        text        not null,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- INDEXES
-- ---------------------------------------------------------------------

create index drops_status_created_at_idx
  on public.drops (status, created_at desc);

create index claims_eater_status_idx
  on public.claims (eater_id, status);

create index claims_drop_status_idx
  on public.claims (drop_id, status);

create index push_subscriptions_user_idx
  on public.push_subscriptions (user_id);

create index drops_general_notify_pending_idx
  on public.drops (general_notify_at, general_notified)
  where status = 'open';

-- ---------------------------------------------------------------------
-- PUBLIC PROFILES VIEW
-- Exposes the columns any authenticated user can see about anyone else
-- (id, first_name, donor_count). Owner is migration runner (postgres),
-- which has BYPASSRLS, so the view bypasses the row-restrictive policy
-- on profiles below.
-- ---------------------------------------------------------------------

create view public.public_profiles as
  select id, first_name, donor_count
  from public.profiles;

-- ---------------------------------------------------------------------
-- AUTH TRIGGER: every new auth.users row gets a matching profile.
-- The Penn-email check on profiles.email rolls back the auth insert
-- if a non-Penn email somehow makes it past the app layer.
-- ---------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- RPC: claim_drop
-- Atomic. Locks the drop row, checks open + slots + no active claim,
-- determines priority, decrements slots, inserts claim. 10-min redeem
-- timer set on the new claim row.
-- ---------------------------------------------------------------------

create or replace function public.claim_drop(
  p_drop_id uuid,
  p_user_id uuid
)
returns public.claims
language plpgsql
security definer
set search_path = public
as $$
declare
  v_drop          public.drops%rowtype;
  v_user          public.profiles%rowtype;
  v_now           timestamptz := now();
  v_local_today   date;
  v_window_start  timestamptz;
  v_window_end    timestamptz;
  v_was_priority  boolean := false;
  v_new_claim     public.claims%rowtype;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'unauthorized';
  end if;

  select * into v_drop from public.drops where id = p_drop_id for update;
  if not found then
    raise exception 'drop not found';
  end if;

  if v_drop.status <> 'open' then
    raise exception 'drop is not open';
  end if;

  if v_drop.expires_at <= v_now then
    raise exception 'drop has expired';
  end if;

  if v_drop.slots_remaining <= 0 then
    raise exception 'no slots remaining';
  end if;

  if exists (
    select 1 from public.claims
    where eater_id = p_user_id
      and status in ('pending', 'donor_confirmed', 'eater_confirmed')
  ) then
    raise exception 'user already has an active claim';
  end if;

  -- priority: today's window AND drop younger than 5 min AND general not yet notified
  select * into v_user from public.profiles where id = p_user_id;
  v_local_today := (v_now at time zone 'America/New_York')::date;

  if v_user.priority_set_date = v_local_today
     and v_user.priority_window_start is not null
     and v_user.priority_window_end is not null then

    v_window_start := (v_user.priority_set_date::timestamp + v_user.priority_window_start)
                      at time zone 'America/New_York';
    v_window_end   := (v_user.priority_set_date::timestamp + v_user.priority_window_end)
                      at time zone 'America/New_York';

    if v_now between v_window_start and v_window_end
       and v_drop.created_at > v_now - interval '5 minutes'
       and v_drop.general_notified = false then
      v_was_priority := true;
    end if;
  end if;

  update public.drops
    set slots_remaining = slots_remaining - 1
    where id = p_drop_id;

  insert into public.claims (drop_id, eater_id, was_priority, claim_expires_at)
    values (p_drop_id, p_user_id, v_was_priority, v_now + interval '10 minutes')
    returning * into v_new_claim;

  return v_new_claim;
end;
$$;

revoke all on function public.claim_drop(uuid, uuid) from public;
grant execute on function public.claim_drop(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: confirm_claim
-- Two-way confirmation. Either party calls with their role; once both
-- have confirmed, status -> 'completed' and the donor's donor_count
-- bumps.
-- ---------------------------------------------------------------------

create or replace function public.confirm_claim(
  p_claim_id uuid,
  p_user_id  uuid,
  p_role     text
)
returns public.claims
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim public.claims%rowtype;
  v_drop  public.drops%rowtype;
  v_now   timestamptz := now();
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'unauthorized';
  end if;

  if p_role not in ('donor', 'eater') then
    raise exception 'invalid role: must be donor or eater';
  end if;

  select * into v_claim from public.claims where id = p_claim_id for update;
  if not found then
    raise exception 'claim not found';
  end if;

  select * into v_drop from public.drops where id = v_claim.drop_id;

  if p_role = 'donor' and v_drop.donor_id <> p_user_id then
    raise exception 'unauthorized: not the donor of this drop';
  end if;

  if p_role = 'eater' and v_claim.eater_id <> p_user_id then
    raise exception 'unauthorized: not the eater on this claim';
  end if;

  if v_claim.status not in ('pending', 'donor_confirmed', 'eater_confirmed') then
    raise exception 'claim is not in a confirmable state';
  end if;

  if p_role = 'donor' then
    if v_claim.donor_confirmed_at is null then
      v_claim.donor_confirmed_at := v_now;
    end if;
    if v_claim.eater_confirmed_at is not null then
      v_claim.status       := 'completed';
      v_claim.completed_at := v_now;
    elsif v_claim.status = 'pending' then
      v_claim.status := 'donor_confirmed';
    end if;
  else
    if v_claim.eater_confirmed_at is null then
      v_claim.eater_confirmed_at := v_now;
    end if;
    if v_claim.donor_confirmed_at is not null then
      v_claim.status       := 'completed';
      v_claim.completed_at := v_now;
    elsif v_claim.status = 'pending' then
      v_claim.status := 'eater_confirmed';
    end if;
  end if;

  update public.claims
    set donor_confirmed_at = v_claim.donor_confirmed_at,
        eater_confirmed_at = v_claim.eater_confirmed_at,
        status             = v_claim.status,
        completed_at       = v_claim.completed_at
    where id = p_claim_id;

  if v_claim.status = 'completed' then
    update public.profiles
      set donor_count = donor_count + 1
      where id = v_drop.donor_id;
  end if;

  return v_claim;
end;
$$;

revoke all on function public.confirm_claim(uuid, uuid, text) from public;
grant execute on function public.confirm_claim(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: cancel_claim
-- Either party can cancel before completion. Slot is returned to the
-- drop (only if the drop itself is still 'open').
-- ---------------------------------------------------------------------

create or replace function public.cancel_claim(
  p_claim_id uuid,
  p_user_id  uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim public.claims%rowtype;
  v_drop  public.drops%rowtype;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'unauthorized';
  end if;

  select * into v_claim from public.claims where id = p_claim_id for update;
  if not found then
    raise exception 'claim not found';
  end if;

  select * into v_drop from public.drops where id = v_claim.drop_id for update;

  if v_claim.eater_id <> p_user_id and v_drop.donor_id <> p_user_id then
    raise exception 'unauthorized: not a party to this claim';
  end if;

  if v_claim.status in ('completed', 'cancelled', 'expired') then
    raise exception 'claim cannot be cancelled in its current state';
  end if;

  update public.claims set status = 'cancelled' where id = p_claim_id;

  if v_drop.status = 'open' then
    update public.drops
      set slots_remaining = slots_remaining + 1
      where id = v_drop.id;
  end if;
end;
$$;

revoke all on function public.cancel_claim(uuid, uuid) from public;
grant execute on function public.cancel_claim(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: set_priority_window
-- Exactly 2 contiguous hours, no midnight cross. Locked once set today.
-- ---------------------------------------------------------------------

create or replace function public.set_priority_window(
  p_user_id uuid,
  p_start   time,
  p_end     time
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user        public.profiles%rowtype;
  v_now         timestamptz := now();
  v_local_today date;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'unauthorized';
  end if;

  if p_end <= p_start or (p_end - p_start) <> interval '2 hours' then
    raise exception 'priority window must be exactly 2 hours within a single day';
  end if;

  v_local_today := (v_now at time zone 'America/New_York')::date;

  select * into v_user from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'profile not found';
  end if;

  if v_user.priority_set_date = v_local_today then
    raise exception 'priority window already set for today';
  end if;

  update public.profiles
    set priority_window_start = p_start,
        priority_window_end   = p_end,
        priority_set_date     = v_local_today,
        priority_set_at       = v_now
    where id = p_user_id
    returning * into v_user;

  return v_user;
end;
$$;

revoke all on function public.set_priority_window(uuid, time, time) from public;
grant execute on function public.set_priority_window(uuid, time, time) to authenticated;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------

alter table public.profiles           enable row level security;
alter table public.dining_locations   enable row level security;
alter table public.drops              enable row level security;
alter table public.claims             enable row level security;
alter table public.push_subscriptions enable row level security;

-- profiles: see/update only your own row. Inserts come from the auth
-- trigger (security definer); no client INSERT or DELETE policy.
create policy profiles_select_own
  on public.profiles for select to authenticated
  using (id = auth.uid());

create policy profiles_update_own
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

grant select on public.public_profiles to authenticated;

-- dining_locations: read-only for everyone authenticated; only active rows.
create policy dining_locations_select_active
  on public.dining_locations for select to authenticated
  using (is_active = true);

-- drops: marketplace is public to authenticated users. Only the donor
-- can insert their own drop. Updates/deletes only via RPC (no policy).
create policy drops_select_all
  on public.drops for select to authenticated
  using (true);

create policy drops_insert_self
  on public.drops for insert to authenticated
  with check (donor_id = auth.uid());

-- claims: see your own + claims on drops you own. Insert/update only via RPC.
create policy claims_select_own_or_donor
  on public.claims for select to authenticated
  using (
    eater_id = auth.uid()
    or exists (
      select 1 from public.drops
      where drops.id = claims.drop_id
        and drops.donor_id = auth.uid()
    )
  );

-- push_subscriptions: full CRUD on your own rows only.
create policy push_subs_all_own
  on public.push_subscriptions for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- SEED DATA
-- ---------------------------------------------------------------------

insert into public.dining_locations (name, sort_order) values
  ('1920 Commons',   1),
  ('Hill House',     2),
  ('Houston Market', 3),
  ('Joe''s Cafe',    4),
  ('Accenture Cafe', 5),
  ('Pret',           6),
  ('Gourmet Grocer', 7),
  ('McClelland',     8),
  ('English House',  9),
  ('Falk at Hillel', 10),
  ('Cafe West',      11);
