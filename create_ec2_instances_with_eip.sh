#!/bin/bash

# 필요한 변수들
EC2_COUNT=2                           # 생성할 EC2 인스턴스 수
EC2_NAME="scipion"                    # EC2 인스턴스 기본 이름 (test1, test2, ... 형태로 생성됨)
EC2_AMI="ami-0fe65056cfe1d7985"       # 사용할 AMI ID
EC2_VOLUME_SIZE=200                   # 루트 볼륨 크기(GiB)
INSTANCE_TYPE="m5.large"              # 인스턴스 타입
SECURITY_GROUP="scipion-sg"           # 보안 그룹 ID 또는 이름
KEY_NAME="ec2-oregon-key"             # 키 페어 이름 (비워두면 키 페어 없이 생성)

# AWS 리전 설정 (Oregon)
AWS_REGION="us-west-2"

# AWS CLI 페이저 비활성화
export AWS_PAGER=""

# 설정 정보 출력
echo "EC2 인스턴스 생성 설정:"
echo "==============================================="
echo "AWS 리전: $AWS_REGION"
echo "생성할 EC2 인스턴스 수: $EC2_COUNT"
echo "EC2 인스턴스 기본 이름: $EC2_NAME"
echo "사용할 AMI ID: $EC2_AMI"
echo "루트 볼륨 크기: $EC2_VOLUME_SIZE GiB"
echo "인스턴스 타입: $INSTANCE_TYPE"
echo "보안 그룹: $SECURITY_GROUP"
echo "키 페어: $KEY_NAME"
echo "==============================================="

# 키 페어 옵션 설정
KEY_OPTION=""
if [ ! -z "$KEY_NAME" ]; then
    KEY_OPTION="--key-name $KEY_NAME"
fi

# 인스턴스 ID와 EIP 할당 ID를 저장할 배열
declare -a INSTANCE_IDS
declare -a EIP_ALLOCATION_IDS

# EC2 인스턴스 생성 및 EIP 할당
for i in $(seq 1 $EC2_COUNT); do
    echo "[$i/$EC2_COUNT] EC2 인스턴스 생성 중: ${EC2_NAME}${i}..."
    
    # EC2 인스턴스 생성
    INSTANCE_ID=$(aws ec2 run-instances \
        --region $AWS_REGION \
        --image-id $EC2_AMI \
        --instance-type $INSTANCE_TYPE \
        --security-group-ids $SECURITY_GROUP \
        $KEY_OPTION \
        --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$EC2_VOLUME_SIZE,\"DeleteOnTermination\":true}}]" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${EC2_NAME}${i}}]" \
        --output text \
        --query 'Instances[0].InstanceId')
    
    if [ $? -ne 0 ]; then
        echo "EC2 인스턴스 생성 실패: ${EC2_NAME}${i}"
        continue
    fi
    
    echo "EC2 인스턴스 생성 완료: ${EC2_NAME}${i} (ID: $INSTANCE_ID)"
    INSTANCE_IDS+=("$INSTANCE_ID")
    
    # EIP 할당
    echo "Elastic IP 할당 중..."
    EIP_ALLOCATION_ID=$(aws ec2 allocate-address \
        --region $AWS_REGION \
        --domain vpc \
        --output text \
        --query 'AllocationId')
    
    if [ $? -ne 0 ]; then
        echo "Elastic IP 할당 실패"
        continue
    fi
    
    EIP_ALLOCATION_IDS+=("$EIP_ALLOCATION_ID")
    echo "Elastic IP 할당 완료: $EIP_ALLOCATION_ID"
    
    # 인스턴스가 실행 상태가 될 때까지 대기
    echo "인스턴스가 실행 상태가 될 때까지 대기 중..."
    aws ec2 wait instance-running --region $AWS_REGION --instance-ids $INSTANCE_ID
    
    # EIP를 EC2 인스턴스에 연결
    echo "Elastic IP를 EC2 인스턴스에 연결 중..."
    aws ec2 associate-address \
        --region $AWS_REGION \
        --allocation-id $EIP_ALLOCATION_ID \
        --instance-id $INSTANCE_ID
    
    if [ $? -ne 0 ]; then
        echo "Elastic IP 연결 실패: $EIP_ALLOCATION_ID -> $INSTANCE_ID"
    else
        echo "Elastic IP 연결 완료: $EIP_ALLOCATION_ID -> $INSTANCE_ID"
    fi
    
    echo ""
    sleep 1
done

# 생성된 리소스 요약
echo "생성된 리소스 요약:"
echo "총 $EC2_COUNT 개의 EC2 인스턴스 생성 요청됨"
echo "생성된 인스턴스 ID: ${INSTANCE_IDS[@]}"
echo "할당된 EIP 할당 ID: ${EIP_ALLOCATION_IDS[@]}"

# 생성된 인스턴스 정보 조회
echo ""
echo "생성된 인스턴스 정보:"
aws ec2 describe-instances \
    --region $AWS_REGION \
    --instance-ids ${INSTANCE_IDS[@]} \
    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name,PublicIpAddress]' \
    --output table
