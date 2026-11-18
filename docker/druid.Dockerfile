FROM apache/druid:38.0.0

FROM alpine:3.21

RUN apk --update add bash perl curl openjdk21-jre-headless postgresql-client

COPY --from=0 /opt/druid/ /opt/druid/

COPY druid.properties /opt/druid/conf/druid/single-server/nano-quickstart/_common/common.runtime.properties
COPY druid.conf /opt/druid/conf/supervise/single-server/nano-quickstart.conf
COPY druid.sh /opt/druid/druid.sh

# The nano quickstart runs two tasks at a time, but every SQL-based ingestion
# or deep storage query takes two (a controller and a worker), so integration
# tests that ingest concurrently would queue behind, or deadlock on, each
# other. Fail the build if the quickstart config stops matching.
ARG WORKER_CAPACITY=8
RUN sed -i "s/^druid.worker.capacity=.*/druid.worker.capacity=${WORKER_CAPACITY}/" \
      /opt/druid/conf/druid/single-server/nano-quickstart/middleManager/runtime.properties && \
    grep -qx "druid.worker.capacity=${WORKER_CAPACITY}" \
      /opt/druid/conf/druid/single-server/nano-quickstart/middleManager/runtime.properties

WORKDIR /opt/druid

EXPOSE 8888/tcp
EXPOSE 8082/tcp

CMD ["bash", "./druid.sh"]
