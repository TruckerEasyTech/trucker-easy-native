-- Bucket privado para documentos do motorista (BOL, permits, seguro, registro, CDL scans).
-- Backup na nuvem do que hoje só fica local no celular (SwiftData). Espelha o padrão de
-- 'fuel-receipts'. RLS: cada motorista só lê/escreve a própria pasta (uid). Aplicar com supabase db push.

insert into storage.buckets (id, name, public)
values ('driver-documents', 'driver-documents', false)
on conflict (id) do nothing;

drop policy if exists driver_documents_insert_own on storage.objects;
create policy driver_documents_insert_own
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'driver-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'heic', 'pdf')
  );

drop policy if exists driver_documents_select_own on storage.objects;
create policy driver_documents_select_own
  on storage.objects for select to authenticated
  using (
    bucket_id = 'driver-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists driver_documents_update_own on storage.objects;
create policy driver_documents_update_own
  on storage.objects for update to authenticated
  using (
    bucket_id = 'driver-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'driver-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'heic', 'pdf')
  );

drop policy if exists driver_documents_delete_own on storage.objects;
create policy driver_documents_delete_own
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'driver-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
