select format('CREATE USER authz_user PASSWORD ''postgres''')
where not exists (
    select from pg_catalog.pg_roles where rolname = 'authz_user'
)\gexec

grant authz_user to postgres;

select $$CREATE DATABASE authz
    OWNER authz_user$$
where not exists (
    select from pg_catalog.pg_database
    where datname = 'authz'
)\gexec

\connect authz

create extension if not exists pg_trgm;
