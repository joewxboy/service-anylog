#!make

SHELL := /bin/bash
ifneq ($(filter check,$(MAKECMDGOALS)), )
        EDGELAKE_TYPE = $(EDGLAKE_TYPE)
else
        EDGELAKE_TYPE := generic
endif

# Docker configurations
export ARCH := $(shell uname -m)
export DOCKER_IMAGE_BASE ?= anylogco/edgelake
export DOCKER_IMAGE_NAME ?= edgelake
export DOCKER_HUB_ID ?= anylogco
export DOCKER_IMAGE_VERSION ?= latest
ifeq ($(ARCH),aarch64)
    export DOCKER_IMAGE_VERSION ?= latest-arm64
    export ARCH=arm64
else ifeq ($(ARCH),arm64)
    export DOCKER_IMAGE_VERSION ?= latest-arm64
    export ARCH=arm64
endif

# Open Horizon Configs
export HZN_ORG_ID ?= myorg
export HZN_LISTEN_IP ?= 127.0.0.1
export SERVICE_NAME ?= service-edgelake-$(EDGELAKE_TYPE)
export SERVICE_VERSION ?= latest

# Node Deployment configs
export EDGELAKE_NODE_NAME := $(shell cat docker-makefiles/edgelake_${EDGELAKE_TYPE}.env | grep NODE_NAME | awk -F "=" '{print $$2}')
export EDGELAKE_VOLUME := $(EDGELAKE_NODE_NAME)-anylog
export BLOCKCHAIN_VOLUME := $(EDGELAKE_NODE_NAME)-blockchain
export DATA_VOLUME := $(EDGELAKE_NODE_NAME)-data
export LOCAL_SCRIPTS_VOLUME := $(EDGELAKE_NODE_NAME)-local-scripts
export TCP_PORT := $(shell cat docker-makefiles/edgelake_${EDGELAKE_TYPE}.env | grep ANYLOG_SERVER_PORT | awk -F "=" '{print $$2}')
export REST_PORT := $(shell cat docker-makefiles/edgelake_${EDGELAKE_TYPE}.env | grep ANYLOG_REST_PORT | awk -F "=" '{print $$2}')
export BROKER_PORT := $(shell cat docker-makefiles/edgelake_${EDGELAKE_TYPE}.env | grep ANYLOG_BROKER_PORT | awk -F "=" '{print $$2}')

# Env Variables
include docker-makefiles/edgelake_${EDGELAKE_TYPE}.env
export

# Docker deployment call
DOCKER_COMPOSE := $(shell command -v docker-compose 2>/dev/null || echo "docker compose")

help: help-docker help-open-horizon
generate-docker-compose:
	EDGELAKE_TYPE=$(EDGELAKE_TYPE) ANYLOG_SERVER_PORT=${TCP_PORT} ANYLOG_REST_PORT=${REST_PORT} envsubst < docker-makefiles/docker-compose-template.yaml > docker-makefiles/docker-compose.yaml
remove-docker-compose:
	@rm -rf docker-makefiles/docker-compose.yaml
check:
	@echo "====================="
	@echo "ENVIRONMENT VARIABLES"
	@echo "====================="
	@echo "EDGELAKE_TYPE          default: generic                               actual: ${EDGELAKE_TYPE}"
	@echo "DOCKER_IMAGE_BASE      default: anylogco/edgelake                     actual: ${DOCKER_IMAGE_BASE}"
	@echo "DOCKER_IMAGE_NAME      default: edgelake                              actual: ${DOCKER_IMAGE_NAME}"
	@echo "DOCKER_IMAGE_VERSION   default: latest                                actual: ${DOCKER_IMAGE_VERSION}"
	@echo "DOCKER_HUB_ID          default: anylogco                              actual: ${DOCKER_HUB_ID}"
	@echo "HZN_ORG_ID             default: myorg                                 actual: ${HZN_ORG_ID}"
	@echo "HZN_LISTEN_IP          default: 127.0.0.1                             actual: ${HZN_LISTEN_IP}"
	@echo "SERVICE_NAME                                                          actual: ${SERVICE_NAME}"
	@echo "SERVICE_VERSION                                                       actual: ${SERVICE_VERSION}"
	@echo "==================="
	@echo "EDGELAKE DEFINITION"
	@echo "==================="
	@echo "NODE_TYPE              default: generic                               actual: ${NODE_TYPE}"
	@echo "NODE_NAME              default: edgelake-node                         actual: ${NODE_NAME}"
	@echo "COMPANY_NAME           default: New Company                           actual: ${COMPANY_NAME}"
	@echo "ANYLOG_SERVER_PORT     default: 32548                                 actual: ${ANYLOG_SERVER_PORT}"
	@echo "ANYLOG_REST_PORT       default: 32549                                 actual: ${ANYLOG_REST_PORT}"
	@echo "LEDGER_CONN            default: 127.0.0.1:32049                       actual: ${LEDGER_CONN}"
	@echo ""
