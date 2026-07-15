select format('CREATE USER adk_user PASSWORD ''postgres''')
where not exists (
    select from pg_catalog.pg_roles where rolname = 'adk_user'
)\gexec

grant adk_user to postgres;

select $$CREATE DATABASE adk
    OWNER adk_user$$
where not exists (
    select from pg_catalog.pg_database
    where datname = 'adk'
)\gexec
