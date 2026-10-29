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
alter table tg.staff add column if not exists photo text not null default '';   -- profile photo, a small JPEG data URL made in the browser
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
-- everything else anyone writes (groups, grade items, check-ins, term start): what, where, who and when
create table if not exists tg.audit (id bigserial primary key, ts timestamptz not null default now(), course text not null default '', grp text not null default '', what text not null, by_ta text not null default '');
-- project teams: a team can mix students of several groups of the course
create table if not exists tg.teams (course text not null, num int not null, name text not null default '', leader text not null default '', primary key (course, num));
create table if not exists tg.team_members (course text not null, sid text not null, num int not null, primary key (course, sid));
-- the weekly schedule of each group: day (0 = Sunday), time, room and the TA named in the schedule
create table if not exists tg.schedule (course text not null, grp text not null, ta text not null default '', day int not null, starts time not null, ends time not null, room text not null default '',
  primary key (course, grp, day, starts));
create index if not exists log_cgw on tg.log (course, grp, week);
create index if not exists log_session on tg.log (session);
create index if not exists grades_cg on tg.grades (course, grp);
create index if not exists students_sid on tg.students (sid);
alter table tg.staff enable row level security;    alter table tg.students enable row level security;
alter table tg.sessions enable row level security; alter table tg.log enable row level security;
alter table tg.devices enable row level security;  alter table tg.items enable row level security;
alter table tg.grades enable row level security;   alter table tg.settings enable row level security;
alter table tg.tokens enable row level security;
alter table tg.teams enable row level security;    alter table tg.team_members enable row level security;
alter table tg.schedule enable row level security;
alter table tg.audit enable row level security;

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

create or replace function tg.note(c text, g text, what text, by_ta text) returns void language sql as $$
  insert into tg.audit (course, grp, what, by_ta) values (coalesce(c, ''), coalesce(g, ''), what, coalesce(by_ta, '')) $$;
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
-- the courses a TA works in: the courses the admin gave them, the courses of their groups, and their courses in the schedule.
-- A TA sees only these courses; the admin sees every course.
create or replace function tg.my_courses(me tg.staff) returns text[] language sql stable as $$
  with names as (select distinct ta from tg.schedule where ta <> ''),
  mine as (   -- the schedule may write "Toqa Hamdy" for the account "Toqa": a first name counts only when one TA in the schedule has it
    select ta from names where lower(ta) = lower(me.name)
    union select ta from names where lower(ta) like lower(me.name) || ' %' and (select count(*) from names n2 where lower(n2.ta) like lower(me.name) || ' %') = 1
    union select ta from names where lower(me.name) like lower(ta) || ' %')
  select coalesce(array(select distinct c from (
    select unnest(me.courses) as c
    union select course from tg.students where ta = me.name
    union select course from tg.schedule where ta in (select ta from mine)) x where c is not null and c <> '' order by 1), '{}') $$;
create or replace function tg.can_see(me tg.staff, c text) returns boolean language sql stable as $$
  select me.role = 'Admin' or c = any(tg.my_courses(me)) $$;
create or replace function tg.in_course(me tg.staff, c text) returns void language plpgsql as $$
begin
  if tg.can_see(me, c) then return; end if;
  -- a new course nobody uploaded yet: the TA who uploads it works in it
  if not exists (select 1 from tg.students where course = c) then return; end if;
  raise exception 'This course is not one of your courses. Ask the admin.';
end $$;
create or replace function tg.group_ta(c text, g text) returns text language sql stable as $$
  select coalesce((select ta from tg.students where course = c and grp = g and ta <> '' order by ord limit 1), '') $$;
-- every TA works on every group of their courses: students move between groups, so any TA of the course can take attendance and marks
create or replace function tg.can_manage(me tg.staff, c text, g text) returns void language plpgsql as $$
begin
  perform tg.in_course(me, c);
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
    ((l.method = 'Self' or l.session = s.id) and l.course = s.course and l.grp = any(tg.sgroups(s)) and l.week = s.week) or (l.session = s.id and l.grp <> all(tg.sgroups(s)))) $$;

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
    'recent', recent, 'guests', jsonb_array_length(guests), 'guestNames', guests, 'flags', tg.flags(s.course, s.grp, s.week, 8),
    'room', cnt + jsonb_array_length(guests),
    'byGroup', (select jsonb_agg(jsonb_build_object('group', g.x,
        'count', (select count(*) from tg.latest(s.course, g.x, s.week) l join tg.students st on st.course = s.course and st.grp = g.x and st.sid = l.sid where l.status in ('P', 'E')),
        'total', (select count(*) from tg.students st where st.course = s.course and st.grp = g.x)) order by g.x) from unnest(gs) as g(x)));
end $$;

create or replace function tg.week_view(c text, g text, w int) returns jsonb language plpgsql as $$
declare held boolean; rows jsonb;
begin
  held := w = 1 or exists (select 1 from tg.sessions where course = c and (grp = g or g = any(also)) and week = w)
              or exists (select 1 from tg.log where course = c and grp = g and week = w and status in ('P', 'A', 'E'));
  select coalesce(jsonb_agg(jsonb_build_object('id', st.sid, 'name', st.name,
      -- only present and excused show; anything else (no check-in, or a mark taken back) is empty, never 'absent'
      'status', case when l.status in ('P', 'E') then l.status when l.status is null and w = 1 then 'P' else '' end,
      'time', case when l.status = 'P' and l.method = 'Self' then tg.hm(l.ts) else '' end,
      'method', case when l.sid is null then case when w = 1 then 'Week 1' else '' end else tg.method_label(l.method, l.by_ta, l.note) end,
      'team', (select tm.num from tg.team_members tm where tm.course = c and tm.sid = st.sid)) order by st.ord), '[]')
    into rows from tg.students st left join tg.latest(c, g, w) l on l.sid = st.sid where st.course = c and st.grp = g;
  return jsonb_build_object('course', c, 'group', g, 'week', w, 'weekLabel', tg.week_label(w), 'held', held, 'rows', rows,
    'present', (select count(*) from jsonb_array_elements(rows) r where r->>'status' = 'P'),
    'absent', case when held then (select count(*) from jsonb_array_elements(rows) r where r->>'status' = '') else 0 end,
    'excused', (select count(*) from jsonb_array_elements(rows) r where r->>'status' = 'E'),
    'flags', tg.flags(c, g, w, 20));
