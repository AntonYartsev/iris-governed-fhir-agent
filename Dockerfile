# syntax=docker/dockerfile:1
# The AI Hub EAP build is not on a public registry yet!
# Download the tar.gz from https://evaluation.intersystems.com/Eval/early-access/AIHub
#
#   x86_64:  docker load < irishealth-community-2026.3.0AI.126.0-docker.tar.gz
#   arm64:   docker load < irishealth_arm64-community-2026.3.0AI.126.0-docker.tar.gz
#
# then docker load prints the tag it created. you may override the default below with it:
#
#   IRIS_IMAGE=<that tag> docker compose up -d --build
#
ARG IRIS_IMAGE=intersystems/irishealth-community:2026.3.0AI.126.0
FROM $IRIS_IMAGE

WORKDIR /home/irisowner/dev

ARG NAMESPACE="IRISAPP"

ENV IRISUSERNAME="_SYSTEM"
ENV IRISPASSWORD="SYS"
ENV IRISNAMESPACE=$NAMESPACE
ENV PYTHON_PATH=/usr/irissys/bin/
ENV PYTHONPATH="/usr/irissys/lib/python"
ENV PATH="/usr/irissys/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/irisowner/bin"

COPY --chmod=755 . /home/irisowner/dev

# Everything: classes, FHIR endpoint, Synthea data, MCP web app - is baked into the image at build time
RUN iris start IRIS && \
    iris merge IRIS /home/irisowner/dev/merge.cpf && \
    iris session IRIS < /home/irisowner/dev/iris.script && \
    iris stop IRIS quietly
