-- =====================================================================
-- Tally Grades: attendance and grades. Made by Toqa Hamdy.
-- Paste this whole file in Supabase > SQL Editor > New query, then Run.
-- Safe to run again: it updates the functions and keeps the data.
-- =====================================================================
create extension if not exists pgcrypto with schema extensions;
create schema if not exists tg;   -- data and helpers live here; this schema is not reachable from the internet

create table if not exists tg.staff (
  name text primary key, pin text unique, role text not null default 'TA',
  courses text[] not null default '{}', added timestamptz not null default now(),
  username text unique, pass_hash text, status text not null default 'active');
alter table tg.staff alter column pin drop not null;
alter table tg.staff add column if not exists username text unique;
alter table tg.staff add column if not exists pass_hash text;
alter table tg.staff add column if not exists status text not null default 'active';
create table if not exists tg.tokens (token text primary key, staff text not null, created timestamptz not null default now(), expires timestamptz not null);
create table if not exists tg.students (
  ord bigserial, course text not null, grp text not null, name text not null, sid text not null, ta text not null default '',
  primary key (course, grp, sid));
create table if not exists tg.sessions (
  id text primary key, ta text, course text not null, grp text not null, week int not null,
  opened timestamptz not null default now(), closes timestamptz not null, closed timestamptz,
  strict_mode boolean not null default false, guests boolean not null default true, secret text not null, code text not null);
alter table tg.sessions add column if not exists also text[] not null default '{}';   -- other groups checking in together with grp
create table if not exists tg.log (
  id bigserial primary key, ts timestamptz not null default now(), session text not null default '',
  course text not null, grp text not null, week int not null, sid text not null, name text not null,
  status text not null, method text not null, by_ta text not null default '', device text not null default '', note text not null default '');
create table if not exists tg.devices (device text primary key, sid text not null, name text not null, first_seen timestamptz not null default now());
create table if not exists tg.items (course text not null, key text not null, item text not null, max numeric not null, kind text not null default 'Grade', ord int not null default 0, primary key (course, key));
create table if not exists tg.grades (id bigserial primary key, ts timestamptz not null default now(), course text not null, grp text not null, sid text not null, name text not null, key text not null, score numeric, by_ta text not null default '');
create table if not exists tg.settings (key text primary key, value text);
create index if not exists log_cgw on tg.log (course, grp, week);
create index if not exists log_session on tg.log (session);
create index if not exists grades_cg on tg.grades (course, grp);
create index if not exists students_sid on tg.students (sid);
alter table tg.staff enable row level security;    alter table tg.students enable row level security;
alter table tg.sessions enable row level security; alter table tg.log enable row level security;
alter table tg.devices enable row level security;  alter table tg.items enable row level security;
alter table tg.grades enable row level security;   alter table tg.settings enable row level security;
alter table tg.tokens enable row level security;

-- ---------------------------------------------------------------- helpers
create or replace function tg.clean(x text) returns text language sql immutable as $$ select regexp_replace(btrim(coalesce(x, '')), '\s+', ' ', 'g') $$;
create or replace function tg.norm_id(x text) returns text language sql immutable as $$ select regexp_replace(regexp_replace(coalesce(x, ''), '\.0+$', ''), '\D', '', 'g') $$;
create or replace function tg.week_label(w int) returns text language sql immutable as $$ select case w when 7 then 'Week 7 (Midterm)' when 14 then 'Week 14 (Final)' else 'Week ' || w end $$;
create or replace function tg.hm(t timestamptz) returns text language sql stable as $$ select case when t is null then '' else to_char(t at time zone 'Africa/Cairo', 'FMHH12:MI AM') end $$;
create or replace function tg.ms(t timestamptz) returns bigint language sql immutable as $$ select coalesce(floor(extract(epoch from t) * 1000)::bigint, 0) $$;
create or replace function tg.res(kind text, title text, detail text, extra jsonb default '{}') returns jsonb language sql immutable as $$ select jsonb_build_object('kind', kind, 'title', title, 'detail', detail) || coalesce(extra, '{}') $$;
create or replace function tg.method_label(m text, by_ta text, note text) returns text language sql immutable as $$
  select case when m = 'Manual'
    then 'Manual' || coalesce(', in group ' || substring(note from '^Attended group (\S+)'), '') || case when by_ta <> '' then ' (' || by_ta || ')' else '' end
    else coalesce('Self, in group ' || substring(note from '^Attended group (\S+)'), m) end $$;

create or replace function tg.who(p_pin text) returns tg.staff language plpgsql as $$
declare r tg.staff;
begin
  select st.* into r from tg.tokens t join tg.staff st on st.name = t.staff
  where t.token = btrim(coalesce(p_pin, '')) and t.expires > now() and st.status = 'active';
  if not found then perform pg_sleep(0.5); raise exception 'Please log in again.'; end if;
  return r;
end $$;
create or replace function tg.new_token(n text) returns text language plpgsql as $$
declare t text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  delete from tg.tokens where expires < now();
  insert into tg.tokens (token, staff, expires) values (t, n, now() + interval '30 days');
  return t;
end $$;
create or replace function tg.good_login(p_user text, p_pass text, p_except text default null) returns text language plpgsql as $$
declare u text := lower(btrim(coalesce(p_user, '')));
begin
  if u !~ '^[a-z0-9._-]{3,30}$' then raise exception 'The username must be 3 to 30 letters, numbers, dots or dashes, with no spaces.'; end if;
  if length(coalesce(p_pass, '')) < 6 then raise exception 'The password must be at least 6 characters.'; end if;
  if exists (select 1 from tg.staff where lower(username) = u and name is distinct from p_except) then raise exception 'This username is taken. Choose another one.'; end if;
  return u;
end $$;
create or replace function tg.admin(p_pin text) returns tg.staff language plpgsql as $$
declare r tg.staff := tg.who(p_pin);
begin
  if r.role <> 'Admin' then raise exception 'Only the admin can do this.'; end if;
  return r;
end $$;
create or replace function tg.in_course(me tg.staff, c text) returns void language plpgsql as $$
begin
  if me.role = 'Admin' or cardinality(me.courses) = 0 or c = any(me.courses) then return; end if;
  raise exception 'This course is not one of your courses. Ask the admin.';
end $$;
create or replace function tg.group_ta(c text, g text) returns text language sql stable as $$
  select coalesce((select ta from tg.students where course = c and grp = g and ta <> '' order by ord limit 1), '') $$;
