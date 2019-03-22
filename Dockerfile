
FROM ubuntu:18.04
# FROM gcc

RUN apt-get update && apt install -y gcc-8 vim ruby build-essential

RUN gem install rspec

RUN mkdir -p /home/db

WORKDIR /home/db

# docker run -ti -v ${PWD}:/home/db db_tutorial bash