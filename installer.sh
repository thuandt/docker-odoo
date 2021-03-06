#!/bin/bash

########################################
# Common functions
########################################

ODOO_VERSION=${1:-"latest"}
LOG_LEVEL=${2:-3}
PORT_PREFIX=${3:-9}

#TODO: switch to color.sh
if [ ${libout_color:-1} -eq 1 ]; then
  DEF_COLOR="\x1b[0m"
  BLUE="\x1b[34;01m"
  CYAN="\x1b[36;01m"
  GREEN="\x1b[32;01m"
  RED="\x1b[31;01m"
  GRAY="\x1b[37;01m"
  YELLOW="\x1b[33;01m"
  ORANGE="\x1b[1;33;01m"
fi


function log(){
    if [ -n "$INIT_LOG" ]; then
        if [[ ! -f "$INIT_LOG" ]]; then
            mkdir -p ${INIT_LOG%/*}
        fi
        echo $(date +%Y-%m-%d:%H:%M:%S) - "$@" >> "$INIT_LOG"
    fi
}


debug() {
  if [ ${LOG_LEVEL:-0} -gt 3 ]; then
    level=$(printf '%7s:' "DEBUG")
    echo -e "$CYAN${level}$DEF_COLOR $@"
    log "$level" "$@"
  fi
}

success() {
  if [ ${LOG_LEVEL:-0} -gt 2 ]; then
    level=$(printf '%7s:' "SUCCESS")
    echo -e "$GREEN${level}$DEF_COLOR $@"
    log "$level" "$@"
  fi
}

warn() {
  if [ ${LOG_LEVEL:-0} -gt 1 ]; then
    level=$(printf '%7s:' "WARN")
    echo -e "$YELLOW${level}$DEF_COLOR $@"
    log "$level" "$@"
  fi
}

info() {
  if [ ${LOG_LEVEL:-0} -gt 0 ]; then
    level=$(printf '%7s:' "INFO")
    echo -e "$GRAY${level}$DEF_COLOR $@"
    log "$level" "$@"
  fi
}

error() {
  level=$(printf '%7s:' "ERROR")
  echo -e "$RED${level}$DEF_COLOR $@"
  log "$level" "$@"
}

line () {
    printf "$BLUE"
    for n in `seq 1 $1`; do printf '#'; done
    echo -e "$DEF_COLOR"
}

title () {
    echo
    line ${#1}
    echo -e "${BLUE}$1${DEF_COLOR}"
    line ${#1}
    echo
}

die () {
  error "EXIT with status 1"
  exit 1
}

exec_timeout () {
  set +e
  local -i TIMEOUT=${2:-6} # 20min timeout
  local -i SLEEP_TIME=2
  local -i COUNT=0
  local -i STATUS=0
  local -i CURRENT_TIME=$(expr $SLEEP_TIME \* $COUNT)
  while [[ $TIMEOUT -gt $CURRENT_TIME ]]; do
      COUNT=$(expr $COUNT \+ 1)
      CURRENT_TIME=$(expr $SLEEP_TIME \* $COUNT)
      eval "$1"
      STATUS=$?
      if [[ $STATUS -eq 0 ]]; then
              return 0
              set -e
      fi
      sleep $SLEEP_TIME
  done
  return 1
  set -e
}

check_docker_compose () {
    debug "check if the port localhost:${PORT_PREFIX}022 is open for SSH..."
    sleep 1s | timeout 2s telnet localhost "${PORT_PREFIX}022" 2>/dev/null | grep SSH &>/dev/null
    nc_status=$?
    return $nc_status
}

check_status () {
    if [[ $? -ne 0 ]]; then
        error "last command failed... Abort"
        die
    fi
}

check_cpu_archi () {
    grep flags /proc/cpuinfo | grep " lm " &>/dev/null
    ret=$?
    if [ $ret -ne 0 ]; then arch_cpu="32 bit"; else arch_cpu="64 bit"; fi;
    echo $arch_cpu
}


check_archi () {
    uname -a | grep 64 &>/dev/null;
    ret=$?
    if [ $ret -ne 0 ]; then arch_os="32 bit"; else arch_os="64 bit"; fi;
    echo $arch_os
}

check_os () {
    os=`lsb_release -a 2>/dev/null | grep Desc | sed 's/.*\:\t*//'`
    echo $os
}


########################################
# Installation script
########################################

USER_HOME=$(eval echo ~${SUDO_USER})
USER_UID=`id -u $(whoami)`
USER_GID=`id -g $(whoami)`

clear

title "Odoo $ODOO_VERSION Container installer by TrobZ"
##########################################

info "check system configuration..."

cpu=`check_cpu_archi`
archi=`check_archi`
os=`check_os`

shopt -s nocasematch;

if [[ $USER_UID -eq 0 ]]; then
    error "This script can't be run by the root user"
    die
fi

if [[ $os =~ ubuntu.*14 ]]; then
    if [[ $archi == '64 bit' ]]; then
        success "Your OS is compatible with Docker !"
    elif [[ $cpu == '64 bit' ]]; then
        error "Your have a 32 bit Ubuntu version, you have to reinstall Ubuntu 14.04 64 bit to support Docker"
        die
    else
        error "Your laptop doesn't support Docker"
        die
    fi
else
    error "This script has been made to be used on Ubuntu 14.x, not on $os"
    die
fi


title "Install all dependencies"
##########################################

curl --version &>/dev/null
if [[ $? -ne 0 ]]; then
    info "Install curl lib..."
    sudo apt-get install -y curl
    check_status
fi

docker --version &>/dev/null
if [[ $? -ne 0 ]]; then
    info "Install docker..."
    curl -sSL https://get.docker.io/ubuntu/ | sudo sh
    check_status
fi

docker-compose --version &>/dev/null
if [[ $? -ne 0 ]]; then
    info "Install docker-compose..."
    curl -L https://github.com/docker/compose/releases/download/1.3.3/docker-compose-`uname -s`-`uname -m` 2>/dev/null | sudo tee /usr/local/bin/docker-compose &>/dev/null
    sudo chmod +x /usr/local/bin/docker-compose
    check_status
fi

success "All dependencies are installed"


title "Setup Odoo container"
##########################################

set -e

CONTAINER_SPACE="$USER_HOME/docker/odoo-$ODOO_VERSION"

info "Setup container folder in $CONTAINER_SPACE"
mkdir -p $CONTAINER_SPACE

info "Generate default docker-compose.yml configuration in $CONTAINER_SPACE/docker-compose.yml"

cat << EOF > $CONTAINER_SPACE/docker-compose.yml
container:

  image: trobz/odoo:$ODOO_VERSION

  environment:
    - USER_UID=$USER_UID
    - USER_GID=$USER_GID
    - ODOO_DEMO=1
    - VIM_SETUP=1

  ports:
    - "${PORT_PREFIX}069:8069"   # openerp
    - "${PORT_PREFIX}022:22"     # ssh
    - "${PORT_PREFIX}032:5432"   # pstgresql
    - "${PORT_PREFIX}011:8011"   # supervisord service monitor

  volumes:

    # SSH personal keys, allow ssh access without authentication
    - $USER_HOME/.ssh/id_rsa.pub:/usr/local/ssh/id_rsa.pub

    # postgres shared config files
    - postgres/data:/etc/postgresql/docker/data
    - postgres/config:/etc/postgresql/docker/config
    - postgres/log:/etc/postgresql/docker/log

    # supervisord log
    - supervisord/log:/var/log/supervisor

    # auto setup remote debugging for Eclipse/PyCharm
    # - map your IDE debug libs into '/usr/local/lib/pydevd'
    # ie: - /home/foo/pycharm/pycharm-debug.egg:/usr/local/lib/pydevd/pycharm-debug.egg

  mem_limit: 500000000
EOF

info "Add upstart config for Odoo"

CONTAINER_PREFIX=$(basename $CONTAINER_SPACE | sed 's/[_.\-]//g')

cat << EOF | sudo tee /etc/init/${CONTAINER_PREFIX}-container.conf &>/dev/null
description "OpenERP $ODOO_VERSION container"
author "Michel Meyer <mmeyer@trobz.com>"
start on filesystem and started docker
stop on runlevel [!2345]
respawn
script
  /usr/bin/docker start -a ${CONTAINER_PREFIX}_container_1
end script
EOF

# disable docker container auto start feature (manage it with upstart instead)
sudo sed -i 's/ -r=false//g' /etc/default/docker
sudo sed -i -r 's/.DOCKER_OPTS="(.*)"/DOCKER_OPTS="\1 -r=false"/' /etc/default/docker


sudo docker pull trobz/odoo:$ODOO_VERSION

info "Start Odoo $ODOO_VERSION container"

cd "$CONTAINER_SPACE"
sudo docker-compose stop container &>/dev/null
sudo docker-compose rm --force container &>/dev/null
sudo docker-compose up container &
check_status

# docker-compose is checking if a service is listening on localhost:port, checking timeout=6s, retry=200,
# so test will run during 20min
exec_timeout 'check_docker_compose' 1200
RETRY_STATUS=$?

if [[ $RETRY_STATUS -eq 0 ]]; then
    info "Stop the container and restart it in background"
    sudo docker-compose stop &>/dev/null
    sudo docker-compose up -d
    check_status
else
    error "Timeout, unable to connect to the container SSH port after 20min..."
    error "Please, try to start the container manually with the command:"
    error "cd $CONTAINER_SPACE ; sudo docker-compose up"
    die
fi

exec_timeout 'check_docker_compose' 1200
RETRY_STATUS=$?

if [[ $RETRY_STATUS -eq 0 ]]; then
    read -r -d '' msg << EOF
Odoo $ODOO_VERSION container setup finished !

Access to:
- Odoo $ODOO_VERSION demo: http://localhost:${PORT_PREFIX}069/
- SSH into the container: ssh -p ${PORT_PREFIX}022 openerp@localhost
- PostgreSQL: openerp:openerp@localhost:${PORT_PREFIX}032
- Supervisor web panel: http://openerp:openerp@localhost:${PORT_PREFIX}011/

Enjoy !
EOF
    success "$msg"
else
    error "Timeout, unable to connect to the container SSH port after 20min..."
    error "Please, try to start the container manually with the command:"
    error "cd $CONTAINER_SPACE ; sudo docker-compose up"
    die
fi



