#!/bin/bash

# ===========================================
# Pub-Sub Pattern 실습환경 구성 스크립트 (AKS with Event Grid)
# ===========================================

# 사용법 출력
print_usage() {
   cat << EOF
사용법:
   $0 <userid>

설명:
   Pub-Sub 패턴 실습을 위한 Azure 리소스를 생성합니다.
   리소스 이름이 중복되지 않도록 userid를 prefix로 사용합니다.

예제:
   $0 gappa     # gappa-pubsub-topic 등의 리소스가 생성됨
EOF
}

# 유틸리티 함수
log() {
   local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
   echo "[$timestamp] $1" | tee -a $LOG_FILE
}

check_error() {
   local status=$?
   if [ $status -ne 0 ]; then
       log "Error: $1 (Exit Code: $status)"
       exit $status
   fi
}

# Azure CLI 로그인 체크
check_azure_cli() {
   log "Azure CLI 로그인 상태 확인 중..."
   if ! az account show &> /dev/null; then
       log "Azure CLI 로그인이 필요합니다."
       az login --use-device-code
       check_error "Azure 로그인 실패"
   fi
}

# 환경 변수 설정
setup_environment() {
   local userid=$1
   USERID=$1
   NAME="${userid}-pubsub"
   NAMESPACE="${NAME}-ns"
   RESOURCE_GROUP="tiu-dgga-rg"
   LOCATION="koreacentral"
   AKS_NAME="${userid}-aks"
   ACR_NAME="${userid}cr"

   VNET_NAME="tiu-dgga-vnet"
   SUBNET_AKS="tiu-dgga-aks-snet"

   EG_TOPIC="$NAME-topic"
   EG_SUB="$NAME-subscriber"

   # MongoDB 설정
   MONGODB_HOST="${NAME}-mongodb"
   MONGODB_PORT="27017"
   MONGODB_DATABASE="telecomdb"
   MONGODB_USER="root"
   MONGODB_PASSWORD="Passw0rd"
   DB_SECRET_NAME="${userid}-dbsecret"

   # Event Grid
   STORAGE_ACCOUNT="${userid}-storage"
   DEAD_LETTER="${userid}-deadletter"

   PROXY_IP="4.217.249.140"
   ALERT_PUBIP="20.39.205.38"
   SUB_ENDPOINT=""

   LOG_FILE="deployment_${NAME}.log"

   log "환경 변수 설정 완료"
}

# ACR 권한 설정
setup_acr_permission() {
    log "ACR pull 권한 확인 중..."

    # AKS의 service principal 확인
    SP_ID=$(az aks show \
        --name $AKS_NAME \
        --resource-group $RESOURCE_GROUP \
        --query servicePrincipalProfile.clientId -o tsv)
    log "SP_ID-->${SP_ID}"
    if [ -z "${SP_ID}" ]; then
        log "AKS가 Managed Identity를 사용하고 있습니다."
        # ACR 권한이 이미 있다고 가정하고 진행
        log "ACR pull 권한이 이미 설정되어 있다고 가정합니다."
    else
        log "Service Principal을 사용하는 AKS입니다. ACR 권한을 확인합니다..."
        # ACR ID 가져오기
        ACR_ID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query "id" -o tsv)
        check_error "ACR ID 조회 실패"

        # AKS에 ACR pull 권한 부여
        log "ACR pull 권한 설정 중..."
        az aks update \
            --name $AKS_NAME \
            --resource-group $RESOURCE_GROUP \
            --attach-acr $ACR_ID 2>/dev/null || true
        check_error "ACR pull 권한 부여 실패"
    fi
}

