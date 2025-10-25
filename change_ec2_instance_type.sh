#!/bin/bash

# 설정 변수
EC2_NAME="scipion"
NEW_INSTANCE_TYPE="g4dn.4xlarge"  # 변경할 인스턴스 타입

# AWS 리전 설정 (Oregon)
AWS_REGION="us-west-2"

# AWS CLI 페이저 비활성화
export AWS_PAGER=""

# AWS CLI를 사용하여 서버 정보 가져오기
echo "AWS에서 '${EC2_NAME}'로 시작하는 중단된 서버 목록을 가져오는 중..."
TEMP_FILE=$(mktemp)
aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Name,Values=${EC2_NAME}*" "Name=instance-state-name,Values=stopped" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value | [0], InstanceId, InstanceType]" \
  --output text > $TEMP_FILE

# 서버 이름, 인스턴스 ID, 현재 타입을 배열에 저장
declare -a SERVER_NAMES
declare -a INSTANCE_IDS
declare -a CURRENT_TYPES

while read -r name instance_id current_type; do
  if [ -n "$instance_id" ]; then
    SERVER_NAMES+=("$name")
    INSTANCE_IDS+=("$instance_id")
    CURRENT_TYPES+=("$current_type")
  fi
done < $TEMP_FILE

rm $TEMP_FILE

# 서버 목록 확인
if [ ${#INSTANCE_IDS[@]} -eq 0 ]; then
  echo "'${EC2_NAME}'로 시작하는 이름을 가진 중단된 서버가 없습니다."
  echo "주의: 인스턴스 타입 변경은 중단된 서버에서만 가능합니다."
  exit 0
fi

echo "총 ${#INSTANCE_IDS[@]}대의 서버 타입을 ${NEW_INSTANCE_TYPE}으로 변경합니다:"
for ((i=0; i<${#INSTANCE_IDS[@]}; i++)); do
  echo "  - ${SERVER_NAMES[i]} (${INSTANCE_IDS[i]}): ${CURRENT_TYPES[i]} → ${NEW_INSTANCE_TYPE}"
done

# 확인 요청
read -p "위 서버들의 인스턴스 타입을 변경하시겠습니까? (y/n): " confirm
if [[ $confirm != [Yy]* ]]; then
  echo "작업이 취소되었습니다."
  exit 0
fi

# 인스턴스 타입 변경
echo "인스턴스 타입 변경 중..."
for ((i=0; i<${#INSTANCE_IDS[@]}; i++)); do
  aws ec2 modify-instance-attribute \
    --region $AWS_REGION \
    --instance-id ${INSTANCE_IDS[i]} \
    --instance-type ${NEW_INSTANCE_TYPE} > /dev/null 2>&1
  
  if [ $? -eq 0 ]; then
    echo "  ✓ ${SERVER_NAMES[i]} (${INSTANCE_IDS[i]}): ${CURRENT_TYPES[i]} → ${NEW_INSTANCE_TYPE}"
  else
    echo "  ✗ ${SERVER_NAMES[i]} (${INSTANCE_IDS[i]}): 변경 실패"
  fi
done

echo "✓ 인스턴스 타입 변경 작업이 완료되었습니다."
