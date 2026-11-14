FROM apache/druid:38.0.0

FROM alpine:3.21

RUN apk --update add bash perl curl openjdk21-jre-headless postgresql-client

COPY --from=0 /opt/druid/ /opt/druid/

COPY druid.properties /opt/druid/conf/druid/single-server/nano-quickstart/_common/common.runtime.properties
COPY druid.conf /opt/druid/conf/supervise/single-server/nano-quickstart.conf
COPY druid.sh /opt/druid/druid.sh

WORKDIR /opt/druid

EXPOSE 8888/tcp
EXPOSE 8082/tcp

CMD ["bash", "./druid.sh"]
