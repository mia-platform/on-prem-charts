select format('CREATE USER catalog_user PASSWORD ''postgres''')
where not exists (
    select from pg_catalog.pg_roles where rolname = 'catalog_user'
)\gexec

grant catalog_user to postgres;

select $$CREATE DATABASE catalog
    OWNER catalog_user$$
where not exists (
    select from pg_catalog.pg_database
    where datname = 'catalog'
)\gexec
