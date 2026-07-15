select format('CREATE USER keycloak_user PASSWORD ''postgres''')
where not exists (
    select from pg_catalog.pg_roles where rolname = 'keycloak_user'
)\gexec

grant keycloak_user to postgres;

select $$CREATE DATABASE keycloak
    OWNER keycloak_user$$
where not exists (
    select from pg_catalog.pg_database
    where datname = 'keycloak'
)\gexec
