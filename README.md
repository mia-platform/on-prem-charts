# Requisiti

- **Un IdP**: identity provider esterno (o Keycloak già esistente del cliente) da federare con il Keycloak gestito da Mia-Platform.
- **Un Postgres**: istanza PostgreSQL esterna raggiungibile dal cluster, usata per Keycloak e per i servizi che richiedono persistenza relazionale.
- **Un ImagePull**: credenziali per scaricare le immagini dal registry privato (sarà quello Mia-Platform).
- Un Kafka (comunque opzionale, richiesto solo da Catalog)
- Un Mongo (per la Console)

## IdP

Va provisionato un client OIDC lato IdP del cliente, che rappresenti la federazione con Mia-Platform ("Mia Federated Authorization"). Serve:
- `client_id`
- un meccanismo di autenticazione client: `client_secret` **oppure** `private_key_jwt`
- gli endpoint OIDC standard (issuer / authorization / token / userinfo / jwks), reperibili dalla `openid-configuration` dell'IdP

## Postgres

Per ciascun servizio serve uno user + un database dedicati:

- **[keycloak]**: user + db per l'istanza Keycloak.
- **[homepage][rbac_management]**: user + db per il servizio `rbac-management`; utilizza solo schemi nominati (nessun uso dello schema `public`).
- **[catalog / ai-foundry][adk-be-app]**: user + db per `adk-be-app`; utilizza solo lo schema `public`.
  > Nota: `adk-be-app` non fa parte del chart `services` (homepage), ma dei chart Catalog e AI Foundry — l'etichetta `[homepage]` va corretta.

## Image pull

Serve un secret di tipo `dockerconfigjson` (o equivalente), da referenziare nei deployment su tutto il cluster per autorizzare il pull delle immagini dal registry privato.

### Preparation

1. Provisioniamo out-of-the-box il `dockerconfigjson` come secret locale nel cluster.
2. Prepariamo Postgres (creazione user/db) tramite script eseguiti direttamente sul pod.
3. Una volta che Postgres è up & running, si passa alla preparazione dei **Shared services & tools**:
   1. Installazione di **Keycloak**.
   2. Installazione di **keycloak-realm-management**.
   3. Configurazione e deploy del **master realm**.
   4. Il super admin si aggiunge come admin permanente all'interno del master realm (rimpiazzando l'account bootstrap temporaneo); si procede quindi con i realm di **product** ed **extensibility**.