# 공통 리소스 설정
setup_common_resources() {
  log "공통 리소스 설정 중..."

  # 네임스페이스 생성
  kubectl create namespace $NAMESPACE 2>/dev/null || true

  # Event Grid Topic 존재 여부 확인
  local topic_exists=$(az eventgrid topic show \
      --name $EG_TOPIC \
      --resource-group $RESOURCE_GROUP \
      --query "provisioningState" -o tsv 2>/dev/null)

  if [ "$topic_exists" != "Succeeded" ]; then
      # Event Grid Topic 생성
      az eventgrid topic create \
          --name $EG_TOPIC \
          --resource-group $RESOURCE_GROUP \
          --location $LOCATION \
          --output none
      check_error "Event Grid Topic 생성 실패"
  else
      log "Event Grid Topic이 이미 존재합니다"
  fi


  # Storage Account가 없으면 생성
  STORAGE_EXISTS=$(az storage account show \
      --name $STORAGE_ACCOUNT \
      --resource-group $RESOURCE_GROUP \
      --query name \
      --output tsv 2>/dev/null)

  if [ -z "$STORAGE_EXISTS" ]; then
      az storage account create \
          --name $STORAGE_ACCOUNT \
          --resource-group $RESOURCE_GROUP \
          --location $LOCATION \
          --sku Standard_LRS
      check_error "Storage Account 생성 실패"
  fi

  # Storage Account connection string 가져오기
  local storage_conn_str=$(az storage account show-connection-string \
      --name $STORAGE_ACCOUNT \
      --resource-group $RESOURCE_GROUP \
      --query connectionString \
      --output tsv)
  check_error "Storage connection string 조회 실패"

  # deadletter 컨테이너 존재 여부 확인
  local container_exists=$(az storage container exists \
      --name $DEAD_LETTER \
      --connection-string "$storage_conn_str" \
      --query "exists" -o tsv)

  if [ "$container_exists" != "true" ]; then
      # deadletter 컨테이너 생성
      az storage container create \
          --name $DEAD_LETTER \
          --connection-string "$storage_conn_str" \
          --output none
      check_error "Storage container 생성 실패"
  else
      log "Deadletter 컨테이너가 이미 존재합니다"
  fi
}

