-- Cleanup for legacy Prisma/Express database objects.
-- Use this only if the current app is the Flutter/Supabase app and the old
-- React/Express/Prisma stack is retired.
--
-- Kept because Flutter/Supabase code references them:
-- audit_log, burial_record, cemetery_lot, cemetery_map, lot_markers,
-- lot_ownership, path_edges, path_nodes, payment_requests, section,
-- transaction_history, users, visitor_log.
--
-- Removed if present:
-- "BranchPathEdge", "BranchPathNode", "BranchSection", "CemeteryBranch",
-- "VisitPass", "VisitorLog", "BurialRecord", "CemeteryLot", "Section",
-- "Visitor", and enum "Role".

begin;

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

drop type if exists public."Role" cascade;

commit;
