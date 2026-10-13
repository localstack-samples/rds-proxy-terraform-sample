export AWS_ACCESS_KEY_ID ?= test
export AWS_SECRET_ACCESS_KEY ?= test
export AWS_DEFAULT_REGION=us-east-1
SHELL := /bin/bash

usage:		## Show this help
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$//' | sed -e 's/##//'

install:	## Install dependencies
	@which lstk || npm install -g @localstack/lstk

start:		## Start LocalStack
	@test -n "${LOCALSTACK_AUTH_TOKEN}" || (echo "LOCALSTACK_AUTH_TOKEN is not set. Find your token at https://app.localstack.cloud/workspace/auth-token"; exit 1)
	@LOCALSTACK_AUTH_TOKEN=$(LOCALSTACK_AUTH_TOKEN) lstk start

stop:		## Stop LocalStack
	@lstk stop


logs:		## Save the logs in a separate file
	@lstk logs > logs.txt

build:		## Build the Lambda functions
	cd api-lambdas && mvn -B clean package

deploy:		## Deploy infrastructure using Terraform
	cd terraform && lstk tf init && lstk tf apply --auto-approve

init-db:	## Create the dogs table and database users
	lstk aws lambda invoke --function-name db-setup --cli-read-timeout 120 output.json && cat output.json

test:		## Initialize the database and test the API end to end
	./test.sh

.PHONY: usage install start stop logs build deploy init-db test
