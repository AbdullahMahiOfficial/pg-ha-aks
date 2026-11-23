FROM postgres:16-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-psycopg2 \
    patroni pgbackrest curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

USER postgres
ENTRYPOINT ["patroni", "/etc/patroni/patroni.yml"]