test-conn:
	@echo "REST Connection Info for testing (Example: 127.0.0.1:32149):"
	@read CONN; \
	echo $$CONN > conn.tmp
	
build:
	@echo "Pulling image $(DOCKER_IMAGE_BASE):$(DOCKER_IMAGE_VERSION)"
	docker pull $(DOCKER_IMAGE_BASE):$(DOCKER_IMAGE_VERSION)
up: generate-docker-compose
	@echo "Deploying EdgeLake with config file: edgelake_$(EDGELAKE_TYPE).env"
	@$(DOCKER_COMPOSE) -f docker-makefiles/docker-compose.yaml up -d
	#@$(MAKE) remove-docker-compose
down: generate-docker-compose
	@echo "Stopping EdgeLake with config file: edgelake_$(EDGELAKE_TYPE).env"
	$(DOCKER_COMPOSE) -f docker-makefiles/docker-compose.yaml down
	@$(MAKE) remove-docker-compose
clean-volume: generate-docker-compose
	@echo "Cleaning EdgeLake with config file: edgelake_$(EDGELAKE_TYPE).env"
	@$(DOCKER_COMPOSE) -f docker-makefiles/docker-compose.yaml down -v
	@$(MAKE) remove-docker-compose
clean: generate-docker-compose
	@echo "Cleaning EdgeLake with config file: edgelake_$(EDGELAKE_TYPE).env"
	@$(DOCKER_COMPOSE) -f docker-makefiles/docker-compose.yaml down -v --rmi all
	@$(MAKE) remove-docker-compose
test-node: test-conn
	@CONN=$$(cat conn.tmp); \
	echo "Node State against $$CONN"; \
	curl -X GET http://$$CONN -H "command: get status"    -H "User-Agent: AnyLog/1.23" -w "\n"; \
	curl -X GET http://$$CONN -H "command: test node"     -H "User-Agent: AnyLog/1.23" -w "\n"; \
	curl -X GET http://$$CONN -H "command: get processes" -H "User-Agent: AnyLog/1.23" -w "\n"; \
	rm -rf conn.tmp
 
test-network: test-conn
	@CONN=$$(cat conn.tmp); \
	echo "Test Network Against: $$CONN"; \
	curl -X GET http://$$CONN -H "command: test network" -H "User-Agent: AnyLog/1.23" -w "\n"; \
	rm -rf conn.tmp
attach:
	@docker attach --detach-keys=ctrl-d $(EDGELAKE_NODE_NAME)
logs:
	@docker logs $(EDGELAKE_NODE_NAME)

publish: publish-service publish-service-policy publish-deployment-policy
hzn-clean: hzn-clean remove-deployment-policy remove-service-policy remove-service

# Pull, not push, Docker image since provided by third party
publish-service:
	@echo "=================="
	@echo "PUBLISHING SERVICE"
	@echo "=================="
	@echo ${HZN_EXCHANGE_USER_AUTH}
	@echo hzn exchange service publish --org=${HZN_ORG_ID} -u ${HZN_EXCHANGE_USER_AUTH} -O -P --json-file=service.definition.json
	@hzn exchange service publish --org=${HZN_ORG_ID} --user-pw=${HZN_EXCHANGE_USER_AUTH} -O -P --json-file=service.definition.json
	@echo ""
remove-service:
	@echo "=================="
	@echo "REMOVING SERVICE"
	@echo "=================="
	@hzn exchange service remove -f $(HZN_ORG_ID)/$(SERVICE_NAME)_$(SERVICE_VERSION)_$(ARCH)
	@echo ""

