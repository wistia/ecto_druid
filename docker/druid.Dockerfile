FROM apache/druid:38.0.0

FROM alpine:3.21

RUN apk --update add bash perl curl openjdk21-jre-headless postgresql-client

COPY --from=0 /opt/druid/ /opt/druid/

COPY druid.properties /opt/druid/conf/druid/single-server/nano-quickstart/_common/common.runtime.properties
COPY druid.conf /opt/druid/conf/supervise/single-server/nano-quickstart.conf
COPY druid.sh /opt/druid/druid.sh
# Runs in place of the quickstart's MiddleManager (see druid.conf)
COPY indexer/ /opt/druid/conf/druid/single-server/nano-quickstart/indexer/

# The Coordinator looks for newly published segments, and assigns them to
# Historicals, every five seconds in the quickstart, so every ingestion waited
# ~7s for its segments to load. Fail the build if the quickstart config stops
# matching.
ARG COORDINATOR=/opt/druid/conf/druid/single-server/nano-quickstart/coordinator-overlord/runtime.properties
RUN sed -i -e "s/^druid.coordinator.period=.*/druid.coordinator.period=PT1S/" \
      -e "s/^druid.manager.segments.pollDuration=.*/druid.manager.segments.pollDuration=PT1S/" \
      "$COORDINATOR" && \
    grep -qx "druid.coordinator.period=PT1S" "$COORDINATOR" && \
    grep -qx "druid.manager.segments.pollDuration=PT1S" "$COORDINATOR"

WORKDIR /opt/druid

EXPOSE 8888/tcp
EXPOSE 8082/tcp

CMD ["bash", "./druid.sh"]
