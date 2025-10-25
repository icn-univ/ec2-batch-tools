#!/bin/bash

# 설정 변수
EC2_NAME="scipion"

# AWS 리전 설정 (Oregon)
AWS_REGION="us-west-2"

# AWS CLI 페이저 비활성화
export AWS_PAGER=""

# AWS CLI를 사용하여 서버 정보 가져오기
echo "AWS에서 '${EC2_NAME}'로 시작하는 실행 중인 서버 목록을 가져오는 중..."
TEMP_FILE=$(mktemp)
aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Name,Values=${EC2_NAME}*" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value | [0], InstanceId]" \
  --output text > $TEMP_FILE

# 서버 이름과 인스턴스 ID를 배열에 저장
declare -a SERVER_NAMES
declare -a INSTANCE_IDS

while read -r name instance_id; do
  if [ -n "$instance_id" ]; then
    SERVER_NAMES+=("$name")
    INSTANCE_IDS+=("$instance_id")
  fi
done < $TEMP_FILE

rm $TEMP_FILE

# 서버 목록 확인
if [ ${#INSTANCE_IDS[@]} -eq 0 ]; then
  echo "'${EC2_NAME}'로 시작하는 이름을 가진 실행 중인 서버가 없습니다."
  exit 0
fi

echo "총 ${#INSTANCE_IDS[@]}대의 서버를 정지합니다:"
for ((i=0; i<${#INSTANCE_IDS[@]}; i++)); do
  echo "  - ${SERVER_NAMES[i]} (${INSTANCE_IDS[i]})"
done

# 확인 요청
read -p "위 서버들을 정지하시겠습니까? (y/n): " confirm
if [[ $confirm != [Yy]* ]]; then
  echo "작업이 취소되었습니다."
  exit 0
fi

# 서버 정지
echo "서버 정지 중..."
aws ec2 stop-instances --region $AWS_REGION --instance-ids ${INSTANCE_IDS[@]} --output text > /dev/null

if [ $? -eq 0 ]; then
  echo "✓ 모든 서버 정지 명령이 완료되었습니다."
  for ((i=0; i<${#INSTANCE_IDS[@]}; i++)); do
    echo "  ✓ ${SERVER_NAMES[i]} (${INSTANCE_IDS[i]})"
  done
else
  echo "✗ 서버 정지 중 오류가 발생했습니다."
  exit 1
fi
