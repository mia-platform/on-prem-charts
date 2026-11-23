select format('CREATE USER temporal_user PASSWORD ''postgres''')
where not exists (
    select from pg_catalog.pg_roles where rolname = 'temporal_user'
)\gexec

grant temporal_user to postgres;

select $$CREATE DATABASE temporal
    OWNER temporal_user$$
where not exists (
    select from pg_catalog.pg_database
    where datname = 'temporal'
)\gexec

select $$CREATE DATABASE temporal_visibility
    OWNER temporal_user$$
where not exists (
    select from pg_catalog.pg_database
    where datname = 'temporal_visibility'
)\gexec