publish-service-policy:
	@echo "========================="
	@echo "PUBLISHING SERVICE POLICY"
	@echo "========================="
	@hzn exchange service addpolicy --org=${HZN_ORG_ID} --user-pw=${HZN_EXCHANGE_USER_AUTH} -f service.policy.json $(HZN_ORG_ID)/$(SERVICE_NAME)_$(SERVICE_VERSION)_$(ARCH)
	@echo ""
remove-service-policy:
	@echo "======================="
	@echo "REMOVING SERVICE POLICY"
	@echo "======================="
	@hzn exchange service removepolicy -f $(HZN_ORG_ID)/$(SERVICE_NAME)_$(SERVICE_VERSION)_$(ARCH)
	@echo ""

publish-deployment-policy:
	@echo "============================"
	@echo "PUBLISHING DEPLOYMENT POLICY"
	@echo "============================"
	@if [ "$(EDGELAKE_TYPE)" = "operator" ] && [ -n "$(BROKER_PORT)" ]; then \
            hzn exchange deployment addpolicy --org=$(HZN_ORG_ID) --user-pw=$(HZN_EXCHANGE_USER_AUTH) -f deployment-policies/operator_broker.json $(HZN_ORG_ID)/policy-$(SERVICE_NAME)_$(SERVICE_VERSION) ; \
        elif [ "$(EDGELAKE_TYPE)" = "operator" ]; then \
            hzn exchange deployment addpolicy --org=$(HZN_ORG_ID) --user-pw=$(HZN_EXCHANGE_USER_AUTH) -f deployment-policies/operator.json $(HZN_ORG_ID)/policy-$(SERVICE_NAME)_$(SERVICE_VERSION) ; \
        elif [ -n "$(BROKER_PORT)" ]; then \
            hzn exchange deployment addpolicy --org=$(HZN_ORG_ID) --user-pw=$(HZN_EXCHANGE_USER_AUTH) -f deployment-policies/generic_broker.json $(HZN_ORG_ID)/policy-$(SERVICE_NAME)_$(SERVICE_VERSION) ; \
        else \
            hzn exchange deployment addpolicy --org=$(HZN_ORG_ID) --user-pw=$(HZN_EXCHANGE_USER_AUTH) -f deployment-policies/generic.json $(HZN_ORG_ID)/policy-$(SERVICE_NAME)_$(SERVICE_VERSION) ; \
        fi
	@echo ""
remove-deployment-policy:
	@echo "=========================="
	@echo "REMOVING DEPLOYMENT POLICY"
	@echo "=========================="
	@hzn exchange deployment removepolicy -f $(HZN_ORG_ID)/policy-$(SERVICE_NAME)_$(SERVICE_VERSION)
	@echo ""

agent-run:
	@echo "================"
	@echo "REGISTERING NODE"
	@echo "================"
	@hzn register --name=hzn-client --policy=node.policy.json
	@watch hzn agreement list
hzn-clean:
	@echo "==================="
	@echo "UN-REGISTERING NODE"
	@echo "==================="
	@hzn unregister -f
	@echo ""
help-docker:
	@echo "====================="
	@echo "Docker Deployment Options"
	@echo "====================="
	@echo "build            pull latest image for $(DOCKER_IMAGE_BASE):$(DOCKER_IMAGE_VERSION)"
	@echo "up               bring up docker container based on EDGELAKE_TYPE"
	@echo "attach           attach to docker container based on EDGELAKE_TYPE"
	@echo "logs             view docker container logs based on EDGELAKE_TYPE"
	@echo "down             stop docker container based on EDGELAKE_TYPE"
	@echo "clean            (stop and) remove volumes and images for a docker container basd on EDGELAKE_TYPE"
	@echo "tset-node        using cURL make sure EdgeLake is accessible and is configured properly"
	@echo "test-network     using cURL make sure EdgeLake node is able to communicate with nodes in the network"
help-open-horizon:
	@echo "=============================="
	@echo "OpenHorizon Deployment Options"
	@echo "=============================="
	@echo "publish-service            publish service to OpenHorizon"
	@echo "remove-service             remove service from OpenHorizon"
	@echo "publish-service-policy     publish service policy to OpenHorizon"
	@echo "remove-service-policy      remove service policy from OpenHorizon"
	@echo "publish-deployment-policy  publish deployment policy to OpenHorizon"
	@echo "remove-deployment-policy   remove deployment policy from OpenHorizon"
	@echo "agent-run                  start OpenHorizon service"
	@echo "hzn-clean                  stop OpenHorizon service"
