# 2.8.11 is available in CentOS7 
cmake_minimum_required(VERSION 2.8.11)

# NONE -> do not check for compilers etc
project(scheduler-worker NONE)

add_custom_target(bundle-install ALL
    bundle config --local build.nokogiri --use-system-libraries
    COMMAND bundle install --deployment
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

set(WORKER_INSTALL_DIR /opt/tester/scheduler-worker/)

INCLUDE(FindPkgConfig)
pkg_check_modules(SYSTEMD "systemd")

if (SYSTEMD_FOUND AND "${SYSTEMD_SERVICES_INSTALL_DIR}" STREQUAL "" AND "${SYSTEMD_SERVICES_CONF_DIR}" STREQUAL "")
    execute_process(COMMAND ${PKG_CONFIG_EXECUTABLE}
        --variable=systemdsystemunitdir systemd
        OUTPUT_VARIABLE SYSTEMD_SERVICES_INSTALL_DIR)
    string(REGEX REPLACE "[ \t\n]+" "" SYSTEMD_SERVICES_INSTALL_DIR
        "${SYSTEMD_SERVICES_INSTALL_DIR}")

    execute_process(COMMAND ${PKG_CONFIG_EXECUTABLE}
        --variable=systemdsystemconfdir systemd
        OUTPUT_VARIABLE SYSTEMD_SERVICES_CONF_DIR)
    string(REGEX REPLACE "[ \t\n]+" "" SYSTEMD_SERVICES_CONF_DIR
        "${SYSTEMD_SERVICES_CONF_DIR}")

elseif (NOT SYSTEMD_FOUND AND SYSTEMD_SERVICES_INSTALL_DIR AND SYSTEMD_SERVICES_CONF_DIR)
    message (FATAL_ERROR "Variable SYSTEMD_SERVICES_INSTALL_DIR and SYSTEMD_SERVICES_CONF_DIR is\
        defined, but we can't find systemd using pkg-config")
endif()

if (SYSTEMD_FOUND)
    message(STATUS "systemd services install dir: ${SYSTEMD_SERVICES_INSTALL_DIR}")
    message(STATUS "systemd config install dir: ${SYSTEMD_SERVICES_CONF_DIR}")
endif(SYSTEMD_FOUND)

set(WORKER_FILES 
    database.rb
    Gemfile
    Gemfile.lock
    LICENSE
    Rakefile
    README
    reporter.rb
    resource.rb
    cleaner.rb
    task.rb
    schedy-manager.rb
    schedy-task.rb
    schedy-transition.rb
    statistics.rb
)

set(WORKER_DIRS
    .bundle
    config
    db
    vendor
)

set(SYSTEMD_FILES
    deploy/scheduler-worker-manager.service
    deploy/scheduler-worker-init.service
    deploy/scheduler-worker-reporter.service
    deploy/scheduler-worker-cleaner-oneshot.service
)

set(LIBEXEC_FILES
    deploy/postgresql-initdb.sh
    deploy/scheduler-worker-init.sh
)

install(
  FILES ${WORKER_FILES}
  DESTINATION ${WORKER_INSTALL_DIR}
)

install(
    DIRECTORY ${WORKER_DIRS}
    USE_SOURCE_PERMISSIONS
    DESTINATION ${WORKER_INSTALL_DIR}
    PATTERN "*/vendor/cache*" EXCLUDE
)

install(
    FILES ${SYSTEMD_FILES}
    DESTINATION ${SYSTEMD_SERVICES_INSTALL_DIR}
)

install(
    FILES ${LIBEXEC_FILES}
    DESTINATION /usr/libexec/
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                GROUP_READ GROUP_EXECUTE
                WORLD_READ WORLD_EXECUTE
)

install(
    FILES deploy/database.rb
    DESTINATION ${WORKER_INSTALL_DIR}/config/
)

# vim:set softtabstop=4 shiftwidth=4 tabstop=4 expandtab:
