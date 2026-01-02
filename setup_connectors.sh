#!/bin/bash
CONNECT_URL="http://localhost:8083"

# Função para verificar se o Kafka Connect está pronto
wait_for_connect() {
    echo "⏳ Aguardando Kafka Connect iniciar em $CONNECT_URL..."
    while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' $CONNECT_URL/)" != "200" ]]; do
        sleep 5
    done
    echo "✅ Kafka Connect está online!"
}

# Função para criar um conector
create_connector() {
    config_file=$1
    echo "🚀 Criando conector a partir de: $config_file"
    curl -X POST -H "Content-Type: application/json" --data @$config_file $CONNECT_URL/connectors
    echo -e "\n"
}

wait_for_connect
# Certifique-se que os JSONs existem nestes caminhos
create_connector "kafka/connectors-config/source-postgres.json"
create_connector "kafka/connectors-config/sink-snowflake.json"
echo "🎉 Todos os conectores foram configurados!"