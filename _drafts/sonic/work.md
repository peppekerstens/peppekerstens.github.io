
```sh
sudo su

docker load -i ./docker-sonic-vs.g

docker swarm init
Swarm initialized: current node (gk64x0hjef87wt54ct0hj95o8) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-5h1mw8z9gupap2tc7xw56u15x0nhmxg3z42l23ek5admf8uyh9-b39ktrvc1t9bmlcb2vvkn4p5i 192.168.65.3:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.

docker image pull ubuntu

docker network create --driver=overlay sonic --attachable
docker network create --driver=bridge host1 --subnet=192.168.1.0/24
docker network create --driver=bridge host2 --subnet=192.168.2.0/24
docker network create --driver=bridge management

docker run --network=management --network=host1 --network=sonic --privileged --name switch1 -it -d  docker-sonic-vs:latest
docker run --network=management --network=host2 --network=sonic --privileged --name switch2 -it -d  docker-sonic-vs:latest
docker run --network=host1 --privileged --name host1 -it -d ubuntu:latest 
docker run --network=host2 --privileged --name host2 -it -d ubuntu:latest

```

```sh
docker container stop host1
docker rm host1
docker run -tid --network=host1 --name host1 --privileged -dit -p 2222:22 ubuntu:lastest
docker exec -it host1 /bin/bash
```