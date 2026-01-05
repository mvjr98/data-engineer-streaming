# Guia de Configuração: Pipeline Kafka CDC -> Snowflake (Raw & Bronze)

Este guia cobre a configuração do ambiente Snowflake para receber dados via Kafka Connect (Snowpipe Streaming) e processá-los automaticamente para uma tabela final consolidada usando CDC (Change Data Capture).

---

### Arquitetura Proposta

**Usuário de Serviço**: SNFLK_USER_KAFKA (autenticado via Key Pair).

**Role**: SNFLK_ROLE_KAFKA.

**Database de Ingestão (Landing)**: RAW_KAFKA -> Schema NORTHWIND -> Tabela ORDERS_INGEST.

**Database Final (Refined)**: BRONZE -> Schema NORTHWIND -> Tabela ORDERS.

**Automação**: Stream para capturar mudanças na Ingest e Task para fazer o Merge na Bronze.

## 
### Passo 1: Segurança e Permissões (Executar como SECURITYADMIN)
Primeiro, criamos o usuário, a role e damos os acessos básicos.

```sql

USE ROLE SECURITYADMIN;

-- 1. Criar a Role dedicada para o Kafka
CREATE ROLE IF NOT EXISTS SNFLK_ROLE_KAFKA;

-- 2. Criar o Usuário de Serviço (A chave pública será adicionada depois)
CREATE USER IF NOT EXISTS SNFLK_USER_KAFKA
    DEFAULT_ROLE = SNFLK_ROLE_KAFKA
    DEFAULT_WAREHOUSE = COMPUTE_WH
    COMMENT = 'Usuário de serviço para Kafka Connect (Snowpipe Streaming)';

-- 3. Atribuir a Role ao Usuário
GRANT ROLE SNFLK_ROLE_KAFKA TO USER SNFLK_USER_KAFKA;

-- 4. Dar permissão de uso do Warehouse
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE SNFLK_ROLE_KAFKA;

-- 5: Permitir que administradores gerenciem os objetos dessa role
-- Opção A: Dar a role para a hierarquia SYSADMIN (Recomendado)
GRANT ROLE SNFLK_ROLE_KAFKA TO ROLE SYSADMIN;

-- Opção B: Dar a role para o seu usuário administrador específico
-- GRANT ROLE SNFLK_ROLE_KAFKA TO USER <SEU_USUARIO_ADMIN>;
```
##
### Passo 2: Estrutura de Banco de Dados (Executar como SYSADMIN)

Vamos criar os databases e schemas onde os dados irão residir.

```sql
USE ROLE SYSADMIN;

-- 1. Criar Database de Ingestão (RAW)
CREATE DATABASE IF NOT EXISTS RAW_KAFKA;
CREATE SCHEMA IF NOT EXISTS RAW_KAFKA.NORTHWIND;

-- 2. Criar Database Final (BRONZE)
CREATE DATABASE IF NOT EXISTS BRONZE;
CREATE SCHEMA IF NOT EXISTS BRONZE.NORTHWIND;
```
## 

### Passo 3: Conceder Acessos ao Usuário do Kafka (Executar como SECURITYADMIN)
O usuário do Kafka precisa de permissão total no schema de Ingestão (RAW_KAFKA), mas não precisa ver a BRONZE.

```sql

USE ROLE SECURITYADMIN;

-- Permissões no Database de Ingestão
GRANT USAGE ON DATABASE RAW_KAFKA TO ROLE SNFLK_ROLE_KAFKA;
GRANT USAGE ON SCHEMA RAW_KAFKA.NORTHWIND TO ROLE SNFLK_ROLE_KAFKA;

-- Permissões para criar objetos (Tabelas, Pipes, Stages) no schema de ingestão
GRANT CREATE TABLE ON SCHEMA RAW_KAFKA.NORTHWIND TO ROLE SNFLK_ROLE_KAFKA;
GRANT CREATE STAGE ON SCHEMA RAW_KAFKA.NORTHWIND TO ROLE SNFLK_ROLE_KAFKA;
GRANT CREATE PIPE ON SCHEMA RAW_KAFKA.NORTHWIND TO ROLE SNFLK_ROLE_KAFKA;
```
##

### Passo 4: Criação das Tabelas (DDL) (Executar como SYSADMIN)
Aqui criamos a tabela bruta (que recebe o JSON do Kafka) e a tabela final estruturada.

