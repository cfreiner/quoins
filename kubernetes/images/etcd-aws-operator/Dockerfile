FROM quay.io/concur_platform/alpine:3.5

RUN apk-install curl wget bash jq python py2-pip \
  && pip install --upgrade pip \
  && pip install --upgrade awscli

COPY etcd-aws-operator /etcd-aws-operator
COPY etcd-aws-proxy /etcd-aws-proxy

VOLUME ["/var/run/coreos"]
