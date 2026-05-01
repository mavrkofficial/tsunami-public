# ─── Tsunami V3 on Ink ─────────────────────────────────────────
-include .env

INK_RPC   ?= $(INK_RPC_URL)
CHAIN_ID  := 57073
GAS_PRICE := 10000000  # 0.01 gwei — Ink is dirt cheap

# ── Forge binary (works from Git Bash, PowerShell, or cmd) ───
# Foundry installs to ~/.foundry/bin which isn't always on PATH.
FORGE := $(shell which forge 2>/dev/null || echo $(USERPROFILE)/.foundry/bin/forge.exe)

# ── Build ────────────────────────────────────────────────────
.PHONY: build clean

build:
	$(FORGE) build

clean:
	$(FORGE) clean

# ── Deploy (dry-run – add --broadcast to send tx) ───────────
.PHONY: deploy-core deploy-router deploy-all

deploy-core:
	$(FORGE) script script/deploy/DeployTsunamiV3Core.s.sol \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		-vvvv

deploy-router:
	$(FORGE) script script/deploy/DeployTsunamiUniversalRouter.s.sol \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		-vvvv

deploy-all: deploy-core deploy-router deploy-sentry deploy-citadel

# ── Deploy (broadcast – actually sends tx) ───────────────────
.PHONY: deploy-core-broadcast deploy-router-broadcast

deploy-core-broadcast:
	$(FORGE) script script/deploy/DeployTsunamiV3Core.s.sol \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://explorer.inkonchain.com/api/ \
		-vvvv

deploy-router-broadcast:
	$(FORGE) script script/deploy/DeployTsunamiUniversalRouter.s.sol \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://explorer.inkonchain.com/api/ \
		-vvvv

# ── Deploy Sentry Pool Manager (UNVERIFIED — proprietary params) ──
# Deploy this FIRST, then set POOL_MANAGER in .env before deploy-sentry
.PHONY: deploy-poolmanager deploy-poolmanager-broadcast

deploy-poolmanager:
	$(FORGE) create contracts/sentry/SentryPoolManagerETH.sol:SentryLowCapPoolManagerETH \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE)

deploy-poolmanager-broadcast:
	@echo "=== Deploying SentryPoolManagerETH (UNVERIFIED) ==="
	$(FORGE) create contracts/sentry/SentryPoolManagerETH.sol:SentryLowCapPoolManagerETH \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE)
	@echo ">> Copy the deployed address above into .env as POOL_MANAGER="

# ── Deploy Sentry Launchpad ─────────────────────────────────────
# Requires: NPM_ADDRESS (from deploy-core), TREASURY, WETH9
# Set POOL_MANAGER in .env first (from deploy-poolmanager-broadcast)
.PHONY: deploy-sentry deploy-sentry-broadcast

deploy-sentry:
	$(FORGE) script script/deploy/DeploySentryLaunchpad.s.sol \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		-vvvv

deploy-sentry-broadcast:
	$(FORGE) script script/deploy/DeploySentryLaunchpad.s.sol \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://explorer.inkonchain.com/api/ \
		-vvvv

# ── Redeploy periphery only (re-uses existing V3_FACTORY) ──────
# Requires: V3_FACTORY, WETH9 (optionally GELATO_TRUSTED_FORWARDER)
.PHONY: redeploy-periphery redeploy-periphery-broadcast

redeploy-periphery:
	$(FORGE) script script/deploy/RedeployPeriphery.s.sol \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		-vvvv

redeploy-periphery-broadcast:
	$(FORGE) script script/deploy/RedeployPeriphery.s.sol \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://explorer.inkonchain.com/api/ \
		-vvvv

# ── Deploy Citadel LP Locker ──────────────────────────────────────
# Requires: NPM_ADDRESS (from deploy-core), WETH9, TREASURY, TYDRO_POOL
.PHONY: deploy-citadel deploy-citadel-broadcast

deploy-citadel:
	$(FORGE) script script/deploy/DeployCitadel.s.sol \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		-vvvv

deploy-citadel-broadcast:
	$(FORGE) script script/deploy/DeployCitadel.s.sol \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://explorer.inkonchain.com/api/ \
		-vvvv

# ── Deploy CitadelV2 Implementation + Upgrade Proxy ───────────────
# V2 removes auto-Tydro supply from collectFees and makes Tydro user-self-service.
# Flow: (1) make deploy-citadel-v2-broadcast -> note the logged address
#       (2) export CITADEL_V2_IMPL=0x... -> make upgrade-citadel-proxy-broadcast
.PHONY: deploy-citadel-v2 deploy-citadel-v2-broadcast \
        upgrade-citadel-proxy upgrade-citadel-proxy-broadcast

deploy-citadel-v2:
	$(FORGE) script script/deploy/DeployCitadelV2.s.sol:DeployCitadelV2 \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		-vvvv

deploy-citadel-v2-broadcast:
	$(FORGE) script script/deploy/DeployCitadelV2.s.sol:DeployCitadelV2 \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://explorer.inkonchain.com/api/ \
		-vvvv

# Requires CITADEL_V2_IMPL env var (from deploy-citadel-v2-broadcast output).
# PRIVATE_KEY must be the ProxyAdmin owner on 0x915c2E6b...6F63.
upgrade-citadel-proxy:
	$(FORGE) script script/deploy/UpgradeCitadelProxy.s.sol:UpgradeCitadelProxy \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		-vvvv

upgrade-citadel-proxy-broadcast:
	$(FORGE) script script/deploy/UpgradeCitadelProxy.s.sol:UpgradeCitadelProxy \
		--rpc-url $(INK_RPC) \
		--chain-id $(CHAIN_ID) \
		--private-key $(PRIVATE_KEY) \
		--gas-price $(GAS_PRICE) \
		--broadcast \
		-vvvv

# ── Full deploy (all four scripts) ────────────────────────────
.PHONY: deploy-all-broadcast
deploy-all-broadcast: deploy-core-broadcast deploy-router-broadcast deploy-sentry-broadcast deploy-citadel-broadcast

# ── Verify a single contract (Blockscout — no API key needed) ─
# Usage: make verify ADDR=0x... CONTRACT=contracts/Foo.sol:Foo
.PHONY: verify
verify:
	$(FORGE) verify-contract $(ADDR) $(CONTRACT) \
		--chain-id $(CHAIN_ID) \
		--verifier blockscout \
		--verifier-url https://explorer.inkonchain.com/api/
