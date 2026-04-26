FROM ubuntu:24.04

LABEL maintainer="Erling G. M. Kristiansen <egkristi@gmail.com>"
LABEL description="DNS benchmark tool using dnsperf and custom scripts"

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      dnsutils \
      dnsperf \
      curl \
      ca-certificates \
      iproute2 \
      procps \
      python3 \
      python3-pip \
      jq \
      bc \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY benchmark.sh /usr/local/bin/benchmark
RUN chmod +x /usr/local/bin/benchmark

COPY resolvers.txt /etc/namebench/resolvers.txt

WORKDIR /results

ENTRYPOINT ["benchmark"]
CMD ["--help"]
