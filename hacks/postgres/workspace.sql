select format('CREATE USER workspace_user PASSWORD ''postgres''')
where not exists (
    select from pg_catalog.pg_roles where rolname = 'workspace_user'
)\gexec

grant workspace_user to postgres;

select $$CREATE DATABASE workspace
    OWNER workspace_user$$
where not exists (
    select from pg_catalog.pg_database
    where datname = 'workspace'
)\gexec
