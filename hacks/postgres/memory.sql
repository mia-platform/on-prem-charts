select format('CREATE USER memory_user PASSWORD ''postgres''')
where not exists (
    select from pg_catalog.pg_roles where rolname = 'memory_user'
)\gexec

grant memory_user to postgres;

select $$CREATE DATABASE memory
    OWNER memory_user$$
where not exists (
    select from pg_catalog.pg_database
    where datname = 'memory'
)\gexec

\connect memory

-- memory-service refuses to start without pgvector; creating an extension
-- needs a superuser, so it is done here rather than by the service.
create extension if not exists vector;
