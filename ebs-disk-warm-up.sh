#!/bin/bash

# 필요한 변수들
BATCH_SIZE=4
WAIT_TIME=10
SSH_USER="ubuntu"
SSH_KEY_PATH="./ec2-oregon-key.pem"
EC2_NAME="scipion"
COMPLETED_SERVERS_FILE="./completed_servers.txt"  # 완료된 서버 목록 파일

# AWS 리전 설정 (Oregon)
AWS_REGION="us-west-2"

# AWS CLI 페이저 비활성화
export AWS_PAGER=""

# 트랩 설정 - 스크립트 중단 시 정리 작업
cleanup() {
  echo "스크립트가 중단되었습니다. 현재까지 완료된 서버 정보는 $COMPLETED_SERVERS_FILE 파일에 저장됩니다."
  exit 1
}
trap cleanup SIGINT SIGTERM

# 완료된 서버 목록 파일이 없으면 생성
if [ ! -f "$COMPLETED_SERVERS_FILE" ]; then
  touch "$COMPLETED_SERVERS_FILE"
fi

# SSH 키 파일 확인
if [ ! -f "$(eval echo "$SSH_KEY_PATH")" ]; then
  echo "SSH 키 파일을 찾을 수 없습니다: $SSH_KEY_PATH"
  echo "올바른 경로를 SSH_KEY_PATH 변수에 설정해주세요."
  exit 1
fi

# AWS CLI를 사용하여 서버 정보 가져오기
echo "AWS에서 '${EC2_NAME}'로 시작하는 서버 목록을 가져오는 중..."
TEMP_FILE=$(mktemp)
aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Name,Values=${EC2_NAME}*" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value | [0], PublicIpAddress]" \
  --output text > $TEMP_FILE

# 서버 이름과 IP 주소를 배열에 저장
declare -a SERVER_NAMES
declare -a SERVER_IPS
declare -a SERVER_DISPLAYS

while read -r name ip; do
  if [ -n "$ip" ]; then  # IP가 비어있지 않은 경우만 추가
    # 이미 완료된 서버인지 확인
    if ! grep -q "^$name|$ip|completed$" "$COMPLETED_SERVERS_FILE"; then
      SERVER_NAMES+=("$name")
      SERVER_IPS+=("$ip")
      SERVER_DISPLAYS+=("$name($ip)")
    fi
  fi
done < $TEMP_FILE

# 임시 파일 삭제
rm $TEMP_FILE

# 완료된 서버 수 확인
COMPLETED_COUNT=$(grep -c "|completed$" "$COMPLETED_SERVERS_FILE")

# 서버 목록 확인
if [ ${#SERVER_IPS[@]} -eq 0 ]; then
  if [ $COMPLETED_COUNT -gt 0 ]; then
    echo "모든 서버의 디스크 warm-up이 이미 완료되었습니다. ($COMPLETED_COUNT 대)"
  else
    echo "'${EC2_NAME}'로 시작하는 이름을 가진 실행 중인 서버가 없거나 Public IP가 없습니다."
  fi
  exit 0
fi

echo "총 ${#SERVER_IPS[@]}대의 '${EC2_NAME}'로 시작하는 서버를 처리해야 합니다."
echo "이미 완료된 서버: $COMPLETED_COUNT 대"
echo "처리 대상 서버 샘플(첫 5개): ${SERVER_DISPLAYS[@]:0:5} ..."

# 확인 요청
read -p "위 서버들에 대해 디스크 warm-up을 진행하시겠습니까? (y/n): " confirm
if [[ $confirm != [Yy]* ]]; then
  echo "작업이 취소되었습니다."
  exit 0
fi

echo "디스크 warm-up 작업을 시작합니다. 총 ${#SERVER_IPS[@]}대 서버, ${BATCH_SIZE}대씩 처리"

for ((i=0; i<${#SERVER_IPS[@]}; i+=BATCH_SIZE)); do
  CURRENT_BATCH=$((i/BATCH_SIZE + 1))
  TOTAL_BATCHES=$(( (${#SERVER_IPS[@]} + BATCH_SIZE - 1) / BATCH_SIZE ))
  
  echo "배치 $CURRENT_BATCH/$TOTAL_BATCHES 처리 중... (서버 ${i}~$((i+BATCH_SIZE-1 < ${#SERVER_IPS[@]} ? i+BATCH_SIZE-1 : ${#SERVER_IPS[@]}-1)))"
  
  # 현재 배치의 서버들에 대해 병렬로 명령 실행
  for ((j=i; j<i+BATCH_SIZE && j<${#SERVER_IPS[@]}; j++)); do
    server_ip=${SERVER_IPS[j]}
    server_name=${SERVER_NAMES[j]}
    server_display=${SERVER_DISPLAYS[j]}
    
    echo "  - ${server_display}: 처리 시작"
    
    # fio 설치 여부 확인 및 필요시 설치 후 디스크 warm-up 실행 (백그라운드로 실행)
    (
      ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no $SSH_USER@$server_ip "
        echo '${server_display}: fio 설치 여부 확인 중...'
        if ! command -v fio &> /dev/null; then
          echo '${server_display}: fio가 설치되어 있지 않습니다. 설치를 시작합니다...'
          sudo apt-get update -qq > /dev/null 2>&1 || echo '${server_display}: apt-get update 실패'
          sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y fio > /dev/null || {
            echo '${server_display}: fio 설치 실패!'
            exit 1
          }
          echo '${server_display}: fio 설치 완료!'
        else
          echo '${server_display}: fio가 이미 설치되어 있습니다.'
        fi
        
        echo '${server_display}: 디스크 warm-up 시작...'
        sudo fio --filename=/dev/nvme0n1 --rw=read --bs=1M --iodepth=32 --ioengine=libaio --direct=1 --name=volume-initialize || {
          echo '${server_display}: 디스크 warm-up 실패!'
          exit 1
        }

        echo '${server_display}: 디스크 warm-up 완료!'
        exit 0
      "
      
      # SSH 명령이 성공적으로 완료되었는지 확인
      if [ $? -eq 0 ]; then
        echo "  - ${server_display}: 디스크 warm-up 작업 완료, 완료 목록에 기록 중..."
        echo "${server_name}|${server_ip}|completed" >> "$COMPLETED_SERVERS_FILE"
      else
        echo "  - ${server_display}: 작업 실패!"
      fi
    ) &  # 백그라운드로 실행
  done
  
  # 현재 배치의 모든 백그라운드 작업이 완료될 때까지 대기
  wait
  
  echo "배치 $CURRENT_BATCH/$TOTAL_BATCHES 완료!"
  
  # 마지막 배치가 아니면 대기
  if [ $((i + BATCH_SIZE)) -lt ${#SERVER_IPS[@]} ]; then
    echo "다음 배치 전 ${WAIT_TIME}초 대기 중..."
    sleep $WAIT_TIME
  fi
done

echo "모든 서버 디스크 warm-up 작업이 완료되었습니다."
echo "완료된 서버 목록은 $COMPLETED_SERVERS_FILE 파일에 저장되었습니다."
