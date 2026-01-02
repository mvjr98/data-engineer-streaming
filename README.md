# 🚀 Real-Time CDC Pipeline: PostgreSQL to Snowflake

Este projeto implementa um pipeline de dados em tempo real utilizando **Change Data Capture (CDC)**. Ele captura transações de um banco operacional PostgreSQL (OLTP), transmite via Kafka e ingere no Snowflake (OLAP) com latência de segundos para análise de dados.

## Tecnologias Utilizadas

<table align="center">
  <tr>
    <td align="center">
      <a href="https://www.docker.com/">
        <img alt="Docker" width="40px" style="padding-right:20px;" src="https://raw.githubusercontent.com/mvjr98/fancy-icons/main/docker/docker.svg"/>
      </a>
      <a href="https://kafka.apache.org/">
        <img alt="Kafka" width="40px" style="padding-right:20px;" src="https://raw.githubusercontent.com/mvjr98/fancy-icons/main/apache_kafka/apache_kafka.svg"/>
      </a>
      <a href="https://www.snowflake.com/pt_br/">
        <img alt="Snowflake" width="40px" style="padding-right:20px;" src="https://raw.githubusercontent.com/MvJr98/fancy-icons/main/snowflake/snowflake.svg"/>
      </a>
    </td>
  </tr>
</table>

## 🏛️ Arquitetura

O fluxo de dados segue a arquitetura abaixo:

1.  **Origem (PostgreSQL):** As transações ocorrem no banco `northwind`.
2.  **Captura (Debezium):** O conector lê o *Write-Ahead Log (WAL)* do Postgres.
3.  **Transporte (Kafka):** Os dados são serializados em JSON e enviados para tópicos no Kafka Broker.
4.  **Ingestão (Snowpipe Streaming):** O conector Snowflake Sink lê do Kafka e faz a ingestão via gRPC diretamente para tabelas no Snowflake.
5.  **Transformação (Snowflake Tasks):** Uma *Task* agendada faz o `MERGE` (Deduplicação, Updates e Deletes) da tabela de ingestão (Raw) para a tabela final (Bronze).

![Architecture Diagram](./architecture_diagram.png)
*(Certifique-se de colocar a imagem que você gerou nesta pasta)*

---

## 📂 Estrutura do Projeto

```bash
├── Postgres/               # Ambiente do Banco de Origem
│   ├── docker-compose.yml  # Postgres + pgAdmin
│   └── initdb/             # Scripts de DDL e DML (Northwind)
│
├── kafka/                  # Core de Streaming
│   ├── docker-compose.yml  # Zookeeper, Broker, Schema Registry, Connect, AKHQ
│   ├── kafka-connect/      # Plugins (Jars do Debezium e Snowflake)
│   └── connectors-config/  # JSONs de configuração dos conectores
│
├── Snowflake/              # Scripts e Configurações do Destino
│   └── setup_pipeline.sql  # SQL para criar DB, Schema, Tables, Streams e Tasks
│
├── setup_connectors.sh     # Script para automatizar o deploy dos conectores
└── README.md               # Documentação do Projeto
```
##
### 🛠️ Pré-requisitos
- Docker & Docker Compose instalados.

- [Conta no Snowflake](https://signup.snowflake.com/?trial=student) (Trial ou Enterprise).

- Chaves RSA geradas para autenticação segura no Snowflake.

- jq e curl (opcionais, para rodar o script de automação localmente).
##

### Como Executar
### 1. Preparar o Ambiente Snowflake
Execute o script SQL localizado em Snowflake/setup_pipeline.md na sua conta Snowflake para criar:

    - Usuário de serviço (SNFLK_USER_KAFKA) e Roles.

    - Databases (RAW_KAFKA, BRONZE).

    - Tabelas (ORDERS_INGEST, ORDERS).

    - Importante: Configure a Chave Pública RSA no usuário criado.

### 2. Iniciar o Banco de Dados (Origem)
Suba o banco de dados e popule com os dados iniciais:

```bash
cd Postgres
docker-compose up -d
```
Validação: Acesse o pgAdmin em http://localhost:5050.

### 3. Iniciar o Cluster Kafka
Suba os serviços de mensageria e o Kafka Connect:

```bash
cd ../kafka
docker-compose up -d
```
Validação: Acesse o AKHQ (Kafka UI) em http://localhost:8080 para monitorar os tópicos e conectores.

### 4. Deploy dos Conectores (Automação)
Para configurar os conectores automaticamente, utilize o script ```setup_connectors.sh``` na raiz do projeto.

```bash
chmod +x setup_connectors.sh
./setup_connectors.sh
```
##
### ⚙️ Detalhes de Configuração
#### Source Connector (Debezium PostgreSQL)
    - Plugin: pgoutput (decodificação lógica nativa do Postgres 10+).

    - Snapshot Mode: initial (realiza carga histórica inicial e depois muda para streaming).

    - Topic Prefix: cdc (ex: cdc.public.orders).

    - Tombstones: Desativados (tombstones.on.delete=false), pois o tratamento de delete é feito no Sink via SMT.

#### Sink Connector (Snowflake Streaming)
    - Ingestion Method: SNOWPIPE_STREAMING (Alta performance e baixa latência via gRPC).

    - Buffer Flush: 1 segundo (Configurado para Near Real-Time).

    - SMT (Single Message Transform): Utiliza ExtractNewRecordState para "aplanar" a estrutura complexa do Debezium e extrair metadados essenciais (__op, __source_ts_ms) para o controle de versão no Snowflake.
##

🛡️ Segurança
Este projeto utiliza Key Pair Authentication para comunicação entre o Kafka Connect e o Snowflake.

Nunca commite o arquivo da chave privada (rsa_key.p8) no Git.

Utilize o .gitignore para excluir arquivos de chaves e configurações sensíveis.

Em produção, recomenda-se o uso de Secrets Management ou variáveis de ambiente para injetar a chave privada (SNOWFLAKE_PRIVATE_KEY) no container.

Autor: Mauro


INSERT INTO public.orders VALUES
	(11555, 'VINET', 5, '1996-07-04', '1996-08-01', '1996-07-16', 3, 32.38, 'Vins et alcools Chevalier', '59 rue de l''Abbaye', 'Reims', NULL, '51100', 'France')


UPDATE public.orders SET ship_country = 'Brazil'
WHERE order_id = 11555


DELETE FROM public.orders
WHERE order_id = 11555