create or replace function tg.can_manage(me tg.staff, c text, g text) returns void language plpgsql as $$
declare t text;
begin
  if me.role = 'Admin' then return; end if;
  t := tg.group_ta(c, g);
  if t = me.name then return; end if;
  if t <> '' then raise exception 'This group belongs to %.', t; end if;
  raise exception 'This group has no TA yet. Press "This is my group" first.';
end $$;
create or replace function tg.courses_arr(j jsonb) returns text[] language sql immutable as $$
  select coalesce(array(select distinct tg.clean(x) from jsonb_array_elements_text(coalesce(j, '[]')) x where tg.clean(x) <> ''), '{}') $$;

create or replace function tg.term_start() returns date language sql stable as $$
  select case when value ~ '^\d{4}-\d{2}-\d{2}$' then value::date end from tg.settings where key = 'Term start' $$;
create or replace function tg.current_week() returns int language sql stable as $$
  select case when tg.term_start() is null then 0
    else least(14, greatest(1, floor(((now() at time zone 'Africa/Cairo')::date - tg.term_start()) / 7.0)::int + 1)) end $$;

-- ---------------------------------------------------------------- sessions and codes
-- every group of a session: its own group, then the groups that check in together with it
create or replace function tg.sgroups(s tg.sessions) returns text[] language sql immutable as $$ select array[s.grp] || coalesce(s.also, '{}') $$;
create or replace function tg.is_live(s tg.sessions) returns boolean language sql stable as $$ select s.id is not null and s.closed is null and now() <= s.closes $$;
create or replace function tg.finalize(p_id text) returns tg.sessions language plpgsql as $$
declare s tg.sessions;
begin
  update tg.sessions set closed = closes where id = p_id and closed is null and now() > closes;
  select * into s from tg.sessions where id = p_id;
  return s;
end $$;
create or replace function tg.slot() returns bigint language sql volatile as $$ select floor(extract(epoch from clock_timestamp()) / 20)::bigint $$;
create or replace function tg.code_for(secret text, slot bigint) returns text language plpgsql immutable as $$
declare b bytea := extensions.hmac(slot::text, secret, 'sha256'); n bigint := 0;
begin
  for i in 0..3 loop n := (n * 256 + get_byte(b, i)) % 1000000007; end loop;
  return lpad((n % 10000)::text, 4, '0');
end $$;
create or replace function tg.current_code(s tg.sessions) returns text language sql volatile as $$ select case when s.strict_mode then tg.code_for(s.secret, tg.slot()) else s.code end $$;
create or replace function tg.code_ok(s tg.sessions, code text) returns boolean language plpgsql volatile as $$
declare c text := regexp_replace(coalesce(code, ''), '\D', '', 'g'); now_slot bigint := tg.slot();
begin
  if not s.strict_mode then return c = s.code; end if;
  for i in 0..3 loop if tg.code_for(s.secret, now_slot - i) = c then return true; end if; end loop;
  return false;
end $$;

-- latest status of every student of a group in a week
create or replace function tg.latest(c text, g text, w int) returns table (sid text, status text, method text, by_ta text, note text, ts timestamptz) language sql stable as $$
  select distinct on (l.sid) l.sid, l.status, l.method, l.by_ta, l.note, l.ts from tg.log l
  where l.course = c and l.grp = g and l.week = w and l.status in ('P', 'A', 'E') order by l.sid, l.id desc $$;
create or replace function tg.flags(c text, g text, w int, lim int) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(f order by id desc), '[]') from (
    select id, tg.hm(ts) || ', ' || name || ': ' || note as f from tg.log
    where course = c and grp = g and week = w and (status = 'Blocked' or note <> '') order by id desc limit lim) x $$;
-- check-ins that belong to a session: its own students, plus guests from other groups
create or replace function tg.session_rows(s tg.sessions) returns setof tg.log language sql stable as $$
  select * from tg.log l where l.status = 'P' and (
    (l.method = 'Self' and l.course = s.course and l.grp = any(tg.sgroups(s)) and l.week = s.week) or (l.session = s.id and l.grp <> all(tg.sgroups(s)))) $$;

create or replace function tg.live(p_id text) returns jsonb language plpgsql as $$
declare s tg.sessions := tg.finalize(p_id); gs text[]; total int; cnt int; recent jsonb; guests jsonb;
begin
  if s.id is null then return jsonb_build_object('open', false); end if;
  if not tg.is_live(s) then
    return jsonb_build_object('open', false, 'id', s.id, 'course', s.course, 'group', s.grp, 'week', s.week, 'weekLabel', tg.week_label(s.week));
  end if;
  gs := tg.sgroups(s);
  select count(*) into total from tg.students where course = s.course and grp = any(gs);
  select count(*) into cnt from unnest(gs) as g(x) cross join lateral tg.latest(s.course, g.x, s.week) l
    join tg.students st on st.course = s.course and st.grp = g.x and st.sid = l.sid where l.status in ('P', 'E');
  select coalesce(jsonb_agg(label order by id desc), '[]') into recent from (
    select id, case when grp = s.grp then name when grp = any(gs) then name || ' (' || grp || ')' else name || ' (from group ' || grp || ')' end as label
    from tg.session_rows(s) order by id desc limit 6) x;
  select coalesce(jsonb_agg(name || ' (group ' || grp || ')' order by id), '[]') into guests from (
    select distinct on (sid) sid, name, grp, id from tg.log where session = s.id and grp <> all(gs) and status = 'P' order by sid, id) x;
  return jsonb_build_object('open', true, 'id', s.id, 'ta', s.ta, 'course', s.course, 'group', s.grp, 'groups', to_jsonb(gs), 'week', s.week, 'weekLabel', tg.week_label(s.week),
    'strict', s.strict_mode, 'code', tg.current_code(s), 'codeLeft', case when s.strict_mode then 20 - (floor(extract(epoch from clock_timestamp()))::bigint % 20) else 0 end,
    'secondsLeft', greatest(0, floor(extract(epoch from s.closes - now()))::int), 'count', cnt, 'total', total,
    'recent', recent, 'guests', jsonb_array_length(guests), 'guestNames', guests, 'flags', tg.flags(s.course, s.grp, s.week, 8));
end $$;