end $$;

-- every week of every chosen student: P, E, or '' (no absent is ever shown; a held week without P or E is counted as missed for the %)
drop function if exists tg.matrix(text, text, text);
create or replace function tg.matrix(c text, g text default null, t text default null)
returns table (grp text, ta text, name text, sid text, ord bigint, weeks text[], p int, a int, e int, pct numeric, missed int[]) language sql stable as $$
  with st as materialized (select s.grp, s.ta, s.name, s.sid, s.ord from tg.students s where s.course = c and (g is null or s.grp = g) and (t is null or s.ta = t)),
  lat as materialized (select distinct on (l.grp, l.week, l.sid) l.grp, l.week, l.sid, l.status from tg.log l
                       where l.course = c and l.status in ('P', 'A', 'E') order by l.grp, l.week, l.sid, l.id desc),
  held as materialized (select distinct x.grp, x.week from (
                          select l.grp, l.week from tg.log l where l.course = c and l.status in ('P', 'A', 'E')
                          union all select x.g, s.week from tg.sessions s cross join unnest(tg.sgroups(s)) as x(g) where s.course = c) x),
  cells as materialized (
    select st.grp, st.ta, st.name, st.sid, st.ord, w.week,
           case when lat.status in ('P', 'E') then lat.status when lat.status is null and w.week = 1 then 'P' else '' end as v,
           (w.week = 1 or h.week is not null) as held
    from st cross join generate_series(1, 14) as w(week)
    left join lat on lat.grp = st.grp and lat.sid = st.sid and lat.week = w.week
    left join held h on h.grp = st.grp and h.week = w.week)
  select cl.grp, cl.ta, cl.name, cl.sid, cl.ord, array_agg(cl.v order by cl.week),
         count(*) filter (where cl.v = 'P')::int, count(*) filter (where cl.held and cl.v = '')::int, count(*) filter (where cl.v = 'E')::int,
         case when count(*) filter (where cl.held or cl.v <> '') = 0 then null
              else (count(*) filter (where cl.v in ('P', 'E')))::numeric / count(*) filter (where cl.held or cl.v <> '') end,
         coalesce(array_agg(cl.week order by cl.week) filter (where cl.held and cl.v = ''), '{}')
  from cells cl group by cl.grp, cl.ta, cl.name, cl.sid, cl.ord order by cl.ord $$;

create or replace function tg.items_json(c text) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'attendanceMax', coalesce((select max from tg.items where course = c and kind = 'Attendance'), 0),
    'items', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'item', item, 'max', max, 'check', kind = 'Check') order by ord) from tg.items where course = c and kind <> 'Attendance'), '[]')) $$;

