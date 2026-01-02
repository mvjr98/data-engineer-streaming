FROM confluentinc/cp-kafka-connect:7.7.1

USER root

# Cria diretórios na pasta PADRÃO de componentes externos
RUN mkdir -p /usr/share/confluent-hub-components/snowflake-kafka-connector \
    && mkdir -p /usr/share/confluent-hub-components/debezium-connector-postgres

# --- 1. Instalar Snowflake Connector ---
RUN curl -L -o /usr/share/confluent-hub-components/snowflake-kafka-connector/snowflake-kafka-connector-3.4.0.jar \
    https://repo1.maven.org/maven2/com/snowflake/snowflake-kafka-connector/3.4.0/snowflake-kafka-connector-3.4.0.jar

# --- 1.1 Dependências Bouncy Castle (Necessário para Criptografia/Auth do Snowflake) ---
# Baixa o bc-fips
RUN curl -L -o /usr/share/confluent-hub-components/snowflake-kafka-connector/bc-fips-2.1.0.jar \
    https://repo1.maven.org/maven2/org/bouncycastle/bc-fips/2.1.0/bc-fips-2.1.0.jar

# Baixa o bcpkix-fips
RUN curl -L -o /usr/share/confluent-hub-components/snowflake-kafka-connector/bcpkix-fips-2.1.8.jar \
    https://repo1.maven.org/maven2/org/bouncycastle/bcpkix-fips/2.1.8/bcpkix-fips-2.1.8.jar

# --- 2. Instalar Debezium Postgres ---
RUN curl -L -o /tmp/debezium-postgres.tar.gz \
    https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.7.4.Final/debezium-connector-postgres-2.7.4.Final-plugin.tar.gz \
    && tar -xvf /tmp/debezium-postgres.tar.gz -C /usr/share/confluent-hub-components/debezium-connector-postgres --strip-components=1 \
    && rm /tmp/debezium-postgres.tar.gz

# IMPORTANTE: Garantir que o usuário do Kafka (appuser) seja dono dos arquivos
RUN chown -R appuser:appuser /usr/share/confluent-hub-components

USER appuser