create or replace function tg.week_view(c text, g text, w int) returns jsonb language plpgsql as $$
declare held boolean; rows jsonb;
begin
  held := w = 1 or exists (select 1 from tg.sessions where course = c and (grp = g or g = any(also)) and week = w)
              or exists (select 1 from tg.log where course = c and grp = g and week = w and status in ('P', 'A', 'E'));
  select coalesce(jsonb_agg(jsonb_build_object('id', st.sid, 'name', st.name,
      'status', coalesce(l.status, case when w = 1 then 'P' when held then 'A' else '' end),
      'time', case when l.status = 'P' and l.method = 'Self' then tg.hm(l.ts) else '' end,
      'method', case when l.sid is null then case when w = 1 then 'Week 1' else '' end else tg.method_label(l.method, l.by_ta, l.note) end) order by st.ord), '[]')
    into rows from tg.students st left join tg.latest(c, g, w) l on l.sid = st.sid where st.course = c and st.grp = g;
  return jsonb_build_object('course', c, 'group', g, 'week', w, 'weekLabel', tg.week_label(w), 'held', held, 'rows', rows,
    'present', (select count(*) from jsonb_array_elements(rows) r where r->>'status' = 'P'),
    'absent', (select count(*) from jsonb_array_elements(rows) r where r->>'status' = 'A'),
    'excused', (select count(*) from jsonb_array_elements(rows) r where r->>'status' = 'E'),
    'flags', tg.flags(c, g, w, 20));
end $$;

-- every week of every chosen student: P, A, E, or '' when that week had no check-in
create or replace function tg.matrix(c text, g text default null, t text default null)
returns table (grp text, ta text, name text, sid text, ord bigint, weeks text[], p int, a int, e int, pct numeric) language sql stable as $$
  with st as materialized (select s.grp, s.ta, s.name, s.sid, s.ord from tg.students s where s.course = c and (g is null or s.grp = g) and (t is null or s.ta = t)),
  lat as materialized (select distinct on (l.grp, l.week, l.sid) l.grp, l.week, l.sid, l.status from tg.log l
                       where l.course = c and l.status in ('P', 'A', 'E') order by l.grp, l.week, l.sid, l.id desc),
  held as materialized (select distinct x.grp, x.week from (
                          select l.grp, l.week from tg.log l where l.course = c and l.status in ('P', 'A', 'E')
                          union all select x.g, s.week from tg.sessions s cross join unnest(tg.sgroups(s)) as x(g) where s.course = c) x),
  cells as materialized (
    select st.grp, st.ta, st.name, st.sid, st.ord, w.week,
           coalesce(lat.status, case when w.week = 1 then 'P' when h.week is not null then 'A' else '' end) as v
    from st cross join generate_series(1, 14) as w(week)
    left join lat on lat.grp = st.grp and lat.sid = st.sid and lat.week = w.week
    left join held h on h.grp = st.grp and h.week = w.week)
  select cl.grp, cl.ta, cl.name, cl.sid, cl.ord, array_agg(cl.v order by cl.week),
         count(*) filter (where cl.v = 'P')::int, count(*) filter (where cl.v = 'A')::int, count(*) filter (where cl.v = 'E')::int,
         case when count(*) filter (where cl.v in ('P', 'A', 'E')) = 0 then null
              else (count(*) filter (where cl.v in ('P', 'E')))::numeric / count(*) filter (where cl.v in ('P', 'A', 'E')) end
  from cells cl group by cl.grp, cl.ta, cl.name, cl.sid, cl.ord order by cl.ord $$;

create or replace function tg.items_json(c text) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'attendanceMax', coalesce((select max from tg.items where course = c and kind = 'Attendance'), 0),
    'items', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'item', item, 'max', max) order by ord) from tg.items where course = c and kind <> 'Attendance'), '[]')) $$;

create or replace function tg.grade_rows(c text, g text default null, t text default null) returns jsonb language sql stable as $$
  with it as (select key from tg.items where course = c and kind <> 'Attendance'),
  att as (select coalesce((select max from tg.items where course = c and kind = 'Attendance'), 0) as mx),
  m as materialized (select * from tg.matrix(c, g, t)),
  sc as materialized (select distinct on (gr.grp, gr.sid, gr.key) gr.grp, gr.sid, gr.key, gr.score from tg.grades gr
         where gr.course = c and gr.key in (select key from it) order by gr.grp, gr.sid, gr.key, gr.id desc),
  agg as materialized (select sc.grp, sc.sid, jsonb_object_agg(sc.key, sc.score) filter (where sc.score is not null) as obj, sum(sc.score) as total
          from sc group by sc.grp, sc.sid)
  select coalesce(jsonb_agg(jsonb_build_object(
      'group', m.grp, 'ta', m.ta, 'name', m.name, 'id', m.sid, 'weeks', to_jsonb(m.weeks), 'p', m.p, 'a', m.a, 'e', m.e,
      'pct', coalesce(to_jsonb(m.pct), '""'::jsonb),
      'attGrade', case when att.mx > 0 and m.pct is not null then to_jsonb(round(m.pct * att.mx, 2)) else '""'::jsonb end,
      'scores', coalesce(agg.obj, '{}'::jsonb),
      'total', round(coalesce(agg.total, 0) + case when att.mx > 0 and m.pct is not null then round(m.pct * att.mx, 2) else 0 end, 2),
      'section', (select jsonb_agg(case when v in ('P', 'E') then to_jsonb(1) when v = 'A' then to_jsonb(0) else '""'::jsonb end order by n)
                  from unnest(m.weeks) with ordinality as u(v, n) where n not in (7, 14))
    ) order by m.ord), '[]')
  from m cross join att left join agg on agg.grp = m.grp and agg.sid = m.sid $$;

create or replace function tg.dash(me tg.staff) returns jsonb language plpgsql as $$
declare groups jsonb; ts date := tg.term_start();
begin
  with g as (
    select st.course, st.grp, count(*)::int as cnt, coalesce((array_agg(st.ta order by st.ord) filter (where st.ta <> ''))[1], '') as ta,
           (count(*) filter (where exists (select 1 from tg.devices d where d.sid = st.sid)))::int as registered
    from tg.students st group by st.course, st.grp),
  lastw as (select distinct on (s.course, s.grp) s.course, s.grp, s.week, s.opened from tg.sessions s order by s.course, s.grp, s.week desc, s.opened desc),
  live as (select distinct on (s.course, x.g) s.course, x.g as grp, s.id, s.week from tg.sessions s cross join unnest(tg.sgroups(s)) as x(g)
           where s.closed is null and s.closes >= now() order by s.course, x.g, s.opened desc)
  select coalesce(jsonb_agg(jsonb_build_object('course', g.course, 'group', g.grp, 'ta', g.ta, 'count', g.cnt, 'registered', g.registered,
           'lastWeek', greatest(1, coalesce(lastw.week, 1)), 'lastOpened', tg.ms(lastw.opened), 'live', live.id, 'liveWeek', coalesce(live.week, 0))), '[]')
    into groups
  from g left join lastw on lastw.course = g.course and lastw.grp = g.grp left join live on live.course = g.course and live.grp = g.grp
  where me.role = 'Admin' or cardinality(me.courses) = 0 or g.course = any(me.courses);
  return jsonb_build_object(
    'me', jsonb_build_object('name', me.name, 'role', me.role, 'courses', to_jsonb(me.courses)),
    'groups', groups,
    'allCourses', case when me.role = 'Admin' then coalesce((select jsonb_agg(c order by c) from (select distinct course as c from tg.students) x), '[]') else '[]' end,
    'weeks', (select jsonb_agg(jsonb_build_array(n, tg.week_label(n) || case when ts is not null then ', ' || to_char(ts + (n - 1) * 7, 'FMDD Mon') else '' end) order by n) from generate_series(1, 14) n),
    'termStart', coalesce(to_char(ts, 'YYYY-MM-DD'), ''), 'currentWeek', tg.current_week(), 'url', '', 'sheetUrl', '',
    'staff', case when me.role = 'Admin' then (select jsonb_agg(jsonb_build_object('name', name, 'role', role, 'courses', to_jsonb(courses), 'username', coalesce(username, ''), 'status', status) order by role, status, name) from tg.staff) end);
