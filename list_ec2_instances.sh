#!/bin/bash

# 필요한 변수들
EC2_NAME="scipion"

# AWS 리전 설정 (Oregon)
AWS_REGION="us-west-2"

# AWS CLI 페이저 비활성화
export AWS_PAGER=""

echo "Name,InstanceId,PublicDnsName,PublicIpAddress,State" > ec2_instances.csv
aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Name,Values=${EC2_NAME}*" "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value | [0], InstanceId, PublicDnsName, PublicIpAddress, State.Name]' \
  --output json | jq -r '.[][] | @csv' | tee -a ec2_instances.csv
