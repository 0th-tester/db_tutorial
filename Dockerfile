FROM ubuntu:18.04
# FROM gcc
RUN sed -i 's/archive.ubuntu.com/kr.archive.ubuntu.com/g' /etc/apt/sources.list
RUN apt-get update && apt install -y gcc-8 gdb vim ruby build-essential

RUN gem install rspec

RUN mkdir -p /home/db

WORKDIR /home/db

# docker run -ti --cap-add=SYS_PTRACE --security-opt seccomp=unconfined -v ${PWD}:/home/db  --name mydb db_tutorial /bin/bash