```sql
USE ROLE SYSADMIN;

-- 1. Tabela de Ingestão (RAW_KAFKA)
-- Contém colunas de metadados do Debezium (__OP, __DELETED, etc)
CREATE OR REPLACE TABLE RAW_KAFKA.NORTHWIND.ORDERS_INGEST (
    ORDER_ID NUMBER(38,0) NOT NULL,
    CUSTOMER_ID VARCHAR(50),
    EMPLOYEE_ID NUMBER(38,0),
    ORDER_DATE DATE,
    REQUIRED_DATE DATE,
    SHIPPED_DATE DATE,
    SHIP_VIA NUMBER(38,0),
    FREIGHT NUMBER(10,2),
    SHIP_NAME VARCHAR(100),
    SHIP_ADDRESS VARCHAR(255),
    SHIP_CITY VARCHAR(100),
    SHIP_POSTAL_CODE VARCHAR(20),
    SHIP_COUNTRY VARCHAR(50),
    SHIP_REGION VARCHAR(100),
    RECORD_METADATA VARIANT, -- Coluna técnica do Snowflake Connector
    __OP VARCHAR(5),         -- Operação (c, u, d, r)
    __SOURCE_TS_MS NUMBER(38,0), -- Timestamp da origem
    __DELETED VARCHAR(5),    -- Flag de delete ('true'/'false')
    PRIMARY KEY (ORDER_ID)
);

-- IMPORTANTE: Dar posse da tabela de ingestão para o Role do Kafka
-- Isso garante que o conector consiga escrever nela sem erro de permissão.
GRANT OWNERSHIP ON TABLE RAW_KAFKA.NORTHWIND.ORDERS_INGEST TO ROLE SNFLK_ROLE_KAFKA REVOKE CURRENT GRANTS;


-- 2. Tabela Final (BRONZE)
-- Tabela limpa, sem as colunas de controle do Kafka
CREATE OR REPLACE TABLE BRONZE.NORTHWIND.ORDERS (
    ORDER_ID NUMBER(38,0) NOT NULL,
    CUSTOMER_ID VARCHAR(50),
    EMPLOYEE_ID NUMBER(38,0),
    ORDER_DATE DATE,
    REQUIRED_DATE DATE,
    SHIPPED_DATE DATE,
    SHIP_VIA NUMBER(38,0),
    FREIGHT NUMBER(10,2),
    SHIP_NAME VARCHAR(100),
    SHIP_ADDRESS VARCHAR(255),
    SHIP_CITY VARCHAR(100),
    SHIP_POSTAL_CODE VARCHAR(20),
    SHIP_COUNTRY VARCHAR(50),
    SHIP_REGION VARCHAR(100),
    PRIMARY KEY (ORDER_ID)
);
```
##
### Passo 5: Configuração do Pipeline CDC (Stream & Task)
Configuramos o motor que vai ler da RAW_KAFKA e aplicar o MERGE na BRONZE.

Nota: Execute isso com uma role que tenha permissão em ambos os bancos (ex: SYSADMIN ou uma role de engenharia de dados), NÃO use a role do Kafka para criar a Task.

