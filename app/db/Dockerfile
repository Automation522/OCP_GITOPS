FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf install -y postgresql && microdnf clean all

WORKDIR /opt/db
COPY seed.sql ./seed.sql
COPY init.sh ./init.sh
RUN chmod +x ./init.sh

ENTRYPOINT ["/opt/db/init.sh"]
