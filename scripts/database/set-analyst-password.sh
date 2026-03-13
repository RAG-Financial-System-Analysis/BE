#!/bin/bash
aws cognito-idp admin-set-user-password \
  --user-pool-id "ap-southeast-1_VTLpFeyhi" \
  --username "analyst@rag.com" \
  --password "Analyst@123!!" \
  --permanent \
  --region "ap-southeast-1"