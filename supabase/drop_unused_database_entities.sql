-- Drop unused legacy database entities.
--
-- Static repo audit notes:
-- - The current Flutter/Supabase app uses snake_case public tables such as
--   users, cemetery_lot, burial_record, graves, visitor_log, cemetery_map,
--   lot_markers, path_nodes, path_edges, lot_ownership, payment_requests,
--   transaction_history, audit_log, burial_informants, and cemetery_map_features.
-- - Cemetery sections/branches have been replaced by the QGIS lot block column:
--   public.cemetery_lot.block_number. Lots are inside blocks, and graves are
--   inside lots. Keep path_nodes and path_edges; they are still used for routing.
-- - The PascalCase tables below come from the old React/Express/Prisma stack
--   under server/ and client/. Do NOT run this if that old npm app is still
--   using the same database.
-- - QGIS staging tables are intentionally kept:
--   lot_import_staging and map_feature_import_staging.
--
-- First run only the preview SELECT below if you want to see which legacy
-- objects still exist before dropping them.

select
  n.nspname as schema_name,
  c.relname as object_name,
  case c.relkind
    when 'r' then 'table'
    when 'v' then 'view'
    when 'm' then 'materialized_view'
    else c.relkind::text
  end as object_type,
  c.reltuples::bigint as estimated_rows
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r', 'v', 'm')
  and c.relname in (
    'BranchPathEdge',
    'BranchPathNode',
    'BranchSection',
    'CemeteryBranch',
    'VisitPass',
    'VisitorLog',
    'BurialRecord',
    'CemeteryLot',
    'Section',
    'Visitor',
    'branch',
    'branches',
    'cemetery_branch',
    'section',
    'sections',
    'walkways',
    '_prisma_migrations'
  )
union all
select
  n.nspname as schema_name,
  t.typname as object_name,
  'type' as object_type,
  null::bigint as estimated_rows
from pg_type t
join pg_namespace n on n.oid = t.typnamespace
where n.nspname = 'public'
  and t.typname = 'Role'
order by object_type, object_name;

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Drop child tables first, then parents.
drop table if exists public."BranchPathEdge" cascade;
drop table if exists public."BranchPathNode" cascade;
drop table if exists public."BranchSection" cascade;
drop table if exists public."CemeteryBranch" cascade;

drop table if exists public."VisitPass" cascade;
drop table if exists public."VisitorLog" cascade;
drop table if exists public."BurialRecord" cascade;
drop table if exists public."CemeteryLot" cascade;
drop table if exists public."Section" cascade;
drop table if exists public."Visitor" cascade;

-- Prisma migration metadata is unused once the Prisma stack is retired.
drop table if exists public._prisma_migrations cascade;

drop type if exists public."Role" cascade;

commit;

-- Block-model cleanup for the current Supabase schema.
-- Run this only after deploying the app version that no longer queries
-- section:section_id or branch:branch_id. It keeps block_number on cemetery_lot
-- as the block source of truth.

select
  to_regclass('public.cemetery_lot') as cemetery_lot,
  to_regclass('public.section') as old_section_table,
  to_regclass('public.sections') as old_sections_table,
  to_regclass('public.branch') as old_branch_table,
  to_regclass('public.branches') as old_branches_table,
  to_regclass('public.cemetery_branch') as old_cemetery_branch_table,
  to_regclass('public.walkways') as old_walkways_table;

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

alter table if exists public.cemetery_lot
  drop constraint if exists cemetery_lot_section_id_fkey;

alter table if exists public.cemetery_lot
  drop column if exists section_id;

drop table if exists public.section cascade;
drop table if exists public.sections cascade;
drop table if exists public.branch cascade;
drop table if exists public.branches cascade;
drop table if exists public.cemetery_branch cascade;
drop table if exists public.walkways cascade;

commit;

-- Optional cleanup only after you are completely done with QGIS CSV imports.
-- These are not runtime app tables, but the current Supabase import scripts use
-- them, so leave these commented unless you deliberately want to remove staging.
--
-- drop table if exists public.map_feature_import_staging cascade;
-- drop table if exists public.lot_import_staging cascade;
