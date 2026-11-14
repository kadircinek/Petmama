-- Mama Haritası — 0020: sosyal onay ve sosyal profil RPC'leri (spec §5.5/0)
--
-- Mahalle RPC'leriyle aynı kurallar: `security definer`, ilk iş `private.require_uid()`, anon'a kapalı,
-- iş kuralı sonuçları jsonb `status` (+ `reason`).

-- Kendi sosyal profilin; satır (onay) yoksa 0 satır
create function public.social_profile_me()
returns table (is_visible boolean, about text, interests public.social_interest[], consented boolean)
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
begin
  return query
    select sp.is_visible, sp.about, sp.interests, private.social_consented(v_uid)
    from public.social_profiles sp
    where sp.user_id = v_uid;
end
$$;

-- Tek seferlik sosyal onay (18+ ve koşullar); idempotent — ilk onay zamanı korunur
create function public.give_social_consent()
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
begin
  perform private.ensure_profile(v_uid);
  insert into public.social_profiles (user_id, adult_confirmed_at, terms_accepted_at)
  values (v_uid, now(), now())
  on conflict (user_id) do update
    set adult_confirmed_at = coalesce(public.social_profiles.adult_confirmed_at, excluded.adult_confirmed_at),
        terms_accepted_at  = coalesce(public.social_profiles.terms_accepted_at, excluded.terms_accepted_at);
  return jsonb_build_object('status', 'ok');
end
$$;

-- Görünürlük, hakkımda, ilgi etiketleri ve (verilirse) kaba konum. Görünür yapmak için konum şart
-- (istemci verir ya da önceki `cell` vardır).
create function public.update_social_profile(
  p_is_visible boolean,
  p_about      text,
  p_interests  public.social_interest[],
  lat          float8 default null,
  lng          float8 default null
)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  c_max_about constant int := 300;
  v_uid       uuid := private.require_uid();
  v_about     text := private.trim_text(p_about);
  v_interests public.social_interest[];
  v_pt        extensions.geography;
  v_has_cell  boolean;
begin
  if p_is_visible is null then
    raise exception 'invalid_parameter' using errcode = '22023';
  end if;
  if (lat is null) <> (lng is null)
     or lat not between -90 and 90 or lng not between -180 and 180 then
    raise exception 'invalid_location' using errcode = '22023';
  end if;

  perform private.ensure_profile(v_uid);
  if not private.social_consented(v_uid) then
    return jsonb_build_object('status', 'consent_required');
  end if;

  if char_length(v_about) > c_max_about then
    return jsonb_build_object('status', 'invalid', 'reason', 'about_too_long');
  end if;
  if private.contains_profanity(v_about) then
    return jsonb_build_object('status', 'rejected_content');
  end if;

  -- tekrarlar atılır, sıra korunur
  select coalesce(array_agg(i order by o), '{}')
    into v_interests
  from (select i, min(o) as o from unnest(coalesce(p_interests, '{}')) with ordinality as t(i, o) group by i) d;

  if lat is not null then
    v_pt := private.make_point(lat, lng);
  end if;

  select sp.cell is not null into v_has_cell from public.social_profiles sp where sp.user_id = v_uid;
  if p_is_visible and v_pt is null and not coalesce(v_has_cell, false) then
    return jsonb_build_object('status', 'invalid', 'reason', 'location_required');
  end if;

  update public.social_profiles
     set is_visible = p_is_visible,
         about      = v_about,
         interests  = v_interests,
         cell       = coalesce(v_pt, cell)   -- trigger 2 ondalığa yuvarlar
   where user_id = v_uid;

  return jsonb_build_object('status', 'ok');
end
$$;

-- ---------------------------------------------------------------------------
-- Yetkiler: yalnızca authenticated — anon ASLA
-- ---------------------------------------------------------------------------
revoke all on all functions in schema private from public;

revoke all on function public.social_profile_me()   from public, anon, authenticated;
revoke all on function public.give_social_consent() from public, anon, authenticated;
revoke all on function public.update_social_profile(boolean, text, public.social_interest[], float8, float8) from public, anon, authenticated;

grant execute on function public.social_profile_me()   to authenticated;
grant execute on function public.give_social_consent() to authenticated;
grant execute on function public.update_social_profile(boolean, text, public.social_interest[], float8, float8) to authenticated;