end $$;

-- ---------------------------------------------------------------- student API
create or replace function public.student_info(p_session text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare s tg.sessions := tg.finalize(coalesce(p_session, ''));
begin
  if not tg.is_live(s) then return jsonb_build_object('open', false); end if;
  return jsonb_build_object('open', true, 'session', s.id, 'course', s.course, 'group', array_to_string(tg.sgroups(s), ' + '), 'weekLabel', tg.week_label(s.week), 'strict', s.strict_mode, 'ta', s.ta);
end $$;

create or replace function public.check_in(p jsonb) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare
  v_id text := tg.norm_id(p->>'id'); v_dev text := left(regexp_replace(coalesce(p->>'device', ''), '[^\w-]', '', 'g'), 80);
  s tg.sessions; st tg.students; guest boolean := false; prev timestamptz; owner_id text; own tg.devices; note text := ''; v_now timestamptz := now();
begin
  select * into s from tg.sessions where id = coalesce(p->>'session', '');
  if not tg.is_live(s) then return tg.res('err', 'Check-in is closed', 'Ask your TA to open it, then scan the QR code again.'); end if;
  if v_id = '' then return tg.res('err', 'Type your ID', 'Write your student ID, then press Check in.'); end if;
  select * into st from tg.students where course = s.course and grp = s.grp and sid = v_id;
  if not found then
    select * into st from tg.students where course = s.course and sid = v_id order by (grp = any(s.also)) desc, ord limit 1;
    if not found then return tg.res('err', 'ID not found', v_id || ' is not on any group list of ' || s.course || '. Check the number.'); end if;
    if not (st.grp = any(s.also)) then
      if not s.guests then return tg.res('err', st.name, 'You are in group ' || st.grp || '. This check-in is only for group ' || array_to_string(tg.sgroups(s), ' + ') || '.'); end if;
      guest := true;
    end if;
  end if;
  if not tg.code_ok(s, p->>'code') then
    return tg.res('err', 'Code expired', case when s.strict_mode then 'The code changes every 20 seconds. Type the code on the screen now.' else 'Type the code shown on the screen.' end, '{"needCode": true}');
  end if;
  perform pg_advisory_xact_lock(hashtext(s.id));
  select min(ts) into prev from tg.session_rows(s) r where r.sid = v_id;
  if prev is not null then return tg.res('warn', st.name, 'Already checked in at ' || tg.hm(prev) || '.', jsonb_build_object('done', true, 'id', v_id, 'name', st.name)); end if;
  if st.grp <> s.grp and exists (select 1 from tg.latest(s.course, st.grp, s.week) l where l.sid = v_id and l.status = 'P') then
    return tg.res('warn', st.name, 'You are already present for ' || tg.week_label(s.week) || ' in your group ' || st.grp || '.', jsonb_build_object('done', true, 'id', v_id, 'name', st.name));
  end if;
  if v_dev <> '' then
    select r.sid into owner_id from tg.session_rows(s) r where r.device = v_dev and r.sid <> v_id limit 1;
    if owner_id is not null then
      insert into tg.log (session, course, grp, week, sid, name, status, method, device, note)
        values (s.id, s.course, st.grp, s.week, v_id, st.name, 'Blocked', 'Self', v_dev, 'Phone already used this week for ' || coalesce((select name from tg.students where sid = owner_id limit 1), owner_id));
      return tg.res('err', 'Blocked', 'This phone already checked in another student this week. Each phone can check in one student only.');
    end if;
    if s.strict_mode then
      select * into own from tg.devices where device = v_dev;
      if found and own.sid <> v_id then
        insert into tg.log (session, course, grp, week, sid, name, status, method, device, note)
          values (s.id, s.course, st.grp, s.week, v_id, st.name, 'Blocked', 'Self', v_dev, 'Phone registered to ' || own.name);
        return tg.res('err', 'Blocked', 'This phone is registered to ' || own.name || '. Check in from your own phone.');
      end if;
      if not found then
        if exists (select 1 from tg.devices where sid = v_id) then note := 'Checked in from a new phone'; end if;
        insert into tg.devices (device, sid, name) values (v_dev, v_id, st.name);
      end if;
    end if;
  end if;
  if guest then note := concat_ws('; ', 'Attended group ' || s.grp || case when coalesce(s.ta, '') <> '' then ' with ' || s.ta else '' end, nullif(note, '')); end if;
  insert into tg.log (ts, session, course, grp, week, sid, name, status, method, device, note) values (v_now, s.id, s.course, st.grp, s.week, v_id, st.name, 'P', 'Self', v_dev, note);
  return tg.res('ok', st.name, case when guest
      then 'Present in group ' || s.grp || ' as a guest. It counts for your own group ' || st.grp || ', ' || tg.week_label(s.week) || '.'
      else s.course || ', ' || tg.week_label(s.week) || ', ' || tg.hm(v_now) end,
    jsonb_build_object('done', true, 'id', v_id, 'name', st.name));
end $$;

create or replace function public.register_phone(p jsonb) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare v_id text := tg.norm_id(p->>'id'); v_dev text := left(regexp_replace(coalesce(p->>'device', ''), '[^\w-]', '', 'g'), 80); st tg.students; own tg.devices; groups jsonb;
begin
  if v_id = '' then return tg.res('err', 'Type your ID', 'Write your student ID, then press Register.'); end if;
  select * into st from tg.students where sid = v_id order by ord limit 1;
  if not found then return tg.res('err', 'ID not found', v_id || ' is not on any group list. Check the number, or tell your TA.'); end if;
  select jsonb_agg(course || ', group ' || grp order by ord) into groups from tg.students where sid = v_id;
  if v_dev <> '' then
    perform pg_advisory_xact_lock(hashtext('dev:' || v_dev));
    select * into own from tg.devices where device = v_dev;
    if found and own.sid <> v_id then return tg.res('err', 'This phone is registered to ' || own.name, 'Each phone can be registered to one student only. Use your own phone.'); end if;
    if not found then insert into tg.devices (device, sid, name) values (v_dev, v_id, st.name); end if;
  end if;
  return tg.res('ok', st.name, '', jsonb_build_object('done', true, 'id', v_id, 'name', st.name, 'groups', groups));
end $$;

-- ---------------------------------------------------------------- staff API
create or replace function public.app_state() returns jsonb language sql security definer set search_path = tg, public, extensions as $$
  select jsonb_build_object('setup', exists (select 1 from tg.staff)) $$;

drop function if exists public.setup_admin(text, text);
drop function if exists public.login(text);
drop function if exists public.add_staff(text, text, text, jsonb);
create or replace function public.setup_admin(p_name text, p_user text, p_pass text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare n text := tg.clean(p_name); u text;
begin
  perform pg_advisory_xact_lock(1);
  if exists (select 1 from tg.staff) then raise exception 'Setup is already done. Log in.'; end if;
  if n = '' then raise exception 'Write your name.'; end if;
  u := tg.good_login(p_user, p_pass);
  insert into tg.staff (name, role, username, pass_hash, status) values (n, 'Admin', u, extensions.crypt(p_pass, extensions.gen_salt('bf')), 'active');
  return jsonb_build_object('token', tg.new_token(n), 'dash', tg.dash((select st from tg.staff st where name = n)));
end $$;
-- log in with username and password. Accounts made with a PIN before this version: username = the name, password = the PIN
create or replace function public.login(p_user text, p_pass text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare r tg.staff; u text := lower(btrim(coalesce(p_user, '')));
begin
  select * into r from tg.staff st where
    (lower(st.username) = u and st.pass_hash is not null and st.pass_hash = extensions.crypt(coalesce(p_pass, ''), st.pass_hash))
    or (st.pass_hash is null and lower(st.name) = u and st.pin is not null and st.pin = btrim(coalesce(p_pass, '')))
  limit 1;
  if not found then perform pg_sleep(1); raise exception 'Wrong username or password.'; end if;
  if r.status = 'pending' then raise exception 'Your account is waiting for the admin to confirm it.'; end if;
  return jsonb_build_object('token', tg.new_token(r.name), 'dash', tg.dash(r));
end $$;
create or replace function public.whoami(p_pin text) returns jsonb language sql security definer set search_path = tg, public, extensions as $$ select tg.dash(tg.who(p_pin)) $$;
create or replace function public.logout(p_pin text) returns jsonb language sql security definer set search_path = tg, public, extensions as $$
  delete from tg.tokens where token = btrim(coalesce(p_pin, '')) returning jsonb_build_object('ok', true) $$;
create or replace function public.course_list() returns jsonb language sql security definer set search_path = tg, public, extensions as $$
  select coalesce(jsonb_agg(c order by c), '[]') from (select distinct course as c from tg.students) x $$;
-- a TA asks for an account; the admin confirms it
create or replace function public.register_ta(p_name text, p_user text, p_pass text, p_courses jsonb default '[]') returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare n text := tg.clean(p_name); u text;
begin
  if n = '' then raise exception 'Write your full name.'; end if;
  if exists (select 1 from tg.staff where lower(name) = lower(n)) then raise exception 'This name already has an account. Log in, or ask the admin.'; end if;
  if (select count(*) from tg.staff where status = 'pending') >= 50 then raise exception 'Too many requests are waiting. Ask the admin.'; end if;
  u := tg.good_login(p_user, p_pass);
  insert into tg.staff (name, role, username, pass_hash, status, courses) values (n, 'TA', u, extensions.crypt(p_pass, extensions.gen_salt('bf')), 'pending', tg.courses_arr(p_courses));
  return jsonb_build_object('ok', true);
end $$;
create or replace function public.approve_ta(p_pin text, p_name text, p_courses jsonb) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.admin(p_pin);
begin
  update tg.staff set status = 'active', courses = tg.courses_arr(p_courses) where name = tg.clean(p_name) and role = 'TA';
  return tg.dash(me);
end $$;
create or replace function public.reject_ta(p_pin text, p_name text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.admin(p_pin);
begin
  delete from tg.staff where name = tg.clean(p_name) and status = 'pending';
  return tg.dash(me);
end $$;
-- the admin sets anyone's username and password (also their own)
create or replace function public.set_staff_login(p_pin text, p_name text, p_user text, p_pass text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.admin(p_pin); u text;
begin
  u := tg.good_login(p_user, p_pass, tg.clean(p_name));
  update tg.staff set username = u, pass_hash = extensions.crypt(p_pass, extensions.gen_salt('bf')), pin = null where name = tg.clean(p_name);
  delete from tg.tokens where staff = tg.clean(p_name) and token <> btrim(coalesce(p_pin, ''));
  return tg.dash(me);
end $$;

create or replace function public.add_group(p_pin text, p_course text, p_group text, p_ta text, p_list jsonb) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); c text := tg.clean(p_course); g text := tg.clean(p_group); t text; owner text; n int; d jsonb;
begin
  if c = '' or g = '' then raise exception 'Write the course and the group.'; end if;
  perform tg.in_course(me, c);
  owner := tg.group_ta(c, g);
  if owner <> '' and owner <> me.name and me.role <> 'Admin' then raise exception 'This group belongs to %.', owner; end if;
  t := case when owner <> '' then owner when me.role = 'Admin' then coalesce(nullif(tg.clean(p_ta), ''), me.name) else me.name end;
  if not exists (select 1 from jsonb_array_elements(coalesce(p_list, '[]')) x where tg.clean(x->>0) <> '' and tg.norm_id(x->>1) <> '') then
    raise exception 'Paste the students first: a name and an ID on each line.';
  end if;
  insert into tg.students (course, grp, name, sid, ta)
    select c, g, tg.clean(x->>0), tg.norm_id(x->>1), t from jsonb_array_elements(p_list) with ordinality as e(x, i)
    where tg.clean(x->>0) <> '' and tg.norm_id(x->>1) <> '' order by i
    on conflict do nothing;
  get diagnostics n = row_count;
  update tg.students set ta = t where course = c and grp = g and ta <> t and t <> '';
  d := tg.dash(me);
  return d || jsonb_build_object('added', n);
end $$;

create or replace function public.import_groups(p_pin text, p_course text, p_groups jsonb) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); c text := tg.clean(p_course); gr jsonb; g text; owner text; t text; n int; total int := 0; ng int := 0; skipped jsonb := '[]';
begin
  if c = '' then raise exception 'Write the course name.'; end if;
  perform tg.in_course(me, c);
  if jsonb_array_length(coalesce(p_groups, '[]')) = 0 then raise exception 'Choose at least one group.'; end if;
  for gr in select value from jsonb_array_elements(p_groups) loop
    g := tg.clean(gr->>'group'); if g = '' then continue; end if;
    owner := tg.group_ta(c, g);
    if me.role <> 'Admin' and owner <> '' and owner <> me.name then skipped := skipped || to_jsonb(g || ' (' || owner || ')'); continue; end if;
    t := case when owner <> '' then owner when me.role <> 'Admin' then me.name else coalesce(
           (select name from tg.staff where status = 'active' and lower(name) = lower(tg.clean(gr->>'ta')) limit 1),
           (select name from tg.staff where status = 'active' and tg.clean(gr->>'ta') <> '' and lower(split_part(name, ' ', 1)) = lower(split_part(tg.clean(gr->>'ta'), ' ', 1)) limit 1), '') end;
    insert into tg.students (course, grp, name, sid, ta)
      select c, g, tg.clean(x->>0), tg.norm_id(x->>1), t from jsonb_array_elements(coalesce(gr->'students', '[]')) with ordinality as e(x, i)
      where tg.clean(x->>0) <> '' and tg.norm_id(x->>1) <> '' order by i
      on conflict do nothing;
    get diagnostics n = row_count;
    total := total + n; ng := ng + 1;
    if t <> '' then update tg.students set ta = t where course = c and grp = g and ta <> t; end if;
  end loop;
  return tg.dash(me) || jsonb_build_object('imported', jsonb_build_object('groups', ng, 'students', total, 'skipped', skipped));
end $$;

create or replace function public.claim_group(p_pin text, p_course text, p_group text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); owner text;
begin
  perform tg.in_course(me, p_course);
  owner := tg.group_ta(p_course, p_group);
  if owner <> '' and owner <> me.name then raise exception 'This group belongs to %. Ask the admin to change it.', owner; end if;
  update tg.students set ta = me.name where course = p_course and grp = p_group;
  return tg.dash(me);
end $$;

create or replace function public.assign_group(p_pin text, p_course text, p_group text, p_ta text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.admin(p_pin); t text := tg.clean(p_ta);
begin
  if t <> '' and not exists (select 1 from tg.staff where name = t and status = 'active') then raise exception 'This TA was not found.'; end if;
  update tg.students set ta = t where course = p_course and grp = p_group;
  return tg.dash(me);
end $$;

create or replace function public.remove_group(p_pin text, p_course text, p_group text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.admin(p_pin);
begin
  delete from tg.students where course = p_course and grp = p_group;
  return tg.dash(me);
end $$;

create or replace function public.add_staff(p_pin text, p_name text, p_user text, p_pass text, p_courses jsonb default '[]') returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.admin(p_pin); n text := tg.clean(p_name); u text;
begin
  if n = '' then raise exception 'Write the TA name.'; end if;
  if exists (select 1 from tg.staff where lower(name) = lower(n)) then raise exception 'This name already exists.'; end if;
  u := tg.good_login(p_user, p_pass);
  insert into tg.staff (name, role, username, pass_hash, status, courses) values (n, 'TA', u, extensions.crypt(p_pass, extensions.gen_salt('bf')), 'active', tg.courses_arr(p_courses));
  return tg.dash(me);
end $$;

create or replace function public.set_staff_courses(p_pin text, p_name text, p_courses jsonb) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.admin(p_pin);
begin
  update tg.staff set courses = tg.courses_arr(p_courses) where name = tg.clean(p_name) and role <> 'Admin';
  return tg.dash(me);
end $$;

create or replace function public.remove_staff(p_pin text, p_name text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.admin(p_pin);
begin
  if tg.clean(p_name) = me.name then raise exception 'You cannot remove yourself.'; end if;
  delete from tg.staff where name = tg.clean(p_name);
  delete from tg.tokens where staff = tg.clean(p_name);
  update tg.students set ta = '' where ta = tg.clean(p_name);
  return tg.dash(me);
end $$;

create or replace function public.set_term_start(p_pin text, p_date text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.admin(p_pin); v text := left(coalesce(p_date, ''), 10);
begin
  if v <> '' and v !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Choose a date.'; end if;
  insert into tg.settings (key, value) values ('Term start', v) on conflict (key) do update set value = excluded.value;
  return tg.dash(me);
end $$;

-- ---------------------------------------------------------------- check-in sessions
drop function if exists public.open_session(text, text, text, int, int, boolean, boolean);
-- p_also: other groups of the course that check in together with p_group (one QR, one code)
create or replace function public.open_session(p_pin text, p_course text, p_group text, p_week int, p_minutes int default 15, p_strict boolean default false, p_guests boolean default true, p_also jsonb default '[]')
returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); v_id text := left(replace(gen_random_uuid()::text, '-', ''), 16); mins int := least(180, greatest(1, coalesce(p_minutes, 15)));
  v_also text[] := array(select distinct tg.clean(x) from jsonb_array_elements_text(coalesce(p_also, '[]')) x where tg.clean(x) not in ('', p_group)); x text;
begin
  perform tg.can_manage(me, p_course, p_group);
  if p_week is null or p_week < 1 or p_week > 14 then raise exception 'Choose a week from 1 to 14.'; end if;
  if not exists (select 1 from tg.students where course = p_course and grp = p_group) then raise exception 'No students found for %, group %.', p_course, p_group; end if;
  foreach x in array v_also loop
    if not exists (select 1 from tg.students where course = p_course and grp = x) then raise exception 'No students found for %, group %.', p_course, x; end if;
    perform tg.can_manage(me, p_course, x);
  end loop;
  perform pg_advisory_xact_lock(hashtext('open:' || p_course));
  update tg.sessions set closed = now() where course = p_course and closed is null and closes >= now() and (array[grp] || also) && (array[p_group] || v_also);
  insert into tg.sessions (id, ta, course, grp, also, week, opened, closes, strict_mode, guests, secret, code)
    values (v_id, me.name, p_course, p_group, v_also, p_week, now(), now() + make_interval(mins => mins), coalesce(p_strict, false), coalesce(p_guests, true),
            gen_random_uuid()::text, (1000 + floor(random() * 9000))::int::text);
  return tg.live(v_id);
end $$;

create or replace function tg.session_for(p_pin text, p_id text) returns tg.sessions language plpgsql as $$
declare me tg.staff := tg.who(p_pin); s tg.sessions;
begin
  select * into s from tg.sessions where id = p_id;
  if not found then raise exception 'Session not found.'; end if;
  perform tg.can_manage(me, s.course, s.grp);
  return s;
end $$;
create or replace function public.live_status(p_pin text, p_id text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
begin perform tg.session_for(p_pin, p_id); return tg.live(p_id); end $$;
create or replace function public.extend_session(p_pin text, p_id text, p_minutes int default 5) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare s tg.sessions := tg.session_for(p_pin, p_id);
begin
  if tg.is_live(s) then update tg.sessions set closes = greatest(closes, now()) + make_interval(mins => coalesce(p_minutes, 5)) where id = p_id; end if;
  return tg.live(p_id);
end $$;
create or replace function public.close_session(p_pin text, p_id text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare s tg.sessions := tg.session_for(p_pin, p_id);
begin
  update tg.sessions set closed = least(now(), closes) where id = p_id and closed is null;
  return tg.live(p_id);
end $$;
create or replace function public.random_check(p_pin text, p_id text, p_n int default 3) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare s tg.sessions := tg.session_for(p_pin, p_id);
begin
  if not tg.is_live(s) then return '[]'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.sid, 'name', x.name, 'group', x.grp)) from (
    select st.sid, st.name, st.grp from unnest(tg.sgroups(s)) as g(x) cross join lateral tg.latest(s.course, g.x, s.week) l
    join tg.students st on st.course = s.course and st.grp = g.x and st.sid = l.sid
    where l.status = 'P' and l.method = 'Self' order by random() limit coalesce(p_n, 3)) x), '[]');
end $$;

-- ---------------------------------------------------------------- attendance lists
create or replace function public.group_state(p_pin text, p_course text, p_group text, p_week int) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); v_id text;
begin
  perform tg.can_manage(me, p_course, p_group);
  update tg.sessions set closed = closes where course = p_course and (grp = p_group or p_group = any(also)) and closed is null and now() > closes;
  select id into v_id from tg.sessions where course = p_course and (grp = p_group or p_group = any(also)) and closed is null and closes >= now() order by opened desc limit 1;
  return jsonb_build_object('live', case when v_id is null then null else tg.live(v_id) end, 'view', tg.week_view(p_course, p_group, p_week));
end $$;
create or replace function public.week_view(p_pin text, p_course text, p_group text, p_week int) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
begin perform tg.can_manage(tg.who(p_pin), p_course, p_group); return tg.week_view(p_course, p_group, p_week); end $$;
create or replace function public.group_summary(p_pin text, p_course text, p_group text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
begin
  perform tg.can_manage(tg.who(p_pin), p_course, p_group);
  return jsonb_build_object('course', p_course, 'group', p_group,
    'weeks', (select jsonb_agg(case n when 7 then 'W7 Mid' when 14 then 'W14 Final' else 'W' || n end order by n) from generate_series(1, 14) n),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'id', sid, 'weeks', to_jsonb(weeks), 'p', p, 'a', a, 'e', e, 'pct', coalesce(to_jsonb(pct), '""'::jsonb)) order by ord)
                      from tg.matrix(p_course, p_group)), '[]'));
end $$;
create or replace function public.mark(p_pin text, p_course text, p_group text, p_week int, p_id text, p_status text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); st tg.students;
begin
  perform tg.can_manage(me, p_course, p_group);
  if p_status not in ('P', 'A', 'E') then raise exception 'Status must be P, A or E.'; end if;
  select * into st from tg.students where course = p_course and grp = p_group and sid = tg.norm_id(p_id);
  if not found then raise exception 'Student not found.'; end if;
  insert into tg.log (course, grp, week, sid, name, status, method, by_ta) values (p_course, p_group, p_week, st.sid, st.name, p_status, 'Manual', me.name);
  return tg.week_view(p_course, p_group, p_week);
end $$;
create or replace function public.mark_all(p_pin text, p_course text, p_group text, p_week int) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); v jsonb;
begin
  perform tg.can_manage(me, p_course, p_group);
  v := tg.week_view(p_course, p_group, p_week);
  insert into tg.log (course, grp, week, sid, name, status, method, by_ta)
    select p_course, p_group, p_week, r->>'id', r->>'name', 'P', 'Manual', me.name from jsonb_array_elements(v->'rows') r where r->>'status' not in ('P', 'E');
  return tg.week_view(p_course, p_group, p_week);
end $$;
create or replace function public.add_guest(p_pin text, p_course text, p_group text, p_week int, p_id text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); v_id text := tg.norm_id(p_id); st tg.students; v_sess text;
begin
  perform tg.can_manage(me, p_course, p_group);
  if v_id = '' then raise exception 'Type the student ID.'; end if;
  select * into st from tg.students where course = p_course and sid = v_id order by ord limit 1;
  if not found then raise exception '% is not on any group list of %.', v_id, p_course; end if;
  if st.grp = p_group then raise exception '% is in this group. Mark them in the list below.', st.name; end if;
  if exists (select 1 from tg.latest(p_course, st.grp, p_week) l where l.sid = v_id and l.status = 'P') then
    return jsonb_build_object('name', st.name, 'group', st.grp, 'already', true);
  end if;
  select id into v_sess from tg.sessions where course = p_course and (grp = p_group or p_group = any(also)) and week = p_week and closed is null and closes >= now() order by opened desc limit 1;
  insert into tg.log (session, course, grp, week, sid, name, status, method, by_ta, note)
    values (coalesce(v_sess, ''), p_course, st.grp, p_week, v_id, st.name, 'P', 'Manual', me.name, 'Attended group ' || p_group || ' with ' || me.name);
  return jsonb_build_object('name', st.name, 'group', st.grp, 'already', false);