#LB IP부여까지 기다리기
wait_LB() {
   log "LoadBalancer IP 대기 중..."
   for i in {1..10}; do
       ip=$(kubectl get svc $1 -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

       if [ ! -z "$ip" ]; then
           break
       fi
       log "LoadBalancer IP 대기 중... (${i}/30)"
       sleep 10
   done

   if [ -z "$ip" ]; then
       log "Error: LoadBalancer IP를 얻는데 실패했습니다."
       exit 1
   fi
}

# Usage(Producer) 배포 함수
deploy_producer() {
   log "Usage(Producer) 서비스 배포 시작..."
   local service_name="usage"
   local port="8080"
   local replicas="1"

   # JAR 빌드
   ./gradlew ${service_name}:clean ${service_name}:build -x test
   check_error "${service_name} jar 빌드 실패"

   # Dockerfile 생성
   cat > "${service_name}/Dockerfile" << EOF
FROM eclipse-temurin:17-jdk-alpine
COPY build/libs/${service_name}.jar app.jar
ENTRYPOINT ["java","-jar","/app.jar"]
EOF
   check_error "${service_name} Dockerfile 생성 실패"

   # 이미지 빌드
   cd "${service_name}"
   az acr build \
       --registry $ACR_NAME \
       --image "telecom/${service_name}:v1" \
       --file Dockerfile \
       .
   cd ..
   check_error "${service_name} 이미지 빌드 실패"

   # Producer용 ConfigMap 생성
   cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
 name: ${service_name}-config
 namespace: $NAMESPACE
data:
 APP_NAME: "usage-service"
 SERVER_PORT: "$port"
 LOG_LEVEL: "DEBUG"
EOF

   # Producer용 Event Grid Secret 생성
   cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
 name: ${service_name}-eventgrid-secret
 namespace: $NAMESPACE
type: Opaque
stringData:
 endpoint: "$(az eventgrid topic show --name $EG_TOPIC -g $RESOURCE_GROUP --query "endpoint" -o tsv)"
 key: "$(az eventgrid topic key list --name $EG_TOPIC -g $RESOURCE_GROUP --query "key1" -o tsv)"
 topic: "$EG_TOPIC"
EOF

   # Producer 배포
   kubectl delete deploy ${service_name}-deploy 2>/dev/null || true

   cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
 name: ${service_name}-deploy
 namespace: $NAMESPACE
spec:
 replicas: $replicas
 selector:
   matchLabels:
     app: $service_name
 template:
   metadata:
     labels:
       app: $service_name
   spec:
     containers:
     - name: $service_name
       image: ${ACR_NAME}.azurecr.io/telecom/${service_name}:v1
       imagePullPolicy: Always
       ports:
       - containerPort: $port
       env:
       - name: APP_NAME
         valueFrom:
           configMapKeyRef:
             name: ${service_name}-config
             key: APP_NAME
       - name: SERVER_PORT
         valueFrom:
           configMapKeyRef:
             name: ${service_name}-config
             key: SERVER_PORT
       - name: LOG_LEVEL
         valueFrom:
           configMapKeyRef:
             name: ${service_name}-config
             key: LOG_LEVEL
       - name: EVENT_GRID_ENDPOINT
         valueFrom:
           secretKeyRef:
             name: ${service_name}-eventgrid-secret
             key: endpoint
       - name: EVENT_GRID_KEY
         valueFrom:
           secretKeyRef:
             name: ${service_name}-eventgrid-secret
             key: key
       - name: EVENT_GRID_TOPIC
         valueFrom:
           secretKeyRef:
             name: ${service_name}-eventgrid-secret
             key: topic
---
apiVersion: v1
kind: Service
metadata:
 name: ${service_name}-svc
 namespace: $NAMESPACE
spec:
 selector:
   app: $service_name
 ports:
 - protocol: TCP
   port: 80
   targetPort: $port
 type: LoadBalancer
EOF

  # LoadBalancer IP 대기
  wait_LB "${service_name}-svc"
}

# Alert(Subscriber) 배포 함수
deploy_subscriber() {
   log "Alert(Subscriber) 서비스 배포 시작..."
   local service_name="alert"
   local port="8080"
   local replicas="1"

   # JAR 빌드
   ./gradlew ${service_name}:clean ${service_name}:build -x test
   check_error "${service_name} jar 빌드 실패"

   # Dockerfile 생성
   cat > "${service_name}/Dockerfile" << EOF
FROM eclipse-temurin:17-jdk-alpine
COPY build/libs/${service_name}.jar app.jar
ENTRYPOINT ["java","-jar","/app.jar"]
EOF
   check_error "${service_name} Dockerfile 생성 실패"

   # 이미지 빌드
   cd "${service_name}"
   az acr build \
       --registry $ACR_NAME \
       --image "telecom/${service_name}:v1" \
       --file Dockerfile \
       .
   cd ..
   check_error "${service_name} 이미지 빌드 실패"

   # Subscriber용 ConfigMap 생성
   cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${service_name}-config
  namespace: $NAMESPACE
data:
  APP_NAME: "alert-service"
  SERVER_PORT: "$port"
  LOG_LEVEL: "DEBUG"
  EVENT_TYPES: "UsageExceeded,UsageAlert"

EOF

   # Subscriber 배포
   kubectl delete deploy ${service_name}-deploy 2>/dev/null || true

   cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${service_name}-deploy
  namespace: $NAMESPACE
spec:
  replicas: $replicas
  selector:
    matchLabels:
      app: $service_name
  template:
    metadata:
      labels:
        app: $service_name
    spec:
      containers:
      - name: $service_name
        image: ${ACR_NAME}.azurecr.io/telecom/${service_name}:v1
        imagePullPolicy: Always
        ports:
        - containerPort: $port
        env:
        - name: APP_NAME
          valueFrom:
            configMapKeyRef:
              name: ${service_name}-config
              key: APP_NAME
        - name: SERVER_PORT
          valueFrom:
            configMapKeyRef:
              name: ${service_name}-config
              key: SERVER_PORT
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: ${service_name}-config
              key: LOG_LEVEL
        - name: EVENT_TYPES
          valueFrom:
            configMapKeyRef:
              name: ${service_name}-config
              key: EVENT_TYPES
        - name: MONGODB_HOST
          value: "${MONGODB_HOST}"
        - name: MONGODB_PORT
          value: "${MONGODB_PORT}"
        - name: MONGODB_DATABASE
          value: "${MONGODB_DATABASE}"
        - name: MONGODB_USER
          value: "${MONGODB_USER}"
        - name: MONGODB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: $DB_SECRET_NAME
              key: mongo-password

---
apiVersion: v1
kind: Service
metadata:
 name: ${service_name}-svc
 namespace: $NAMESPACE
spec:
 selector:
   app: $service_name
 ports:
 - protocol: TCP
   port: 80
   targetPort: $port
 type: LoadBalancer
 loadBalancerIP: ${ALERT_PUBIP}
EOF

   # Deployment Ready 대기
   kubectl rollout status deployment/${service_name}-deploy -n $NAMESPACE
   check_error "${service_name} Deployment 준비 실패"

  # LoadBalancer IP 대기
  wait_LB "${service_name}-svc"
}

# Event Grid Subscriber 설정
setup_event_grid_subscriber() {
    log "Event Grid Subscriber 설정 중..."
    SUB_ENDPOINT="https://${USERID}.${PROXY_IP}.nip.io/api/events/usage"

    # 기존 subscription 확인
    local subscription_exists=$(az eventgrid event-subscription show \
        --name $EG_SUB \
        --source-resource-id $(az eventgrid topic show --name $EG_TOPIC -g $RESOURCE_GROUP --query "id" -o tsv) \
        --query "provisioningState" -o tsv 2>/dev/null)

    if [ "$subscription_exists" = "Succeeded" ]; then
        log "Event Grid Subscription이 이미 존재합니다"
        return 0
    fi

    # Storage Account ID 가져오기
    local storage_id=$(az storage account show \
        --name $STORAGE_ACCOUNT \
        --resource-group $RESOURCE_GROUP \
        --query id \
        --output tsv)
    check_error "Storage Account ID 조회 실패"

    # 신규 subscription 생성
    az eventgrid event-subscription create \
        --name $EG_SUB \
        --source-resource-id $(az eventgrid topic show --name $EG_TOPIC -g $RESOURCE_GROUP --query "id" -o tsv) \
        --endpoint $SUB_ENDPOINT \
        --endpoint-type webhook \
        --included-event-types UsageExceeded UsageAlert \
        --max-delivery-attempts 3 \
        --event-ttl 1440 \
        --deadletter-endpoint "${storage_id}/blobServices/default/containers/${DEAD_LETTER}" \
        --output none
    check_error "Event Grid Subscriber 생성 실패"

    log "Event Grid Subscriber가 생성되었습니다"
    log "Endpoint: ${subscriber_endpoint}"
}

# MongoDB 설정
setup_mongodb() {
   log "MongoDB 데이터베이스 설정 중..."

   # MongoDB 초기화 스크립트 ConfigMap 생성
   cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
 name: mongo-init-script
 namespace: $NAMESPACE
data:
 init-mongo.js: |
   db = db.getSiblingDB('telecomdb');
   db.createUser({
     user: 'telecom',
     pwd: '$MONGO_PASSWORD',
     roles: [{ role: 'readWrite', db: 'telecomdb' }]
   });
EOF

   cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
 name: $NAME-mongodb
 namespace: $NAMESPACE
spec:
 serviceName: "$NAME-mongodb"
 replicas: 1
 selector:
   matchLabels:
     app: mongodb
     userid: $USERID
 template:
   metadata:
     labels:
       app: mongodb
       userid: $USERID
   spec:
     containers:
     - name: mongodb
       image: mongo:8.0.3
       env:
       - name: MONGO_INITDB_ROOT_USERNAME
         value: "root"
       - name: MONGO_INITDB_ROOT_PASSWORD
         valueFrom:
           secretKeyRef:
             name: $DB_SECRET_NAME
             key: mongo-password
       - name: MONGO_INITDB_DATABASE
         value: "telecomdb"
       - name: MONGO_INITDB_USERNAME
         value: "telecom"
       - name: MONGO_INITDB_PASSWORD
         valueFrom:
            secretKeyRef:
              name: $DB_SECRET_NAME
              key: mongo-password
       ports:
       - containerPort: 27017
       volumeMounts:
       - name: mongodb-data
         mountPath: /data/db
         subPath: mongo
       - name: init-script
         mountPath: /docker-entrypoint-initdb.d
     volumes:
     - name: init-script
       configMap:
         name: mongo-init-script
 volumeClaimTemplates:
 - metadata:
     name: mongodb-data
   spec:
     accessModes: [ "ReadWriteOnce" ]
     resources:
       requests:
         storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
 name: $NAME-mongodb
 namespace: $NAMESPACE
spec:
 selector:
   app: mongodb
   userid: $USERID
 ports:
 - port: 27017
   targetPort: 27017
 type: ClusterIP
EOF
   check_error "MongoDB 배포 실패"
}

# Database 설정
setup_databases() {
   log "데이터베이스 설정 중..."

   # Secret 설정
   log "데이터베이스 Secret 설정 중..."
   kubectl delete secret $DB_SECRET_NAME --namespace $NAMESPACE

   # DB Namespace에 Secret 생성
   kubectl create secret generic $DB_SECRET_NAME \
       --namespace $NAMESPACE \
       --from-literal=mongo-password=$MONGODB_PASSWORD \
       2>/dev/null || true
   check_error "데이터베이스 Secret 생성 실패"

   # 기존 데이터베이스 정리
  log "기존 데이터베이스 정리 중..."
  # StatefulSet 삭제
  kubectl delete statefulset -n $NAMESPACE $NAME-mongodb 2>/dev/null || true
  # PVC 삭제 - label에 userid 추가
  kubectl delete pvc -n $NAMESPACE -l "app=mongodb,userid=$USERID" 2>/dev/null || true

  # 데이터베이스 배포
  setup_mongodb

  # 데이터베이스가 Ready 상태가 될 때까지 대기
  log "데이터베이스 준비 상태 대기 중..."
  kubectl wait --for=condition=ready pod -l "app=mongodb,userid=$USERID" -n $NAMESPACE --timeout=120s
  log "데이터베이스 준비 완료"
}

print_results() {
    log "=== 배포 결과 ==="
    kubectl get all -n $NAMESPACE

    log "=== Event Grid Topic 정보 ==="
    az eventgrid topic show --name $EG_TOPIC --resource-group $RESOURCE_GROUP -o table

    log "=== Event Grid Subscription 정보 ==="
    az eventgrid event-subscription show \
        --name $EG_SUB \
        --source-resource-id $(az eventgrid topic show --name $EG_TOPIC -g $RESOURCE_GROUP --query "id" -o tsv) \
        -o table

    log "=== 서비스 접근 정보 ==="
    local usage_ip=$(kubectl get svc usage-svc -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    local alert_ip=$(kubectl get svc alert-svc -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

    log "Application URLs:"
    log "usage-svc URL: http://${usage_ip}/swagger-ui.html"
    log "alert-svc URL: http://${alert_ip}/swagger-ui.html"
    log "Event Grid Subscription Endpoint: ${SUB_ENDPOINT}"
}

# 메인 실행 함수
main() {
   if [ $# -ne 1 ]; then
       print_usage
       exit 1
   fi

   if [[ ! $1 =~ ^[a-z0-9]+$ ]]; then
       echo "Error: userid는 영문 소문자와 숫자만 사용할 수 있습니다."
       exit 1
   fi

   # 환경 설정
   setup_environment "$1"

   # 사전 체크
   check_azure_cli

   # ACR 권한 설정
   setup_acr_permission

   # 공통 리소스 설정
   setup_common_resources

   # mongodb 설정
   setup_databases

   # Producer 배포
   deploy_producer

   # Subscriber 배포
   deploy_subscriber

   # Event Grid Subscriber 설정
   setup_event_grid_subscriber

   # 결과 출력
   print_results

   log "모든 리소스가 성공적으로 생성되었습니다."
}

# 스크립트 시작
main "$@"
