select format('CREATE USER litellm_user PASSWORD ''postgres''')
where not exists (
    select from pg_catalog.pg_roles where rolname = 'litellm_user'
)\gexec

grant litellm_user to postgres;

select $$CREATE DATABASE litellm
    OWNER litellm_user$$
where not exists (
    select from pg_catalog.pg_database
    where datname = 'litellm'
)\gexec
