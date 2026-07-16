select format('CREATE USER ai_foundry_user PASSWORD ''postgres''')
where not exists (
    select from pg_catalog.pg_roles where rolname = 'ai_foundry_user'
)\gexec

grant ai_foundry_user to postgres;

select $$CREATE DATABASE ai_foundry
    OWNER ai_foundry_user$$
where not exists (
    select from pg_catalog.pg_database
    where datname = 'ai_foundry'
)\gexec
