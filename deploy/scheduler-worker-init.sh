#!/bin/bash

# some vars which we need globaly
DBM_OK=5
CU_OK=5
CDB_OK=5
RESOURCE_SQL="/opt/tester/scheduler-worker/resources.sql"

function upsert_resources()
{
    if [ -f ${RESOURCE_SQL} ]; then
        echo "Found '${RESOURCE_SQL}', run it with psql..."
        set -e
        su -c "/usr/bin/psql --echo-queries --file=${RESOURCE_SQL} scheduler_worker" tester
        set +e
    else
        echo "'${RESOURCE_SQL}' does not exists..."
    fi
}


pushd /opt/tester/scheduler-worker/
su -c "RAILS_ENV=production bundle exec rake db:migrate" tester
DBM_OK=$?
popd

if [ $DBM_OK = 0 ]; then
    echo "All fine so far, lets check for a '${RESOURCE_SQL}' file..."
    upsert_resources
    exit $DBM_OK
else
    HAS_ROLE=$(su -c "/usr/bin/psql -A -t -c \"select count(*) from pg_user where usename='tester'\"" postgres 2>/dev/null || echo "42")
    if [ $HAS_ROLE = 0 ]; then
        echo "No role 'tester' in postgresql, create role..."
        su -c "/usr/bin/createuser --echo --login tester" postgres
        CU_OK=$?
    elif [ $HAS_ROLE = 42 ]; then
        echo "Is postgresql not running? giving up!"
        exit 42
    fi

    if [ $CU_OK = 0 ]; then
        HAS_DB=$(su -c "/usr/bin/psql -A -t -c \"select count(*) from pg_database where datname='scheduler_worker' \"" postgres 2>/dev/null || echo "42")
        if [ $HAS_DB = 0 ]; then
            echo "No db 'scheduler_worker' in postgresql, create db..."
            su -c "/usr/bin/createdb --echo --owner=tester scheduler_worker" postgres
            CDB_OK=$?
        elif [ $HAS_ROLE = 42 ]; then
            echo "Is postgresql not running? giving up!"
            exit 42
        fi

        if [ $CDB_OK = 0 ]; then
            echo "Now db:migrate should work, try again..."
            pushd /opt/tester/scheduler-worker/
            su -c "RAILS_ENV=production bundle exec rake db:migrate" tester
            DBM_OK=$?
            popd

            if [ $DBM_OK = 0 ]; then
                upsert_resources
                echo "all fine now, scheduler can start..."
                exit 0
            else
                echo "db:migrate still fails, giving up!"
                exit $DBM_OK
            fi
        else
            echo "/usr/bin/createdb failed!"
            exit $CDB_OK
        fi
    else
        echo "/usr/bin/createuser failed!"
        exit $CU_OK
    fi
fi

# should never be reached!
exit 1

# vim:set softtabstop=4 shiftwidth=4 tabstop=4 expandtab:
