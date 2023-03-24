# Store the paths of the PostgreSQL configuration and extensions
# directory. These can be be obtained using pg_config --sysconfdir
# and pg_config --sharedir respectively. The ones below are the
# default paths in a Debian bookworm setup with PostgreSQL 15
# installed from the official package repository.
ARG PGCONFDIR=/etc/postgresql-common/
ARG PGEXTDIR=/usr/share/postgresql/15/extension/

# Store the path of pg_hba.conf file. This is the default path
# in a Debian bookworm setup with PostgreSQL 15 installed from
# the official package repository.
ARG HBA_FILE=/etc/postgresql/15/main/pg_hba.conf

# libpq connections can refer to a connection service defined
# in the pg_service.conf file. This file defines named
# groups of connection parameters so that applications
# can use a unique service name to connect to the database.
# Storing a service name in the PGSERVICE environment variable
# instructs libpq to use the corresponding database connection
# parameters by default. This way there is no need to enter the
# username and target database every time psql is invoked.
# See https://www.postgresql.org/docs/15/libpq-pgservice.html
# for details.
ARG PGSERVICE=coldbar

# Set coldbar version
ARG COLDBAR_VERSION=0.1

# Set pg_coldbar PostgreSQL extension version
ARG PG_COLDBAR_VERSION=0.1

# Set argc parser version
ARG ARGC_VERSION=0.12.0

FROM debian:bookworm-slim AS prod

# Inherit global arg variables
ARG PGCONFDIR
ARG PGEXTDIR
ARG HBA_FILE
ARG PGSERVICE
ARG COLDBAR_VERSION
ARG PG_COLDBAR_VERSION
ARG ARGC_VERSION

# UID and GID variables must equal
# UID and GID of the host's user
# so that ownership of files written
# to a bind mount remains unchanged.
ARG UID=1000
ARG GID=1000

ENV PGEXTDIR=$PGEXTDIR
ENV PGSERVICE=$PGSERVICE
ENV COLDBAR_VERSION=$COLDBAR_VERSION
ENV PG_COLDBAR_VERSION=$PG_COLDBAR_VERSION

# Store a copy of the connection service file inside
# the PostgreSQL configuration directory so that it
# will be found by libpq.
COPY pg_service.conf $PGCONFDIR

# Copy argc parser release archive.
# argc allows to define bash subcommands
# and parameters using tags in comments.
# argc is distributed under the MIT License.
# Visit https://github.com/sigoden/argc
# for further details.
COPY deps/argc-v${ARGC_VERSION}-x86_64-unknown-linux-musl.tar.gz /usr/local/bin/argc.tar.gz

# Copy pg_coldbar extension template control and SQL script files.
COPY src/bin/pg_coldbar.control.template ${PGEXTDIR}pg_coldbar.control.template
COPY src/bin/pg_coldbar.sql ${PGEXTDIR}pg_coldbar--${PG_COLDBAR_VERSION}.sql

# Copy coldbar CLI source files
COPY src/bin/coldbar-cli.sh /usr/local/bin/coldbar-cli/

RUN set -eux; \
# Install required packages
    apt-get update; \
    apt-get install -y --no-install-recommends \
            gdal-bin \
	    gettext-base \
            nco \
	    pgtap \
	    postgis \
	    postgresql \
	    postgresql-client \
	    postgresql-15-pgtap \
	    postgresql-postgis \
	    sudo \
    ; \
    rm -rf /var/lib/apt/lists/*; \
# Install argc parser: tag-based parameter definitions in bash
    tar --extract --file /usr/local/bin/argc.tar.gz --directory /usr/local/bin \
    && rm /usr/local/bin/argc.tar.gz; \
# Create pg_coldbar extension control file
    envsubst < ${PGEXTDIR}pg_coldbar.control.template > ${PGEXTDIR}pg_coldbar.control; \
# Create symlink to coldbar-cli.sh
    ln -s /usr/local/bin/coldbar-cli/coldbar-cli.sh /usr/local/bin/coldbar; \
# Create user non-root as sudo user
    groupadd -g ${GID} non-root; \
    useradd --create-home -u ${UID} -g ${GID} -G sudo non-root; \
# Allow non-root to run any command as superuser without authentication
    echo "non-root ALL = NOPASSWD: ALL" | sudo EDITOR="tee -a" visudo; \
# Customize the container's shell prompt.
# Set PROMPT variable in 'docker run' to display a meaningful string such as the container name
    echo 'export PS1="${debian_chroot:+($debian_chroot)}\u@${PROMPT:-coldbar_container}:\w\$ "' >> /home/non-root/.bashrc; \
# Allow local conexions to user postgres
    sed -i '0,/peer$/s//trust/' ${HBA_FILE}; \
# Setup coldbar database
    pg_ctlcluster 15 main start ;\
    psql -d postgres -c "CREATE DATABASE coldbar;" ;\
    psql -c "CREATE SCHEMA coldbar;" \
         -c "CREATE EXTENSION postgis;" \
	 -c "CREATE EXTENSION pg_coldbar;" \
	 -c "CREATE EXTENSION pgtap;" \
    ; \
    pg_ctlcluster 15 main stop

USER non-root
WORKDIR /data

FROM prod AS dev

USER root
# Copy src-monitor.sh script file.
# This bash script can be run in a separate terminal
# window during development in order to monitor changes
# in source files and automatically copy them to their
# target dir for testing purposes.
COPY src/dev/src-monitor.sh /usr/local/bin/src-monitor

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
            emacs-nox \
	    inotify-tools \
    ; \
    \
    rm -rf /var/lib/apt/lists/*

USER non-root