end $$;

-- ---------------------------------------------------------------- grades
create or replace function public.grades_view(p_pin text, p_course text, p_group text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin);
begin
  perform tg.can_manage(me, p_course, p_group);
  return jsonb_build_object('course', p_course, 'group', p_group, 'canEditItems', me.role = 'Admin', 'rows', tg.grade_rows(p_course, p_group)) || tg.items_json(p_course);
end $$;
create or replace function public.save_items(p_pin text, p_course text, p_att_max numeric, p_items jsonb) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.admin(p_pin); c text := tg.clean(p_course); x jsonb; i int := 0; k text; seen text[] := '{}';
begin
  for x in select value from jsonb_array_elements(coalesce(p_items, '[]')) loop
    if tg.clean(x->>'item') = '' then continue; end if;
    if coalesce((x->>'max')::numeric, 0) <= 0 then raise exception 'Give "%" a full mark bigger than 0.', tg.clean(x->>'item'); end if;
    if lower(tg.clean(x->>'item')) = any(seen) then raise exception '"%" is written twice.', tg.clean(x->>'item'); end if;
    seen := seen || lower(tg.clean(x->>'item'));
  end loop;
  delete from tg.items where course = c;
  insert into tg.items (course, key, item, max, kind, ord) values (c, 'attendance', 'Attendance', greatest(0, coalesce(p_att_max, 0)), 'Attendance', 0);
  for x in select value from jsonb_array_elements(coalesce(p_items, '[]')) loop
    if tg.clean(x->>'item') = '' then continue; end if;
    i := i + 1;
    k := coalesce(nullif(regexp_replace(coalesce(x->>'key', ''), '[^\w-]', '', 'g'), ''), 'i' || left(replace(gen_random_uuid()::text, '-', ''), 8));
    insert into tg.items (course, key, item, max, kind, ord) values (c, k, tg.clean(x->>'item'), (x->>'max')::numeric, 'Grade', i);
  end loop;
  return tg.items_json(c);