create or replace function tg.grade_rows(c text, g text default null, t text default null) returns jsonb language sql stable as $$
  with it as (select key from tg.items where course = c and kind <> 'Attendance'),
  att as (select coalesce((select max from tg.items where course = c and kind = 'Attendance'), 0) as mx),
  m as materialized (select * from tg.matrix(c, g, t)),
  sc as materialized (select distinct on (gr.grp, gr.sid, gr.key) gr.grp, gr.sid, gr.key, gr.score, gr.by_ta, gr.ts from tg.grades gr
         where gr.course = c and gr.key in (select key from it) order by gr.grp, gr.sid, gr.key, gr.id desc),
  agg as materialized (select sc.grp, sc.sid, jsonb_object_agg(sc.key, sc.score) filter (where sc.score is not null) as obj, sum(sc.score) as total,
          jsonb_object_agg(sc.key, jsonb_build_object('by', sc.by_ta, 't', to_char(sc.ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'))) filter (where sc.score is not null) as byk
          from sc group by sc.grp, sc.sid)
  select coalesce(jsonb_agg(jsonb_build_object(
      'group', m.grp, 'ta', m.ta, 'name', m.name, 'id', m.sid, 'weeks', to_jsonb(m.weeks), 'p', m.p, 'a', m.a, 'e', m.e, 'missed', to_jsonb(m.missed),
      'team', (select tm.num from tg.team_members tm where tm.course = c and tm.sid = m.sid),
      'pct', coalesce(to_jsonb(m.pct), '""'::jsonb),
      'attGrade', case when att.mx > 0 and m.pct is not null then to_jsonb(round(m.pct * att.mx, 2)) else '""'::jsonb end,
      'scores', coalesce(agg.obj, '{}'::jsonb), 'by', coalesce(agg.byk, '{}'::jsonb),
      'total', round(coalesce(agg.total, 0) + case when att.mx > 0 and m.pct is not null then round(m.pct * att.mx, 2) else 0 end, 2),
      'section', (select jsonb_agg(case when v in ('P', 'E') then to_jsonb(1) when v = 'A' then to_jsonb(0) else '""'::jsonb end order by n)
                  from unnest(m.weeks) with ordinality as u(v, n) where n not in (7, 14))
    ) order by m.ord), '[]')
  from m cross join att left join agg on agg.grp = m.grp and agg.sid = m.sid $$;

create or replace function tg.dash(me tg.staff) returns jsonb language plpgsql as $$
declare groups jsonb; ts date := tg.term_start(); mc text[] := tg.my_courses(me);
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
  where me.role = 'Admin' or g.course = any(mc);
  return jsonb_build_object(
    'me', jsonb_build_object('name', me.name, 'role', me.role, 'courses', to_jsonb(case when me.role = 'Admin' then me.courses else mc end), 'username', coalesce(me.username, ''), 'photo', coalesce(me.photo, '')),
    'groups', groups,
    'allCourses', case when me.role = 'Admin' then coalesce((select jsonb_agg(c order by c) from (select distinct course as c from tg.students) x), '[]') else '[]' end,
    'weeks', (select jsonb_agg(jsonb_build_array(n, tg.week_label(n) || case when ts is not null then ', ' || to_char(ts + (n - 1) * 7, 'FMDD Mon') else '' end) order by n) from generate_series(1, 14) n),
    'termStart', coalesce(to_char(ts, 'YYYY-MM-DD'), ''), 'currentWeek', tg.current_week(), 'url', '', 'sheetUrl', '',
    'teams', coalesce((select jsonb_agg(jsonb_build_object('course', t.course, 'num', t.num, 'name', t.name,
        'leader', coalesce((select st.name from tg.students st where st.course = t.course and st.sid = t.leader order by st.ord limit 1), ''),
        'count', (select count(*) from tg.team_members m where m.course = t.course and m.num = t.num),
        'groups', (select coalesce(jsonb_agg(distinct st.grp order by st.grp), '[]') from tg.team_members m join tg.students st on st.course = m.course and st.sid = m.sid
                   where m.course = t.course and m.num = t.num)) order by t.course, t.num)
      from tg.teams t where me.role = 'Admin' or t.course = any(mc)), '[]'),
    'staff', case when me.role = 'Admin' then (select jsonb_agg(jsonb_build_object('name', name, 'role', role, 'courses', to_jsonb(courses), 'username', coalesce(username, ''), 'status', status, 'photo', coalesce(photo, '')) order by role, status, name) from tg.staff) end,
    -- the check-ins this staff member opened lately, with day and time in Cairo: Take attendance learns which groups to pick, on every device
    'habits', coalesce((select jsonb_agg(jsonb_build_object('c', h.course, 'g', h.gs, 'd', h.d, 'm', h.m, 't', h.t) order by h.t) from (
        select s.course, to_jsonb(tg.sgroups(s)) as gs, extract(dow from s.opened at time zone 'Africa/Cairo')::int as d,
               (extract(hour from s.opened at time zone 'Africa/Cairo') * 60 + extract(minute from s.opened at time zone 'Africa/Cairo'))::int as m, tg.ms(s.opened) as t
        from tg.sessions s where s.ta = me.name and s.opened > now() - interval '150 days' order by s.opened desc limit 80) h), '[]'),
    'schedule', coalesce((select jsonb_agg(jsonb_build_object('course', sc.course, 'group', sc.grp, 'ta', sc.ta, 'day', sc.day,
        'start', to_char(sc.starts, 'HH24:MI'), 'end', to_char(sc.ends, 'HH24:MI'), 'room', sc.room) order by sc.course, sc.day, sc.starts, sc.grp)
      from tg.schedule sc where me.role = 'Admin' or sc.course = any(mc)), '[]'));
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

-- a student sees their own attendance and team, only from a phone that registered or checked in as them (never grades)
-- one student's marks in one course: what the student sees on their own phone
create or replace function tg.student_grade(c text, g text, v_sid text, v_pct numeric) returns jsonb language sql stable as $$
  with att as (select coalesce((select max from tg.items where course = c and kind = 'Attendance'), 0) as mx),
  it as (select i.item, i.max, i.ord, i.kind = 'Check' as chk,
           (select gr.score from tg.grades gr where gr.course = c and gr.grp = g and gr.sid = v_sid and gr.key = i.key order by gr.id desc limit 1) as score,
           (select jsonb_build_object('by', gr.by_ta, 't', to_char(gr.ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI')) from tg.grades gr
              where gr.course = c and gr.grp = g and gr.sid = v_sid and gr.key = i.key order by gr.id desc limit 1) as who
         from tg.items i where i.course = c and i.kind <> 'Attendance')
  select case when att.mx = 0 and not exists (select 1 from it) then null else jsonb_build_object(
    'attMax', att.mx,
    'attGrade', case when att.mx > 0 and v_pct is not null then to_jsonb(round(v_pct * att.mx, 2)) else '""'::jsonb end,
    'items', coalesce((select jsonb_agg(jsonb_build_object('item', it.item, 'max', it.max, 'check', it.chk, 'score', coalesce(to_jsonb(it.score), '""'::jsonb),
                   'by', case when it.score is not null then it.who->>'by' else '' end, 't', case when it.score is not null then it.who->>'t' else '' end) order by it.ord) from it), '[]'),
    'total', round(coalesce((select sum(it.score) from it), 0) + case when att.mx > 0 and v_pct is not null then round(v_pct * att.mx, 2) else 0 end, 2),
    'max', att.mx + coalesce((select sum(it.max) from it where it.item !~* '^\s*bonus\M'), 0)) end
  from att $$;

-- every mark and attendance change of one student in one course, newest first, with who made it
create or replace function tg.student_history(c text, v_sid text, n int default 300) returns jsonb language sql stable as $$
  select coalesce((select jsonb_agg(v.j order by v.ts desc, v.id desc) from (select * from (
    select y.ts, y.id, jsonb_build_object('t', to_char(y.ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'), 'kind', 'Mark', 'group', y.grp, 'id', y.sid, 'name', y.name,
             'what', y.item, 'from', coalesce(y.prev::text, ''), 'to', coalesce(y.score::text, ''), 'by', y.by_ta) as j
    from (select g.*, coalesce(i.item, g.key) as item, lag(g.score) over (partition by g.key order by g.id) as prev, row_number() over (partition by g.key order by g.id) as k
          from tg.grades g left join tg.items i on i.course = g.course and i.key = g.key where g.course = c and g.sid = v_sid) y
    where y.prev is distinct from y.score and not (y.k = 1 and y.score is null)
    union all
    select z.ts, z.id, jsonb_build_object('t', to_char(z.ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'), 'kind', 'Attendance', 'group', z.grp, 'id', z.sid, 'name', z.name,
             'what', tg.week_label(z.week), 'from', coalesce(z.prev, ''), 'to', z.status, 'how', z.method, 'by', case when z.method = 'Self' then 'The student (QR)' else z.by_ta end) as j
    from (select l.*, lag(l.status) over (partition by l.grp, l.week order by l.id) as prev from tg.log l where l.course = c and l.sid = v_sid) z
    where z.prev is distinct from z.status and not (z.prev is null and z.status = 'A')
  ) u order by u.ts desc, u.id desc limit n) v), '[]') $$;

create or replace function public.student_status(p jsonb) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare v_id text := tg.norm_id(p->>'id'); v_dev text := left(regexp_replace(coalesce(p->>'device', ''), '[^\w-]', '', 'g'), 80); v_out jsonb;
begin
  if v_id = '' or v_dev = '' or not (exists (select 1 from tg.devices where device = v_dev and sid = v_id)
                                     or exists (select 1 from tg.log where device = v_dev and sid = v_id and status = 'P')) then
    return jsonb_build_object('ok', false);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('course', st.course, 'group', st.grp, 'name', st.name,
      'team', (select jsonb_build_object('num', t.num, 'name', t.name,
                 'leader', coalesce((select s2.name from tg.students s2 where s2.course = t.course and s2.sid = t.leader order by s2.ord limit 1), ''))
               from tg.team_members m join tg.teams t on t.course = m.course and t.num = m.num where m.course = st.course and m.sid = st.sid),
      'weeks', to_jsonb(mx.weeks), 'p', mx.p, 'a', mx.a, 'e', mx.e, 'missed', to_jsonb(mx.missed), 'pct', coalesce(to_jsonb(mx.pct), '""'::jsonb),
      'grade', tg.student_grade(st.course, st.grp, st.sid, mx.pct),
      'ta', tg.group_ta(st.course, st.grp),
      'schedule', coalesce((select jsonb_agg(jsonb_build_object('day', sc.day, 'start', to_char(sc.starts, 'HH24:MI'), 'end', to_char(sc.ends, 'HH24:MI'), 'room', sc.room, 'ta', sc.ta) order by sc.day, sc.starts)
                   from tg.schedule sc where sc.course = st.course and sc.grp = st.grp), '[]'),
      'history', tg.student_history(st.course, st.sid, 100),
      'groupAvg', (select jsonb_build_object('pct', avg((r->>'pct')::numeric) filter (where r->>'pct' <> ''), 'total', round(avg((r->>'total')::numeric), 2), 'n', count(*))
                   from jsonb_array_elements(tg.grade_rows(st.course, st.grp)) r)) order by st.course, st.grp), '[]')
    into v_out
  from tg.students st cross join lateral (select * from tg.matrix(st.course, st.grp) x where x.sid = st.sid limit 1) mx
  where st.sid = v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'courses', v_out, 'currentWeek', tg.current_week());
end $$;

-- ---------------------------------------------------------------- staff API
-- every student this staff member can see, with attendance and grades: the page answers questions from it
create or replace function public.ask_data(p_pin text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin);
begin
  return jsonb_build_object('currentWeek', tg.current_week(), 'courses', coalesce((
    select jsonb_agg(jsonb_build_object('course', c.course, 'rows', tg.grade_rows(c.course, null, null)) || tg.items_json(c.course) order by c.course)
    from (select distinct st.course from tg.students st where tg.can_see(me, st.course)) c), '[]'));
end $$;

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

-- each staff member's own settings: profile photo and password
create or replace function public.set_my_photo(p_pin text, p_photo text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); v text := coalesce(p_photo, '');
begin
  if v <> '' and (v !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(v) > 300000) then
    raise exception 'This photo cannot be used. Choose a JPG or PNG image.';
  end if;
  update tg.staff set photo = v where name = me.name;
  return tg.dash((select st from tg.staff st where name = me.name));
end $$;
-- also sets or changes the username: accounts made with a PIN before usernames have none
drop function if exists public.change_my_password(text, text, text);
create or replace function public.change_my_password(p_pin text, p_old text, p_new text, p_user text default null) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); u text := coalesce(nullif(lower(btrim(coalesce(p_user, ''))), ''), lower(coalesce(me.username, '')));
begin
  if not ((me.pass_hash is not null and me.pass_hash = extensions.crypt(coalesce(p_old, ''), me.pass_hash))
          or (me.pass_hash is null and me.pin is not null and me.pin = btrim(coalesce(p_old, '')))) then
    perform pg_sleep(1); raise exception 'The current password is wrong.';
  end if;
  if u = '' then raise exception 'Choose a username first.'; end if;
  u := tg.good_login(u, p_new, me.name);
  update tg.staff set username = u, pass_hash = extensions.crypt(p_new, extensions.gen_salt('bf')), pin = null where name = me.name;
  delete from tg.tokens where staff = me.name and token <> btrim(coalesce(p_pin, ''));
  return jsonb_build_object('ok', true, 'username', u, 'dash', tg.dash((select st from tg.staff st where name = me.name)));
end $$;

create or replace function public.add_group(p_pin text, p_course text, p_group text, p_ta text, p_list jsonb) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); c text := tg.clean(p_course); g text := tg.clean(p_group); t text; owner text; n int; d jsonb;
begin
  if c = '' or g = '' then raise exception 'Write the course and the group.'; end if;
  perform tg.in_course(me, c);
  owner := tg.group_ta(c, g);
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
  perform tg.note(c, g, 'Added ' || n || ' students to the group', me.name);
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
  perform tg.note(c, '', 'Uploaded ' || ng || ' groups with ' || total || ' students', me.name);
  return tg.dash(me) || jsonb_build_object('imported', jsonb_build_object('groups', ng, 'students', total, 'skipped', skipped));
end $$;

-- one student into a group, or out of it. The TA of the group (or any TA of the course) and the admin can do it.
-- A removed student's attendance and marks stay in the history.
create or replace function public.add_student(p_pin text, p_course text, p_group text, p_name text, p_id text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); n text := tg.clean(p_name); v text := tg.norm_id(p_id); other text;
begin
  perform tg.can_manage(me, p_course, p_group);
  if n = '' or v = '' then raise exception 'Write the student name and ID.'; end if;
  if length(v) < 5 then raise exception 'The ID looks too short.'; end if;
  if exists (select 1 from tg.students where course = p_course and grp = p_group and sid = v) then
    raise exception '% is already in group %.', (select name from tg.students where course = p_course and grp = p_group and sid = v limit 1), p_group;
  end if;
  select grp into other from tg.students where course = p_course and sid = v order by ord limit 1;
  if other is not null then raise exception 'This ID is already in group % of this course. Remove the student from there first.', other; end if;
  insert into tg.students (course, grp, name, sid, ta) values (p_course, p_group, n, v, tg.group_ta(p_course, p_group));
  perform tg.note(p_course, p_group, 'Added the student ' || n || ' (' || v || ')', me.name);
  return tg.dash(me);
end $$;
create or replace function public.remove_student(p_pin text, p_course text, p_group text, p_id text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); st tg.students;
begin
  perform tg.can_manage(me, p_course, p_group);
  select * into st from tg.students where course = p_course and grp = p_group and sid = tg.norm_id(p_id);
  if not found then raise exception 'Student not found.'; end if;
  delete from tg.students where course = p_course and grp = p_group and sid = st.sid;
  if not exists (select 1 from tg.students where course = p_course and sid = st.sid) then
    delete from tg.team_members where course = p_course and sid = st.sid;
  end if;
  perform tg.note(p_course, p_group, 'Removed the student ' || st.name || ' (' || st.sid || ')', me.name);
  return tg.dash(me);
end $$;

create or replace function public.claim_group(p_pin text, p_course text, p_group text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); owner text;
begin
  perform tg.in_course(me, p_course);
  owner := tg.group_ta(p_course, p_group);
  if owner <> '' and owner <> me.name then raise exception 'This group belongs to %. Ask the admin to change it.', owner; end if;
  update tg.students set ta = me.name where course = p_course and grp = p_group;
  perform tg.note(p_course, p_group, 'Took the group as their own', me.name);
  return tg.dash(me);
end $$;

create or replace function public.assign_group(p_pin text, p_course text, p_group text, p_ta text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.admin(p_pin); t text := tg.clean(p_ta);
begin
  if t <> '' and not exists (select 1 from tg.staff where name = t and status = 'active') then raise exception 'This TA was not found.'; end if;
  update tg.students set ta = t where course = p_course and grp = p_group;
  perform tg.note(p_course, p_group, 'Changed the TA of the group to ' || coalesce(nullif(t, ''), 'nobody'), me.name);
  return tg.dash(me);
end $$;

create or replace function public.remove_group(p_pin text, p_course text, p_group text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.admin(p_pin);
begin
  delete from tg.students where course = p_course and grp = p_group;
  perform tg.note(p_course, p_group, 'Deleted the group', me.name);
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
  perform tg.note('', '', 'Set the term start to ' || coalesce(nullif(v, ''), 'nothing'), me.name);
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
  perform tg.note(p_course, p_group, 'Opened the check-in of ' || tg.week_label(p_week) || ' for group' || case when cardinality(v_also) > 0 then 's ' || array_to_string(array[p_group] || v_also, ' + ') else ' ' || p_group end, me.name);
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
  perform tg.note(s.course, s.grp, 'Added ' || coalesce(p_minutes, 5) || ' minutes to the check-in of ' || tg.week_label(s.week), (tg.who(p_pin)).name);
  return tg.live(p_id);
end $$;
create or replace function public.close_session(p_pin text, p_id text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare s tg.sessions := tg.session_for(p_pin, p_id);
begin
  update tg.sessions set closed = least(now(), closes) where id = p_id and closed is null;
  perform tg.note(s.course, s.grp, 'Closed the check-in of ' || tg.week_label(s.week), (tg.who(p_pin)).name);
  return tg.live(p_id);
end $$;
-- the student has no internet: the TA types the ID (or its last digits) on the live screen and the student is present in their own group
create or replace function public.session_mark(p_pin text, p_id text, p_sid text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare s tg.sessions := tg.session_for(p_pin, p_id); me tg.staff := tg.who(p_pin); v text := tg.norm_id(p_sid); st tg.students; n int; cands jsonb;
begin
  if not tg.is_live(s) then raise exception 'Check-in is closed. Mark the student in the list below.'; end if;
  if length(v) < 3 then raise exception 'Type the student ID, or at least its last 3 digits.'; end if;
  select * into st from tg.students where course = s.course and sid = v order by (grp = any(tg.sgroups(s))) desc, ord limit 1;
  if not found then
    select count(*), jsonb_agg(jsonb_build_object('id', x.sid, 'name', x.name, 'group', x.grp) order by (x.grp = any(tg.sgroups(s))) desc, x.name)
      into n, cands
      from (select distinct on (sid) * from tg.students where course = s.course and sid like '%' || v order by sid, (grp = any(tg.sgroups(s))) desc, ord) x;
    if n = 0 then raise exception 'No student of % has an ID ending in %.', s.course, v; end if;
    if n > 1 then return jsonb_build_object('choose', cands); end if;
    select * into st from tg.students where course = s.course and sid = cands->0->>'id' order by (grp = any(tg.sgroups(s))) desc, ord limit 1;
  end if;
  if exists (select 1 from tg.latest(s.course, st.grp, s.week) l where l.sid = st.sid and l.status in ('P', 'E')) then
    return jsonb_build_object('name', st.name, 'id', st.sid, 'group', st.grp, 'already', true);
  end if;
  insert into tg.log (session, course, grp, week, sid, name, status, method, by_ta, note)
    values (s.id, s.course, st.grp, s.week, st.sid, st.name, 'P', 'Manual', me.name,
            case when st.grp = any(tg.sgroups(s)) then '' else 'Attended group ' || s.grp || ' with ' || me.name end);
  return jsonb_build_object('name', st.name, 'id', st.sid, 'group', st.grp, 'already', false, 'guest', not (st.grp = any(tg.sgroups(s))));
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
-- mark many weeks of many students of one group at once, from the All weeks page: p_items = [{"id": "...", "weeks": [2, 3, 5]}]
create or replace function public.mark_weeks(p_pin text, p_course text, p_group text, p_items jsonb, p_status text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); x jsonb; st tg.students; w int;
begin
  perform tg.can_manage(me, p_course, p_group);
  if p_status not in ('P', 'A', 'E') then raise exception 'Status must be P, A or E.'; end if;
  for x in select value from jsonb_array_elements(coalesce(p_items, '[]')) loop
    select * into st from tg.students where course = p_course and grp = p_group and sid = tg.norm_id(x->>'id');
    if not found then raise exception 'Student % is not in group %.', x->>'id', p_group; end if;
    for w in select distinct (value #>> '{}')::int from jsonb_array_elements(coalesce(x->'weeks', '[]')) loop
      if w < 1 or w > 14 then raise exception 'Week % does not exist.', w; end if;
      insert into tg.log (course, grp, week, sid, name, status, method, by_ta) values (p_course, p_group, w, st.sid, st.name, p_status, 'Manual', me.name);
    end loop;
  end loop;
  return public.group_summary(p_pin, p_course, p_group);
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

-- import attendance from an Excel file: p_rows = [{"id", "week", "status"}], only P (present) and E (excused) are recorded.
-- Absent is never written, so it stays empty. A student already present or excused that week is left as is.
-- The admin can import any group of the course; a TA only the groups that are theirs.
create or replace function public.import_attendance(p_pin text, p_course text, p_rows jsonb) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); c text := tg.clean(p_course); n_marks int; n_saved int; n_ok int; n_notyours int; v_missing text[];
begin
  if c = '' then raise exception 'Choose the course.'; end if;
  perform tg.in_course(me, c);
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'No present marks found in the file.'; end if;
  if jsonb_array_length(p_rows) > 20000 then raise exception 'The file is too big. Import fewer weeks or groups at a time.'; end if;
  create temp table if not exists tg_import (sid text, week int, status text, grp text, name text, mine boolean) on commit drop;
  truncate tg_import;
  insert into tg_import (sid, week, status)
    select distinct on (y.sid, y.week) y.sid, y.week, y.status from (
      select tg.norm_id(x->>'id') as sid, case when coalesce(x->>'week', '') ~ '^\d{1,2}$' then (x->>'week')::int end as week, upper(coalesce(x->>'status', '')) as status
      from jsonb_array_elements(p_rows) x) y
    where y.week between 1 and 14 and y.status in ('P', 'E') and y.sid <> ''
    order by y.sid, y.week, y.status desc;   -- P wins over E for the same week
  get diagnostics n_marks = row_count;
  update tg_import i set grp = st.grp, name = st.name, mine = true
    from tg.students st where st.course = c and st.sid = i.sid;
  select array_agg(distinct sid order by sid) into v_missing from tg_import where grp is null;
  select count(*) filter (where mine), count(*) filter (where grp is not null and not mine) into n_ok, n_notyours from tg_import;
  if n_ok = 0 and coalesce(array_length(v_missing, 1), 0) > 0 and n_notyours = 0 then
    raise exception 'None of the students in the file are in %. Choose the right course.', c;
  end if;
  with ins as (
    insert into tg.log (session, course, grp, week, sid, name, status, method, by_ta)
    select '', c, i.grp, i.week, i.sid, i.name, i.status, 'Manual', me.name from tg_import i
    where i.mine and not exists (select 1 from tg.latest(c, i.grp, i.week) l where l.sid = i.sid and l.status in ('P', 'E'))
    returning 1)
  select count(*) into n_saved from ins;
  drop table tg_import;
  return jsonb_build_object('marks', n_marks, 'saved', n_saved, 'already', n_ok - n_saved, 'notYours', n_notyours,
    'missing', coalesce(to_jsonb(v_missing), '[]'::jsonb));
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
    -- Check: a done / not done item, the TA ticks it and the student gets the full mark
    insert into tg.items (course, key, item, max, kind, ord) values (c, k, tg.clean(x->>'item'), (x->>'max')::numeric, case when coalesce((x->>'check')::boolean, false) then 'Check' else 'Grade' end, i);
  end loop;
  perform tg.note(c, '', 'Changed the grade items: attendance ' || greatest(0, coalesce(p_att_max, 0)) || coalesce(', ' || (select string_agg(item || ' ' || max, ', ' order by ord) from tg.items where course = c and kind <> 'Attendance'), ''), me.name);
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
-- who changed what: every mark and every attendance change of a course (or one group), newest first, with the TA who made it
create or replace function public.change_history(p_pin text, p_course text, p_group text default null) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin);
begin
  if p_group is null or p_group = '' then perform tg.in_course(me, p_course); p_group := null; else perform tg.can_manage(me, p_course, p_group); end if;
  return coalesce((select jsonb_agg(v.j order by v.ts desc, v.id desc) from (select * from (
    select y.ts, y.id, jsonb_build_object('t', to_char(y.ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'), 'kind', 'Mark', 'group', y.grp, 'id', y.sid, 'name', y.name,
             'what', y.item, 'from', coalesce(y.prev::text, ''), 'to', coalesce(y.score::text, ''), 'by', y.by_ta) as j
    from (select g.*, coalesce(i.item, g.key) as item, lag(g.score) over (partition by g.course, g.sid, g.key order by g.id) as prev,
                 row_number() over (partition by g.course, g.sid, g.key order by g.id) as n
          from tg.grades g left join tg.items i on i.course = g.course and i.key = g.key
          where g.course = p_course and (p_group is null or g.grp = p_group)) y
    where y.prev is distinct from y.score and not (y.n = 1 and y.score is null)
    union all
    select z.ts, z.id, jsonb_build_object('t', to_char(z.ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'), 'kind', 'Attendance', 'group', z.grp, 'id', z.sid, 'name', z.name,
             'what', tg.week_label(z.week), 'from', coalesce(z.prev, ''), 'to', z.status, 'how', z.method, 'by', case when z.method = 'Self' then 'The student (QR)' else z.by_ta end) as j
    from (select l.*, lag(l.status) over (partition by l.course, l.grp, l.sid, l.week order by l.id) as prev
          from tg.log l where l.course = p_course and (p_group is null or l.grp = p_group)) z
    where z.prev is distinct from z.status and not (z.prev is null and z.status = 'A')
    union all
    select a.ts, a.id, jsonb_build_object('t', to_char(a.ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'), 'kind', 'Other', 'group', a.grp, 'id', '', 'name', '',
             'what', a.what, 'from', '', 'to', '', 'by', a.by_ta) as j
    from tg.audit a where a.course = p_course and (p_group is null or a.grp = p_group or a.grp = '')
  ) u order by u.ts desc, u.id desc limit 600) v), '[]');
end $$;

-- everything one TA wrote in the courses this staff member can see: marks, attendance and the other changes, newest first
create or replace function public.ta_activity(p_pin text, p_ta text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); t text := lower(btrim(coalesce(p_ta, '')));
begin
  if t = '' then return '[]'; end if;
  return coalesce((select jsonb_agg(v.j order by v.ts desc, v.id desc) from (select * from (
    select y.ts, y.id, jsonb_build_object('t', to_char(y.ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'), 'kind', 'Mark', 'course', y.course, 'group', y.grp, 'id', y.sid, 'name', y.name,
             'what', y.item, 'from', coalesce(y.prev::text, ''), 'to', coalesce(y.score::text, ''), 'by', y.by_ta) as j
    from (select g.*, coalesce(i.item, g.key) as item, lag(g.score) over (partition by g.course, g.sid, g.key order by g.id) as prev,
                 row_number() over (partition by g.course, g.sid, g.key order by g.id) as k
          from tg.grades g left join tg.items i on i.course = g.course and i.key = g.key where tg.can_see(me, g.course)) y
    where (lower(y.by_ta) = t or lower(y.by_ta) like t || ' %' or t like lower(y.by_ta) || ' %') and y.prev is distinct from y.score and not (y.k = 1 and y.score is null)
    union all
    select z.ts, z.id, jsonb_build_object('t', to_char(z.ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'), 'kind', 'Attendance', 'course', z.course, 'group', z.grp, 'id', z.sid, 'name', z.name,
             'what', tg.week_label(z.week), 'from', coalesce(z.prev, ''), 'to', z.status, 'how', z.method, 'by', z.by_ta) as j
    from (select l.*, lag(l.status) over (partition by l.course, l.grp, l.sid, l.week order by l.id) as prev from tg.log l where tg.can_see(me, l.course)) z
    where z.method <> 'Self' and (lower(z.by_ta) = t or lower(z.by_ta) like t || ' %' or t like lower(z.by_ta) || ' %')
      and z.prev is distinct from z.status and not (z.prev is null and z.status = 'A')
    union all
    select a.ts, a.id, jsonb_build_object('t', to_char(a.ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'), 'kind', 'Other', 'course', a.course, 'group', a.grp, 'id', '', 'name', '',
             'what', a.what, 'from', '', 'to', '', 'by', a.by_ta) as j
    from tg.audit a where (a.course = '' or tg.can_see(me, a.course)) and (lower(a.by_ta) = t or lower(a.by_ta) like t || ' %' or t like lower(a.by_ta) || ' %')
  ) u order by u.ts desc, u.id desc limit 600) v), '[]');
end $$;

-- one student: group, TA, team, every mark with who wrote it, every week with who marked it, and the whole history of the student
create or replace function public.student_profile(p_pin text, p_course text, p_id text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); st tg.students; r jsonb;
begin
  select * into st from tg.students where course = p_course and sid = tg.norm_id(p_id) order by ord limit 1;
  if not found then raise exception 'Student not found.'; end if;
  perform tg.can_manage(me, p_course, st.grp);
  select x into r from jsonb_array_elements(tg.grade_rows(p_course, st.grp)) x where x->>'id' = st.sid limit 1;
  return coalesce(r, '{}'::jsonb) || tg.items_json(p_course) || jsonb_build_object(
    'course', p_course, 'group', st.grp, 'name', st.name, 'id', st.sid,
    'ta', coalesce(nullif(tg.group_ta(p_course, st.grp), ''), (select sc.ta from tg.schedule sc where sc.course = p_course and sc.grp = st.grp and sc.ta <> '' limit 1), ''),
    'teamName', (select t.name from tg.team_members m join tg.teams t on t.course = m.course and t.num = m.num where m.course = p_course and m.sid = st.sid limit 1),
    'phone', exists (select 1 from tg.devices d where d.sid = st.sid),
    'weekLog', (select jsonb_agg(jsonb_build_object('week', n, 'label', tg.week_label(n), 'status', coalesce(l.status, ''), 'how', coalesce(l.method, ''),
                  'by', case when l.method = 'Self' then 'The student (QR)' else coalesce(l.by_ta, '') end, 'note', coalesce(l.note, ''),
                  't', coalesce(to_char(l.ts at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI'), '')) order by n)
                from generate_series(1, 14) n left join lateral (select * from tg.log g where g.course = p_course and g.grp = st.grp and g.sid = st.sid and g.week = n order by g.id desc limit 1) l on true),
    'history', tg.student_history(p_course, st.sid));
end $$;

-- a project team: every member with attendance and marks, whatever their group, for grading the team together
create or replace function public.team_view(p_pin text, p_course text, p_num int) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); t tg.teams; g text; acc jsonb := '[]'; r jsonb;
begin
  perform tg.in_course(me, p_course);
  select * into t from tg.teams where course = p_course and num = p_num;
  if not found then raise exception 'Team not found.'; end if;
  for g in select distinct st.grp from tg.team_members m join tg.students st on st.course = m.course and st.sid = m.sid where m.course = p_course and m.num = p_num order by 1 loop
    for r in select value from jsonb_array_elements(tg.grade_rows(p_course, g)) loop
      if exists (select 1 from tg.team_members m where m.course = p_course and m.num = p_num and m.sid = r->>'id') then
        acc := acc || jsonb_build_array(r || jsonb_build_object('leader', r->>'id' = t.leader, 'canEdit', true));
      end if;
    end loop;
  end loop;
  select coalesce(jsonb_agg(x order by (x->>'leader')::boolean desc, x->>'group', x->>'name'), '[]') into acc from jsonb_array_elements(acc) x;
  return jsonb_build_object('course', p_course, 'num', t.num, 'name', t.name, 'canEditItems', me.role = 'Admin', 'rows', acc) || tg.items_json(p_course);
end $$;
-- marks for team members; each mark is saved in the student's own group, like the group grades page
create or replace function public.save_team_scores(p_pin text, p_course text, p_num int, p_changes jsonb) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); x jsonb; it tg.items; st tg.students; v text; n numeric;
begin
  perform tg.in_course(me, p_course);
  for x in select value from jsonb_array_elements(coalesce(p_changes, '[]')) loop
    select * into it from tg.items where course = p_course and key = x->>'key' and kind <> 'Attendance';
    if not found then continue; end if;
    select s2.* into st from tg.students s2 join tg.team_members m on m.course = s2.course and m.sid = s2.sid
      where s2.course = p_course and m.num = p_num and s2.sid = tg.norm_id(x->>'id') order by s2.ord limit 1;
    if not found then continue; end if;
    perform tg.can_manage(me, p_course, st.grp);
    v := btrim(coalesce(x->>'score', ''));
    if v = '' then n := null;
    else
      if v !~ '^\d+(\.\d+)?$' then raise exception '%: % must be a number.', st.name, it.item; end if;
      n := v::numeric;
      if n < 0 or n > it.max then raise exception '%: % must be from 0 to %.', st.name, it.item, it.max; end if;
    end if;
    insert into tg.grades (course, grp, sid, name, key, score, by_ta) values (p_course, st.grp, st.sid, st.name, it.key, n, me.name);
  end loop;
  return public.team_view(p_pin, p_course, p_num);
end $$;
create or replace function public.final_export(p_pin text) returns jsonb language plpgsql security definer set search_path = tg, public, extensions as $$
declare me tg.staff := tg.who(p_pin); out jsonb := '[]'; cc text; r jsonb;
  wk jsonb := (select jsonb_agg(tg.week_label(n) order by n) from generate_series(1, 14) n);
begin
  for cc in select distinct course from tg.students order by 1 loop
    if not tg.can_see(me, cc) then continue; end if;
    r := tg.grade_rows(cc, null, null);
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
  foreach f in array array['student_info(text)', 'check_in(jsonb)', 'register_phone(jsonb)', 'student_status(jsonb)', 'app_state()', 'setup_admin(text,text,text)', 'login(text,text)',
    'whoami(text)', 'logout(text)', 'set_my_photo(text,text)', 'change_my_password(text,text,text,text)', 'course_list()', 'register_ta(text,text,text,jsonb)', 'approve_ta(text,text,jsonb)', 'reject_ta(text,text)', 'set_staff_login(text,text,text,text)',
    'add_group(text,text,text,text,jsonb)', 'import_groups(text,text,jsonb)', 'claim_group(text,text,text)', 'assign_group(text,text,text,text)',
    'remove_group(text,text,text)', 'add_staff(text,text,text,text,jsonb)', 'set_staff_courses(text,text,jsonb)', 'remove_staff(text,text)', 'set_term_start(text,text)',
    'open_session(text,text,text,int,int,boolean,boolean,jsonb)', 'live_status(text,text)', 'extend_session(text,text,int)', 'close_session(text,text)',
    'random_check(text,text,int)', 'session_mark(text,text,text)', 'group_state(text,text,text,int)', 'week_view(text,text,text,int)', 'group_summary(text,text,text)',
    'mark(text,text,text,int,text,text)', 'mark_all(text,text,text,int)', 'mark_weeks(text,text,text,jsonb,text)', 'add_guest(text,text,text,int,text)', 'grades_view(text,text,text)', 'ask_data(text)',
    'save_items(text,text,numeric,jsonb)', 'import_attendance(text,text,jsonb)', 'team_view(text,text,int)', 'save_team_scores(text,text,int,jsonb)', 'save_scores(text,text,text,jsonb)', 'final_export(text)', 'export_all(text)', 'change_history(text,text,text)', 'student_profile(text,text,text)', 'ta_activity(text,text)', 'add_student(text,text,text,text,text)', 'remove_student(text,text,text,text)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;
revoke all on schema tg from public;
