-- Mama Haritası — 0010: Storage — `photos` bucket'ı
--
-- * Bucket public: dosyalar /storage/v1/object/public/photos/... URL'iyle herkesçe okunur
--   (public okuma RLS gerektirmez; anon için listeleme politikası bilinçli olarak YOK — kullanıcı
--   klasörlerinin numaralandırılmasını önler).
-- * Yükleme yalnızca kendi klasörüne: {auth.uid()}/{uuid}.jpg
-- * İstemci yüklemeden önce EXIF/GPS siler, uzun kenarı 1600 px'e küçültür (PRD 7.1).

do $$
declare
  v_has_public boolean;
  v_has_limits boolean;
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise notice 'storage şeması yok, photos bucket atlandı';
    return;
  end if;

  select exists (select 1 from information_schema.columns
                 where table_schema = 'storage' and table_name = 'buckets' and column_name = 'public')
    into v_has_public;
  select exists (select 1 from information_schema.columns
                 where table_schema = 'storage' and table_name = 'buckets' and column_name = 'allowed_mime_types')
    into v_has_limits;

  if v_has_public then
    execute $q$insert into storage.buckets (id, name, public) values ('photos', 'photos', true)
               on conflict (id) do update set public = true$q$;
  else
    execute $q$insert into storage.buckets (id, name) values ('photos', 'photos')
               on conflict (id) do nothing$q$;
  end if;

  if v_has_limits then
    execute $q$update storage.buckets
                  set file_size_limit = 5242880,
                      allowed_mime_types = array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
                where id = 'photos'$q$;
  end if;

  execute 'drop policy if exists photos_insert_own on storage.objects';
  execute 'drop policy if exists photos_select_own on storage.objects';
  execute 'drop policy if exists photos_update_own on storage.objects';
  execute 'drop policy if exists photos_delete_own on storage.objects';

  execute $q$create policy photos_insert_own on storage.objects
               for insert to authenticated
               with check (bucket_id = 'photos'
                           and (storage.foldername(name))[1] = (select auth.uid())::text)$q$;
  -- kendi klasörünü listeleyebilir (upsert/overwrite için de gerekli)
  execute $q$create policy photos_select_own on storage.objects
               for select to authenticated
               using (bucket_id = 'photos'
                      and (storage.foldername(name))[1] = (select auth.uid())::text)$q$;
  execute $q$create policy photos_update_own on storage.objects
               for update to authenticated
               using (bucket_id = 'photos'
                      and (storage.foldername(name))[1] = (select auth.uid())::text)
               with check (bucket_id = 'photos'
                           and (storage.foldername(name))[1] = (select auth.uid())::text)$q$;
  execute $q$create policy photos_delete_own on storage.objects
               for delete to authenticated
               using (bucket_id = 'photos'
                      and (storage.foldername(name))[1] = (select auth.uid())::text)$q$;
end
$$;