end $$;
create or replace function public.save_scores(p_pin text, p_course text, p_group text, p_changes jsonb) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); x jsonb; it tg.items; st tg.students; v text; n numeric;
begin
  perform tg.can_manage(me, p_course, p_group);
  for x in select value from jsonb_array_elements(coalesce(p_changes, '[]')) loop
    select * into it from tg.items where course = p_course and key = x->>'key' and kind <> 'Attendance';
    if not found then continue; end if;
    select * into st from tg.students where course = p_course and grp = p_group and sid = tg.norm_id(x->>'id');
    if not found then continue; end if;
    v := btrim(coalesce(x->>'score', ''));
    if v = '' then n := null;
    else
      if v !~ '^\d+(\.\d+)?$' then raise exception '%: % must be a number.', st.name, it.item; end if;
      n := v::numeric;
      if n < 0 or n > it.max then raise exception '%: % must be from 0 to %.', st.name, it.item, it.max; end if;
    end if;
    insert into tg.grades (course, grp, sid, name, key, score, by_ta) values (p_course, p_group, st.sid, st.name, it.key, n, me.name);
  end loop;
  return public.grades_view(p_pin, p_course, p_group);
end $$;
create or replace function public.final_export(p_pin text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); out jsonb := '[]'; cc text; r jsonb;
  wk jsonb := (select jsonb_agg(tg.week_label(n) order by n) from generate_series(1, 14) n);
