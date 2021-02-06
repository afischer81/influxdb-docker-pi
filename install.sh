#!/bin/bash

IMAGE=influxdb
#IMAGE2=influxdb-timeshift-proxy
INFLUXDB_DATA_DIR=/data/influxdb
BACKUP_DIR=/data/backup/raspi1/influxdb

function do_build {
    docker pull ${IMAGE}
    #cd image
    #docker build -t ${IMAGE2} .
    #cd -
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
        ${IMAGE} /init-influxdb.sh
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
        ${IMAGE} /init-influxdb.sh
    sudo chown -R influxdb:influxdb ${INFLUXDB_DATA_DIR}
}

function do_run {
    INFLUX_UID=$(grep influxdb /etc/passwd | cut -d: -f3)
    INFLUX_GID=$(grep influxdb /etc/group | cut -d: -f3)
    docker run \
        -d \
        --restart unless-stopped \
        -p 8086:8086 \
        --user ${INFLUX_UID}:${INFLUX_GID} \
        --name=influxdb \
        -v /etc/influxdb/influxdb.conf:/etc/influxdb/influxdb.conf \
        -v ${INFLUXDB_DATA_DIR}:/var/lib/influxdb \
        ${IMAGE} \
        -config /etc/influxdb/influxdb.conf
}

function do_reset {
    docker rm -f influxdb
    sudo rm -fr ${INFLUXDB_DATA_DIR}
}

function do_backup {
    for db in iobroker solaredge
    do
        docker exec influxdb influxd backup -portable -database ${db} -host 127.0.0.1:8088 /var/lib/influxdb
        if [ ! -d ${BACKUP_DIR}/${db} ]
        then
            sudo mkdir -p -m 755 ${BACKUP_DIR}/${db}
        fi
        sudo mv ${INFLUXDB_DATA_DIR}/$(date +'%Y%m%d')*.* ${BACKUP_DIR}/${db}
        sudo chmod 644 ${BACKUP_DIR}/${db}/$(date +'%Y%m%d')*.*
    done
}

function do_backup_full {
    timestamp=$(date +'%Y%m%d')
    docker exec influxdb influxd backup -portable -host 127.0.0.1:8088 /var/lib/influxdb
    sudo rm -f ${BACKUP_DIR}/influxdb_full.tar
    (cd ${INFLUXDB_DATA_DIR}; sudo tar -c -f ${BACKUP_DIR}/influxdb_${timestamp}.tar --no-recursion ${timestamp}*.*)
    sudo rm -f ${INFLUXDB_DATA_DIR}/${timestamp}*.*
}

function do_restore {
    backup=$1
    sudo tar -C ${INFLUXDB_DATA_DIR} -x -f ${backup}
    docker exec influxdb influxd restore -portable -host 127.0.0.1:8088 /var/lib/influxdb
    sudo rm -f ${INFLUXDB_DATA_DIR}/[0-9]*T[0-9]*.*
}

function do_exec {
    #
    # NOTE: be aware of quotes!
    #
    # e.g. create iobroker database
    #
    # ./install.sh exec CREATE USER \"iobroker\" WITH PASSWORD \'iobroker\'
    # ./install.sh exec CREATE DATABASE \"iobroker\"
    # ./install.sh exec GRANT ALL ON \"iobroker\" TO \"iobroker\"
    #
    db=$1
    shift
    docker exec influxdb /usr/bin/influx -database $db -execute "$*"
}

function do_info {
    docker exec influxdb /usr/bin/influx -execute 'SHOW USERS; SHOW DATABASES'
}

function do_metrics {
    curl -G http://localhost:8086/metrics
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
