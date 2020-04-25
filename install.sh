#!/bin/bash

INFLUXDB_DATA_DIR=/data/influxdb

function do_build {
    docker pull influxdb
}

function do_init {
    sudo useradd -rs /bin/false influxdb
    if [ ! -d /etc/influxdb ]
    then
        sudo mkdir -p /etc/influxdb
        docker run --rm influxdb influxd config | sudo tee /etc/influxdb/influxdb.conf > /dev/null
        sudo chown influxdb:influxdb /etc/influxdb/
    fi
    docker run --rm -e INFLUXDB_HTTP_AUTH_ENABLED=true \
        -e INFLUXDB_ADMIN_USER=admin \
        -e INFLUXDB_ADMIN_PASSWORD=admin123 \
        -v /var/lib/influxdb:/var/lib/influxdb \
        -v /etc/influxdb/scripts:/docker-entrypoint-initdb.d \
        influxdb /init-influxdb.sh
    sudo rm -fr /var/lib/influxdb
    if [ -d ${INFLUXDB_DATA_DIR} ]
    then
        sudo rm -fr ${INFLUXDB_DATA_DIR}
    fi
    sudo mkdir -p ${INFLUXDB_DATA_DIR}
    sudo chown influxdb:influxdb ${INFLUXDB_DATA_DIR}
    sudo mkdir -p /etc/influxdb/scripts
    sudo cp influxdb-init.iql /etc/influxdb/scripts
    docker run --rm -e INFLUXDB_HTTP_AUTH_ENABLED=true \
        -e INFLUXDB_ADMIN_USER=admin \
        -e INFLUXDB_ADMIN_PASSWORD=admin123 \
        -v ${INFLUXDB_DATA_DIR}:/var/lib/influxdb \
        -v /etc/influxdb/scripts:/docker-entrypoint-initdb.d \
        influxdb /init-influxdb.sh
    sudo chown -R influxdb:influxdb ${INFLUXDB_DATA_DIR}
}

function do_run {
    INFLUX_UID=$(grep influxdb /etc/passwd | cut -d: -f3)
    INFLUX_GID=$(grep influxdb /etc/group | cut -d: -f3)
    docker run \
        -d \
        -p 8086:8086 \
        --user ${INFLUX_UID}:${INFLUX_GID} \
        --name=influxdb \
        --restart unless-stopped \
        -v /etc/influxdb/influxdb.conf:/etc/influxdb/influxdb.conf \
        -v ${INFLUXDB_DATA_DIR}:/var/lib/influxdb \
        influxdb \
        -config /etc/influxdb/influxdb.conf
}

function do_exec {
    docker exec influxdb /usr/bin/influx -execute "$*"
}

function do_info {
    docker exec influxdb /usr/bin/influx -execute 'SHOW USERS; SHOW DATABASES'
}

function do_shell {
    docker exec -it influxdb /bin/bash
}

function do_test {
    curl -G http://localhost:8086/query --data-urlencode "q=SHOW DATABASES"
}

task=$1
shift
do_$task $*