begin
  for cc in select distinct course from tg.students order by 1 loop
    if not (me.role = 'Admin' or cardinality(me.courses) = 0 or cc = any(me.courses)) then continue; end if;
    r := tg.grade_rows(cc, null, case when me.role = 'Admin' then null else me.name end);
    if jsonb_array_length(r) > 0 then
      out := out || jsonb_build_array(jsonb_build_object('course', cc, 'weeks', wk, 'rows', r) || tg.items_json(cc));
    end if;
  end loop;
  return out;
end $$;
-- the admin's full backup: every table except the PINs
create or replace function public.export_all(p_pin text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
begin
  perform tg.admin(p_pin);
  return jsonb_build_object(
    'Staff', (select coalesce(jsonb_agg(jsonb_build_object('Name', name, 'Username', coalesce(username, ''), 'Role', role, 'Status', status, 'Courses', array_to_string(courses, ', ')) order by name), '[]') from tg.staff),
    'Students', (select coalesce(jsonb_agg(jsonb_build_object('Course', course, 'Group', grp, 'Name', name, 'ID', sid, 'TA', ta) order by ord), '[]') from tg.students),
    'Log', (select coalesce(jsonb_agg(jsonb_build_object('Time', to_char(ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'), 'Course', course, 'Group', grp, 'Week', week, 'ID', sid, 'Name', name, 'Status', status, 'Method', method, 'By', by_ta, 'Note', note) order by id), '[]') from tg.log),
    'Grades', (select coalesce(jsonb_agg(jsonb_build_object('Time', to_char(g.ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'), 'Course', g.course, 'Group', g.grp, 'ID', g.sid, 'Name', g.name, 'Item', coalesce(i.item, g.key), 'Score', g.score, 'By', g.by_ta) order by g.id), '[]') from tg.grades g left join tg.items i on i.course = g.course and i.key = g.key),
    'Sessions', (select coalesce(jsonb_agg(jsonb_build_object('TA', ta, 'Course', course, 'Group', array_to_string(array[grp] || also, ' + '), 'Week', week, 'Opened', to_char(opened at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'), 'Mode', case when strict_mode then 'Strict' else 'Normal' end) order by opened), '[]') from tg.sessions));
end $$;

-- only these functions can be called from the website
do $$
declare f text;
begin
  foreach f in array array['student_info(text)', 'check_in(jsonb)', 'register_phone(jsonb)', 'app_state()', 'setup_admin(text,text,text)', 'login(text,text)',
    'whoami(text)', 'logout(text)', 'course_list()', 'register_ta(text,text,text,jsonb)', 'approve_ta(text,text,jsonb)', 'reject_ta(text,text)', 'set_staff_login(text,text,text,text)',
    'add_group(text,text,text,text,jsonb)', 'import_groups(text,text,jsonb)', 'claim_group(text,text,text)', 'assign_group(text,text,text,text)',
    'remove_group(text,text,text)', 'add_staff(text,text,text,text,jsonb)', 'set_staff_courses(text,text,jsonb)', 'remove_staff(text,text)', 'set_term_start(text,text)',
    'open_session(text,text,text,int,int,boolean,boolean,jsonb)', 'live_status(text,text)', 'extend_session(text,text,int)', 'close_session(text,text)',
    'random_check(text,text,int)', 'group_state(text,text,text,int)', 'week_view(text,text,text,int)', 'group_summary(text,text,text)',
    'mark(text,text,text,int,text,text)', 'mark_all(text,text,text,int)', 'add_guest(text,text,text,int,text)', 'grades_view(text,text,text)',
    'save_items(text,text,numeric,jsonb)', 'save_scores(text,text,text,jsonb)', 'final_export(text)', 'export_all(text)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;
revoke all on schema tg from public;
