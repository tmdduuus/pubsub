#!/bin/bash

# ===========================================
# Pub-Sub Pattern 실습환경 정리 스크립트
# ===========================================

print_usage() {
   cat << EOF
사용법: $0 <userid>
설명: Pub-Sub 패턴 실습 리소스를 정리합니다.
예제: $0 gappa
EOF
}

log() {
   local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
   echo "[$timestamp] $1"
}

setup_environment() {
   local userid=$1
   USERID=$1
   NAME="${userid}-pubsub"
   NAMESPACE="${NAME}-ns"
   RESOURCE_GROUP="tiu-dgga-rg"

   # Event Grid 관련
   EG_TOPIC="$NAME-topic"
   EG_SUB="$NAME-subscriber"

   # Storage Account
   STORAGE_ACCOUNT="${userid}storage"
   DEAD_LETTER="${userid}deadletter"

   # Database
   MONGODB_HOST="${NAME}-mongodb"
   DB_SECRET_NAME="${userid}-dbsecret"
}

cleanup_storage() {
   log "Storage Account 리소스 정리 중..."

   # Dead Letter Container 삭제
   az storage container delete \
       --name $DEAD_LETTER \
       --account-name $STORAGE_ACCOUNT \
       2>/dev/null || true

   # Storage Account 삭제
   az storage account delete \
       --name $STORAGE_ACCOUNT \
       --resource-group $RESOURCE_GROUP \
       --yes \
       2>/dev/null || true

   log "Storage Account 리소스 정리 완료"
}

cleanup_event_grid() {
   log "Event Grid 리소스 정리 중..."

   # Topic 존재 여부 확인
   local topic_exists=$(az eventgrid topic show \
       --name $EG_TOPIC \
       --resource-group $RESOURCE_GROUP \
       --query id -o tsv 2>/dev/null)

   if [ ! -z "$topic_exists" ]; then
       # Subscription 삭제
       az eventgrid event-subscription delete \
           --name $EG_SUB \
           --source-resource-id $topic_exists \
           2>/dev/null || true

       # Topic 삭제
       az eventgrid topic delete \
           --name $EG_TOPIC \
           --resource-group $RESOURCE_GROUP \
           2>/dev/null || true

       log "Event Grid Topic 삭제 완료"
   else
       log "Event Grid Topic이 존재하지 않습니다"
   fi
}

cleanup_kubernetes() {
   log "Kubernetes 리소스 정리 중..."

   # StatefulSet 삭제
   kubectl delete statefulset -n $NAMESPACE $NAME-mongodb 2>/dev/null || true

   # PVC 삭제
   kubectl delete pvc -n $NAMESPACE -l "app=mongodb,userid=$USERID" 2>/dev/null || true

   # Deployment 삭제
   kubectl delete deployment -n $NAMESPACE usage-deploy alert-deploy 2>/dev/null || true

   # Service 삭제
   kubectl delete service -n $NAMESPACE usage-svc alert-svc $MONGODB_HOST 2>/dev/null || true

   # ConfigMap 삭제
   kubectl delete configmap -n $NAMESPACE usage-config alert-config mongo-init-script 2>/dev/null || true

   # Secret 삭제
   kubectl delete secret -n $NAMESPACE usage-eventgrid-secret $DB_SECRET_NAME 2>/dev/null || true

   # Namespace가 비어있으면 삭제
   if ! kubectl get all -n $NAMESPACE 2>/dev/null | grep -q .; then
       kubectl delete namespace $NAMESPACE 2>/dev/null || true
       log "Namespace 삭제 완료"
   else
       log "경고: Namespace에 아직 리소스가 있어 삭제하지 않습니다"
   fi

   log "Kubernetes 리소스 정리 완료"
}

check_resources() {
   log "=== 남은 리소스 확인 ==="

   # Event Grid 리소스 확인
   local topic_exists=$(az eventgrid topic show \
       --name $EG_TOPIC \
       --resource-group $RESOURCE_GROUP \
       2>/dev/null)
   if [ ! -z "$topic_exists" ]; then
       log "Event Grid Topic이 아직 존재합니다"
   fi

   # Storage Account 확인
   local storage_exists=$(az storage account show \
       --name $STORAGE_ACCOUNT \
       --resource-group $RESOURCE_GROUP \
       2>/dev/null)
   if [ ! -z "$storage_exists" ]; then
       log "Storage Account가 아직 존재합니다"
   fi

   # Kubernetes 리소스 확인
   kubectl get all -n $NAMESPACE 2>/dev/null || echo "남은 Kubernetes 리소스 없음"
}

main() {
   if [ $# -ne 1 ]; then
       print_usage
       exit 1
   fi

   if [[ ! $1 =~ ^[a-z0-9]+$ ]]; then
       echo "Error: userid는 영문 소문자와 숫자만 사용할 수 있습니다."
       exit 1
   fi

   setup_environment "$1"

   log "리소스 정리를 시작합니다..."

   cleanup_kubernetes
   cleanup_event_grid
   cleanup_storage
   check_resources

   log "리소스 정리가 완료되었습니다"
}

main "$@"
