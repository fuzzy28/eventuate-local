#!/bin/bash

set -e

if [ -z "$DOCKER_COMPOSE" ]; then
    echo setting DOCKER_COMPOSE
    export DOCKER_COMPOSE="docker-compose -f docker-compose-postgres-wal.yml -f docker-compose-new-cdc-postgres-wal.yml"
else
    echo using existing DOCKER_COMPOSE = $DOCKER_COMPOSE
fi

export GRADLE_OPTIONS="-P excludeCdcLibs=true"

./gradlew $GRADLE_OPTIONS $* :new-cdc:eventuate-local-java-cdc-sql-service:clean :new-cdc:eventuate-local-java-cdc-sql-service:assemble

. ./scripts/set-env-postgres-wal.sh

$DOCKER_COMPOSE stop
$DOCKER_COMPOSE rm --force -v

$DOCKER_COMPOSE build
$DOCKER_COMPOSE up -d postgres

# wait for Postgres
echo waiting for Postgres
./scripts/wait-for-postgres.sh
#create replication slot
docker exec $(echo ${PWD##*/} | sed -e 's/-//g')_postgres_1 /bin/sh -c "pg_recvlogical -U eventuate -d eventuate --slot test_slot --create-slot -P wal2json"

$DOCKER_COMPOSE up -d

./gradlew $GRADLE_OPTIONS :eventuate-local-java-jdbc-tests:cleanTest

./scripts/wait-for-services.sh $DOCKER_HOST_IP 8099

./gradlew $GRADLE_OPTIONS :eventuate-local-java-jdbc-tests:test

# Assert healthcheck good

echo testing restart Postgres restart scenario $(date)

docker stop  $(echo ${PWD##*/} | sed -e 's/-//g')_postgres_1

sleep 10

docker start  $(echo ${PWD##*/} | sed -e 's/-//g')_postgres_1

./scripts/wait-for-postgres.sh

./gradlew $GRADLE_OPTIONS :eventuate-local-java-jdbc-tests:cleanTest :eventuate-local-java-jdbc-tests:test

$DOCKER_COMPOSE stop
$DOCKER_COMPOSE rm --force -v