```sql
USE ROLE SYSADMIN;

-- 1. Criar o Stream (O "Olheiro")
-- Monitora inserções na tabela de ingestão
CREATE OR REPLACE STREAM RAW_KAFKA.NORTHWIND.STREAM_ORDERS_INGEST 
ON TABLE RAW_KAFKA.NORTHWIND.ORDERS_INGEST;


-- 2. Criar a Task com MERGE (O "Motor")
-- Roda a cada 1 minuto, deduplica o lote e aplica Insert/Update/Delete na Bronze
CREATE OR REPLACE TASK BRONZE.NORTHWIND.TASK_MERGE_ORDERS
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = '1 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('RAW_KAFKA.NORTHWIND.STREAM_ORDERS_INGEST')
AS
MERGE INTO BRONZE.NORTHWIND.ORDERS AS target
USING (
    SELECT * FROM RAW_KAFKA.NORTHWIND.STREAM_ORDERS_INGEST
    -- Lógica de Deduplicação: Pega apenas o registro mais recente de cada ID no lote
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ORDER_ID ORDER BY __SOURCE_TS_MS DESC) = 1
) AS source
ON target.ORDER_ID = source.ORDER_ID

-- CASO 1: Delete na origem (__DELETED = 'true')
WHEN MATCHED AND source.__DELETED = 'true' THEN 
    DELETE

-- CASO 2: Update (Existe no destino e não é delete)
WHEN MATCHED THEN 
    UPDATE SET 
        target.CUSTOMER_ID = source.CUSTOMER_ID,
        target.EMPLOYEE_ID = source.EMPLOYEE_ID,
        target.ORDER_DATE = source.ORDER_DATE,
        target.REQUIRED_DATE = source.REQUIRED_DATE,
        target.SHIPPED_DATE = source.SHIPPED_DATE,
        target.SHIP_VIA = source.SHIP_VIA,
        target.FREIGHT = source.FREIGHT,
        target.SHIP_NAME = source.SHIP_NAME,
        target.SHIP_ADDRESS = source.SHIP_ADDRESS,
        target.SHIP_CITY = source.SHIP_CITY,
        target.SHIP_POSTAL_CODE = source.SHIP_POSTAL_CODE,
        target.SHIP_COUNTRY = source.SHIP_COUNTRY,
        target.SHIP_REGION = source.SHIP_REGION

-- CASO 3: Insert (Não existe no destino)
WHEN NOT MATCHED AND (source.__DELETED IS NULL OR source.__DELETED != 'true') THEN 
    INSERT (
        ORDER_ID, CUSTOMER_ID, EMPLOYEE_ID, ORDER_DATE, REQUIRED_DATE, 
        SHIPPED_DATE, SHIP_VIA, FREIGHT, SHIP_NAME, SHIP_ADDRESS, 
        SHIP_CITY, SHIP_POSTAL_CODE, SHIP_COUNTRY, SHIP_REGION
    ) VALUES (
        source.ORDER_ID, source.CUSTOMER_ID, source.EMPLOYEE_ID, source.ORDER_DATE, source.REQUIRED_DATE, 
        source.SHIPPED_DATE, source.SHIP_VIA, source.FREIGHT, source.SHIP_NAME, source.SHIP_ADDRESS, 
        source.SHIP_CITY, source.SHIP_POSTAL_CODE, source.SHIP_COUNTRY, source.SHIP_REGION
    );

-- 3. Iniciar a Task
USE ROLE ACCOUNTADMIN;

GRANT EXECUTE TASK ON ACCOUNT TO ROLE SYSADMIN;

GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE SYSADMIN;

USE ROLE SYSADMIN;

ALTER TASK BRONZE.NORTHWIND.TASK_MERGE_ORDERS RESUME;
```
##
### Passo 6: Configuração de Autenticação (Key Pair)
Conforme a [documentação oficial do Snowflake](https://docs.snowflake.com/en/user-guide/kafka-connector-install#using-key-pair-authentication-key-rotation), recomenda-se o uso de chaves criptografadas.

### 6.1. Gerar Chave Privada
No terminal (Linux/Mac/WSL), gere uma chave privada criptografada. Você será solicitado a digitar uma passphrase (senha).

```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 des3 -inform PEM -out rsa_key.p8
```

### 6.2. Gerar Chave Pública
Gere a chave pública a partir da chave privada criada, será pedido a senha criada no passo anterior.

```bash
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
```
### 6.3. Associar Chave ao Usuário (Snowflake)
Abra o arquivo rsa_key.pub.

Copie apenas o conteúdo da chave (remova as linhas -----BEGIN PUBLIC KEY----- e -----END PUBLIC KEY-----).

No Snowflake (como SECURITYADMIN), execute:

```sql
USE ROLE SECURITYADMIN;
ALTER USER SNFLK_USER_KAFKA SET RSA_PUBLIC_KEY='<COLE_O_CONTEUDO_DA_CHAVE_AQUI>';
```
## 
### Passo 6: Configuração de Autenticação (Key Pair)

Use este modelo no Kafka Connect. Note que incluímos o campo snowflake.private.key.passphrase pois geramos a chave seguindo a documentação oficial.

```json
{
  "name": "sink_snowflake_orders_v1",
  "config": {
    "connector.class": "com.snowflake.kafka.connector.SnowflakeSinkConnector",
    "tasks.max": "1",
    "topics": "cdc.public.orders",

    "snowflake.url.name": "SUA_CONTA.snowflakecomputing.com",
    "snowflake.user.name": "SNFLK_USER_KAFKA",
    "snowflake.private.key": "<CONTEUDO_DO_ARQUIVO_rsa_key.p8_COMPLETO>",
    "snowflake.private.key.passphrase": "<CONTEUDO_DO_ARQUIVO_rsa_key.p8_COMPLETO>",

    "snowflake.database.name": "RAW_KAFKA",
    "snowflake.schema.name": "NORTHWIND",
    "snowflake.warehouse.name": "COMPUTE_WH",
    "snowflake.role.name": "SNFLK_ROLE_KAFKA",
    "snowflake.ingestion.method": "SNOWPIPE_STREAMING",

    "buffer.count.records": "50",
    "buffer.flush.time": "1",
    "buffer.size.bytes": "5000000",
    "snowflake.streaming.max.client.lag": "1",

    "value.converter.schemas.enable": "true",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",

    "key.converter": "org.apache.kafka.connect.storage.StringConverter",

    "snowflake.enable.schematization": "true",
    "snowflake.topic2table.map": "cdc.public.orders:ORDERS_INGEST",

    "transforms": "unwrap",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "false",
    "transforms.unwrap.delete.handling.mode": "rewrite",
    "transforms.unwrap.add.fields": "op,source.ts_ms"
  }
}
```