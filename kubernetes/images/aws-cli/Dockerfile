FROM quay.io/concur_platform/alpine:3.5

RUN apk-install less groff python py2-pip jq curl bash \
  && pip install --upgrade pip \
  && pip install --upgrade awscli s3cmd

COPY get-metadata /opt/bin/get-metadata
