#!/bin/bash

# Copyright (C) 2017 Rogier Wessel - All Rights Reserved
# https://github.com/blijblijblij/cd-demo

clear

echo "tachikoma" | figlet | lolcat
echo "'friendly robot at your disposal'" | lolcat
echo ""

#############################################################################
# Consts
#############################################################################
# version
declare -r VERSION="0.0.1"
# colors
declare -r LIGHT_BLUE="\033[1;34m"
declare -r NO_COLOR="\033[0m"

MESOS_MASTER_1=$(docker-machine ip demo)
CLUSTERNAME=demo
CLUSTER_SECRET=$(pwgen -s 32 | head)
ZK=${MESOS_MASTER_1}:2181
SLAVE_IP=${MESOS_MASTER_1}

#############################################################################
# Utils
#############################################################################

spin () {
  declare -i rotations=5
  delay=0.2
  for i in `seq 0 $rotations`; do
    for char in '|' '/' '-' '\'; do
      printf ${LIGHT_BLUE}$char
      sleep $delay
      printf "\b\b"
    done
  done
  printf ${NO_COLOR}
}

show_help () {
  cat ./MANUAL | less
}

#############################################################################
# Docker machine
#############################################################################
create_docker_machine () {
  echo "---> create docker machine demo" | lolcat
  spin
  docker-machine create -d virtualbox \
  --virtualbox-cpu-count "2" --virtualbox-memory "8192" \
  --virtualbox-disk-size "50000" demo;
  echo "---> created docker machine demo" | lolcat
}

delete_docker_machine() {
  echo "---> remove docker-machine demo" | lolcat
  spin
  docker-machine rm -f demo > /dev/null
  echo "---> removed docker-machine demo" | lolcat
}

#############################################################################
# Mesos
#############################################################################
start_mesos () {
  echo "---> start mesos" | lolcat
  docker-machine env demo
  eval "$(docker-machine env demo)"

  echo "---> clean dockers" | lolcat
  docker kill $(docker ps -a -q)
  docker rm $(docker ps -a -q)

  echo "---> start zookeeper" | lolcat
  spin
  docker run -d \
  -e MYID=1 \
  -e SERVERS=${MESOS_MASTER_1} \
  --name=zookeeper --net=host --restart=always \
  mesoscloud/zookeeper:3.4.6-ubuntu-14.04;

  echo "---> start master" | lolcat
  spin
  docker run -d \
  -e MESOS_CLUSTER=${CLUSTERNAME} \
  -e MESOS_HOSTNAME=${MESOS_MASTER_1} \
  -e MESOS_IP=${MESOS_MASTER_1} \
  -e MESOS_QUORUM=1 \
  -e MESOS_ZK=zk://${ZK}/mesos \
  -e MESOS_REGISTRY=in_memory \
  -e MESOS_LOG_DIR=/var/log/mesos \
  -e MESOS_WORK_DIR=/var/tmp/mesos \
  -v "/var/log/mesos:/var/log/mesos" \
  -v "/var/tmp/mesos:/var/tmp/mesos" \
  --name master --net host --restart always  \
  mesosphere/mesos-master:1.4.0;

  echo "---> start marathon" | lolcat
  spin
  docker run -d \
  -e MARATHON_HOSTNAME=${MESOS_MASTER_1} \
  -e MARATHON_HTTPS_ADDRESS=${MESOS_MASTER_1} \
  -e MARATHON_HTTP_ADDRESS=${MESOS_MASTER_1} \
  -e MARATHON_MASTER=zk://${ZK}/mesos \
  -e MARATHON_ZK=zk://${ZK}/marathon \
  -e MARATHON_EVENT_SUBSCRIBER="http_callback" \
  -e MARATHON_TASK_LAUNCH_TIMEOUT="300000" \
  --name marathon --net host --restart always \
  mesosphere/marathon:v1.4.8;

  echo "---> start chronos" | lolcat
  spin
  docker run -d \
  -e PORT0=4400 \
  -e PORT1=8081 \
  --name chronos --restart always \
  -p 4400:4400 \
  -p 8081:8081 \
  mesosphere/chronos:v3.0.2 \
  --zk_hosts=${MESOS_MASTER_1}:2181 \
  --master=zk://${MESOS_MASTER_1}:2181/mesos \
  --hostname=${MESOS_MASTER_1} \
  --mesos_role=private \
  --mesos_framework_name=chronos;

  echo "---> start agent" | lolcat
  spin
  docker run -d \
  -e MESOS_HOSTNAME=${SLAVE_IP} \
  -e MESOS_IP=${SLAVE_IP} \
  -e LIBPROCESS_IP=${SLAVE_IP} \
  -e MESOS_MASTER=zk://${ZK}/mesos \
  -e MESOS_LOG_DIR=/var/log/mesos \
  -e MESOS_LOGGING_LEVEL=INFO \
  -e MESOS_CONTAINERIZERS="docker,mesos" \
  -e MESOS_EXECUTOR_REGISTRATION_TIMEOUT="5mins" \
  -e MESOS_EXECUTOR_SHUTDOWN_GRACE_PERIOD="90secs" \
  -e MESOS_DOCKER_STOP_TIMEOUT="60secs" \
  -e MESOS_PORT="5051" \
  -e MESOS_WORK_DIR=/tmp/mesos \
  -e MESOS_LAUNCHER=posix \
  -e MESOS_SYSTEMD_ENABLE_SUPPORT=false \
  -v /var/log/mesos:/var/log/mesos \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  -v /usr/local/bin/docker:/usr/bin/docker \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --name agent --net host --privileged --restart always \
  mesosphere/mesos-slave:1.4.0;

  echo "---> start proxy" | lolcat
  docker run -d \
  -e MARATHON_IPS="${MESOS_MASTER_1}" \
  --name proxy --net host --pid host --restart always \
  indigodatacloud/haproxy-marathon-bridge
}

#############################################################################
# Marathon
#############################################################################
deploy_on_marathon() {
  echo "---> deploy on marathon" | lolcat
  spin
  curl -X POST "http://${MESOS_MASTER_1}:8080/v2/apps?force=true" -d @"./marathon/teamcity-server.json" -H "Content-type: application/json";
  spin
  curl -X POST "http://${MESOS_MASTER_1}:8080/v2/apps?force=true" -d @"./marathon/teamcity-agent.json" -H "Content-type: application/json";

}
#############################################################################
# Base
#############################################################################

case $1 in
  "-c"|"--create-docker-machine"|"create")
    create_docker_machine
  ;;
  "-d"|"--delete-docker-machine"|"delete")
    delete_docker_machine
  ;;
  "-h"|"--help"|"help")
    show_help
  ;;
  "--start-mesos"|"mesos")
    start_mesos
  ;;
  "--deploy-marathon"|"marathon")
    deploy_on_marathon
  ;;
  *)
    echo "run 'bin/tachikoma.sh -h' for help"
  ;;
esac
