-include .env

# update interfaces from the hub
tests :; cp hub/src/interfaces/* interfaces && forge test

### ----- TESTNET Operations ------- ###

# Deploys on test networks - can be used to test layerZero workflows
# @requires private key with testnet eth in .env
# @requires etherscan key for the block explorer in .env
# Remove 'broadcast' to preview the transaction
# You can sometimes set --resume if the tx is struggling
# NB: order of commands matters
# Etherscan verification is hit and miss on some networks. Arbitrum, Avax, FTM seem to work.

# Stage 1: Deploy components (Testnets)

deploy-arbitrum-test :; forge script DeployArbitrumRinkeby \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${ARBITRUM_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--verify \
	-vvvv

deploy-polygon-test :; forge script script/Deploy.s.sol:DeployPolygonMumbai \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${POLYGONSCAN_KEY} \
	--rpc-url https://polygon-mumbai.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--verify \
	-vvvv

deploy-optimism-test :; forge script script/Deploy.s.sol:DeployOptimismKovan \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${OPTIMISTIC_KEY} \
	--rpc-url https://optimism-kovan.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--verify \
	-vvvv

deploy-avax-test :; forge script script/Deploy.s.sol:DeployAvaxFuji \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${AVAXSCAN_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	--verify \
	-vvvv	
	

deploy-avax-test-existing-vault :; forge script DeployAvaxFujiExistingVault \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${AVAXSCAN_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	--verify \
	-vvvv	

deploy-arbitrum-test-existing-vault :; forge script DeployArbitrumRinkebyExistingVault \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${ARBITRUM_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--verify \
	-vvvv


deploy-ftm-test :; forge script script/Deploy.s.sol:DeployFTMTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${FTMSCAN_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	--verify \
	-vvvv		

# Stage 2: Prepare components by setting up neccessary permissions

prepare-deposit-arbitrum-avax-test :; forge script DepositPrepareArbitrumToAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${ARBITRUM_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	-vvvv

prepare-deposit-arbitrum-ftm-test :; forge script DepositPrepareArbitrumToFTMTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${ARBITRUM_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	-vvvv

prepare-deposit-avax-arbitrum-test :; forge script DepositPrepareAvaxToArbitrumTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${AVAXSCAN_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv


prepare-deposit-avax-ftm-test :; forge script script/Deploy.s.sol:DepositPrepareAvaxToFTMTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${AVAXSCAN_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--verify \
	--broadcast \
	-vvvv	

prepare-deposit-ftm-arbitrum-test :; forge script script/Deploy.s.sol:DepositPrepareFTMToArbitrumTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${FTMSCAN_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--verify \
	--broadcast \
	-vvvv

prepare-deposit-ftm-avax-test :; forge script script/Deploy.s.sol:DepositPrepareFTMToAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${FTMSCAN_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--verify \
	--broadcast \
	-vvvv

# Stage 3: Make a deposit into the source chain vault
deposit-avax-vault-test :; forge script DepositIntoAvaxVaultTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv

# Note: Arbitrum testnets appear to fail with OOG error unless you 'skip simulation'
deposit-arbitrum-vault-test :; forge script DepositIntoArbitrumVaultTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--skip-simulation \
	-vvvv 


deposit-ftm-vault-test :; forge script script/Deploy.s.sol:DepositIntoFTMVaultTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 


# Stage 4.1: Prepare the XChain Deposit from the XChainStrategy
# Note: Arbitrum testnets appear to fail with OOG error unless you 'skip simulation'
xchain-deposit-prepare-avax-arbitrum-test :; forge script XChainPrepareDepositAvaxToArbitrumTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv 

xchain-deposit-prepare-arbitrum-avax-test :; forge script XChainPrepareDepositArbitrumToAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--skip-simulation \
	--broadcast \
	-vvvv 

# Stage 4.2 Deposit into the XChainStrategy 
xchain-deposit-strategy-avax-test :; forge script DepositIntoXChainStrategyAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv 

# Stage 4.3 Depositinto the vault
xchain-deposit-avax-arbitrum-test :; forge script XChainDepositAvaxToArbitrumTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv 


# Stage 5: Update remote hubs with strategy report
xchain-report-avax-ftm-test :; forge script script/Deploy.s.sol:XChainReportAvaxToFTMTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv 

xchain-report-arbitrum-ftm-test :; forge script script/Deploy.s.sol:XChainReportArbitrumToFTMTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	-vvvv 

xchain-report-arbitrum-avax-test :; forge script XChainReportArbitrumToAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	-vvvv 	

xchain-report-ftm-arbitrum-test :; forge script script/Deploy.s.sol:XChainReportFTMToArbitrumTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 

xchain-report-ftm-avax-test :; forge script script/Deploy.s.sol:XChainReportFTMToAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 


# Stage 6: Permit exit of vaults
set-exiting-arbitrum-test :; forge script SetExitingArbitrumTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	-vvvv 


set-exiting-ftm-test :; forge script script/Deploy.s.sol:SetExitingFTMTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 


set-exiting-avax-test :; forge script script/Deploy.s.sol:SetExitingAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv

# stage 7: Request the withdraw
xchain-request-withdraw-avax-ftm-test :; forge script script/Deploy.s.sol:XChainRequestWithdrawAvaxToFTMTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv

xchain-request-withdraw-avax-arbitrum-test :; forge script XChainRequestWithdrawAvaxToArbitrumTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv


xchain-request-withdraw-ftm-avax-test :; forge script script/Deploy.s.sol:XChainRequestWithdrawFTMToAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 


xchain-request-withdraw-arbitrum-ftm-test :; forge script script/Deploy.s.sol:XChainRequestWithdrawArbitrumToFTMTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	-vvvv 

# Stage 8, exit the vault
exit-vault-avax :; forge script script/Deploy.s.sol:ExitVaultAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv

exit-vault-arbitrum :; forge script ExitVaultArbitrumTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--skip-simulation \
	--broadcast \
	-vvvv 

exit-vault-ftm :; forge script script/Deploy.s.sol:ExitVaultFTMTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 

# Stage 9, send tokens back
xchain-finalize-withdraw-avax-ftm-test :; forge script script/Deploy.s.sol:XChainFinalizeWithdrawAvaxToFTMTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv

xchain-finalize-withdraw-ftm-avax-test :; forge script script/Deploy.s.sol:XChainFinalizeWithdrawFTMToAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 

xchain-finalize-withdraw-arbitrum-avax-test :; forge script XChainFinalizeWithdrawArbitrumToAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	-vvvv 

# Stage 10 - remove tokens from the hub
hub-withdraw-ftm-test :; forge script script/Deploy.s.sol:HubWithdrawFTMTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 

hub-withdraw-avax-test :; forge script HubWithdrawAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv

# Stage 11 - remember to report on the origin chain!

######## SEE ABOVE ##########

# Stage 12 - exit the strategy

strategy-withdraw-ftm-test :; forge script script/Deploy.s.sol:StrategyWithdrawFTMTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 


# Administrative: Redeploy a hub - ensuring you update all remotes to point to the new hub
redeploy-hub-arbitrum-test :; forge script RedeployXChainHubArbitrumTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	-vvvv 

update-hub-avax-arbitrum-test :; forge script UpdateHubAvaxToArbitrumTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv

redeploy-hub-avax-test :; forge script RedeployXChainHubAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	--verify \
	-vvvv

update-hub-arbitrum-avax-test :; forge script UpdateHubArbitrumToAvaxTest \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	-vvvv 


### Prod Deploys ###

# Polygon has issues with gas prices 
# https://github.com/foundry-rs/foundry/issues/1703
# tl;dr add --legacy flag
deploy-polygon-prod :; forge script DeployPolygonProduction \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${POLYGONSCAN_KEY} \
	--rpc-url https://polygon-rpc.com \
	--legacy \
	--verify \
	--broadcast \
	-vvvv

deploy-optimism-prod :; forge script DeployOptimismProduction \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--etherscan-api-key ${OPTIMISTIC_KEY} \
	--rpc-url https://optimism-mainnet.infura.io/v3/${INFURA_API_KEY} \
	--verify \
	--broadcast \
	-vvvv	

# Polygon has issues with gas prices 
# https://github.com/foundry-rs/foundry/issues/1703
# tl;dr add --legacy flag
deposit-prepare-polygon-arbitrum-prod :; forge script DepositPreparePolygonToArbitrumProd \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://polygon-rpc.com \
	--legacy \
	--broadcast \
	-vvvv

deposit-prepare-arbitrum-polygon-prod :; forge script DepositPrepareAritrumToPolygonProd \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-mainnet.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	-vvvv

deposit-prepare-polygon-optimism-prod :; forge script DepositPreparePolygonToOptimismProd \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://polygon-rpc.com \
	--broadcast \
	--legacy \
	-vvvv	

deposit-prepare-optimism-polygon-prod :; forge script DepositPrepareOptimismToPolygonProd \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://optimism-mainnet.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	-vvvv	

# Note the private key is different here
deposit-polygon-prod :; forge script DepositIntoPolygonVaultProd \
	--private-key ${DEPOSITOR_PRIVATE_KEY} \
	--rpc-url https://polygon-rpc.com \
	--legacy \
	--broadcast \
	-vvvv

xchain-deposit-prepare-arbitrum-polygon-prod :; forge script XChainPrepareDepositArbitrumFromPolygon \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-mainnet.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	-vvvv

xchain-deposit-prepare-polygon-optimism-prod :; forge script XChainPrepareDepositPolygonToOptimismProd \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://polygon-rpc.com \
	--broadcast \
	--legacy \
	-vvvv

xchain-deposit-prepare-optimism-polygon-prod :; forge script XChainPrepareDepositOptimismToPolygonProd \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://optimism-mainnet.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	-vvvv	

deposit-xchainstrategy-polygon-prod :; forge script DepositIntoXChainStrategyPolygonProd \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://polygon-rpc.com \
	--legacy \
	--broadcast \
	-vvvv

xchain-deposit-polygon-arbitrum-prod :; forge script XChainDepositPolygonToArbitrumProd \
	--rpc-url https://polygon-rpc.com \
	--legacy \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--broadcast \
	-vvvv

xchain-deposit-polygon-optimism-prod :; forge script XChainDepositPolygonToOptimismProd \
	--rpc-url https://polygon-rpc.com \
	--legacy \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--broadcast \
	-vvvv


# Administrative action: LayerZero changed chain ids
upgrade-chain-polygon-optimism-prod :; forge script UpgradePolygonToOptimismChainId \
	--etherscan-api-key ${POLYGONSCAN_KEY} \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://polygon-rpc.com \
	--legacy \
	--verify \
	--broadcast \
	-vvvv

upgrade-chain-optimism-polygon-prod :; forge script UpgradeOptimismToPolygonChainId \
	--etherscan-api-key ${OPTIMISTIC_KEY} \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://optimism-mainnet.infura.io/v3/${INFURA_API_KEY} \
	--verify \
	--broadcast \
	-vvvv


### -------- FORK Operations ---------- ####
# Cheaper, faster, less complicated than testnet. 
# Cannot be used for directly testing LayerZero workflows, but you can simulate the messages.

# runs local anvil fork on the selected network
fork-arbitrum :; anvil -f https://rpc.ankr.com/arbitrum -p ${PORT_ARBITRUM}
fork-optimism :; anvil -f https://rpc.ankr.com/optimism -p ${PORT_OPTIMISM}
fork-polygon :; anvil -f https://rpc.ankr.com/polygon -p ${PORT_POLYGON}

# deploy components to local fork
deploy-arbitrum-fork :; forge script script/Deploy.s.sol:DeployArbitrumProduction \
	-vvvv \
	--broadcast \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_ARBITRUM}

deploy-optimism-fork :; forge script DeployOptimismProduction \
	-vvvv \
	--broadcast \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_OPTIMISM}

deploy-polygon-fork :; forge script DeployPolygonProduction \
	-vvvv \
	--broadcast \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_POLYGON}

deposit-prepare-polygon-arbitrum-fork :; forge script DepositPreparePolygonToArbitrumProd \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_POLYGON} \
	--legacy \
	-vvvv

deposit-prepare-polygon-optimism-fork :; forge script DepositPreparePolygonToOptimismProd \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_POLYGON} \
	--legacy \
	-vvvv

deposit-prepare-optimism-polygon-fork :; forge script DepositPrepareOptimismToPolygonProd \
	-vvvv \
	--broadcast \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_OPTIMISM}

deposit-prepare-arbitrum-polygon-fork :; forge script DepositPrepareAritrumToPolygonProd \
	--broadcast \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_ARBITRUM}

deposit-polygon-fork :; forge script DepositIntoPolygonVaultProd \
	--private-key ${DEPOSITOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_POLYGON} \
	--legacy \
	-vvvv

xchain-deposit-prepare-arbitrum-polygon-fork :; forge script XChainPrepareDepositArbitrumFromPolygon \
	--broadcast \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_ARBITRUM}

xchain-deposit-prepare-polygon-optimism-fork :; forge script XChainPrepareDepositPolygonToOptimismProd \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_POLYGON} \
	--broadcast \
	--legacy \
	-vvvv

xchain-deposit-prepare-optimism-polygon-fork :; forge script XChainPrepareDepositOptimismToPolygonProd \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_OPTIMISM} \
	--broadcast \
	-vvvv	

deposit-xchainstrategy-polygon-fork :; forge script DepositIntoXChainStrategyPolygonProd \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_POLYGON} \
	--legacy \
	--broadcast \
	-vvvv
	
xchain-deposit-polygon-arbitrum-fork :; forge script XChainDepositPolygonToArbitrumProd \
	--broadcast \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_POLYGON}

xchain-deposit-polygon-optimism-fork :; forge script XChainDepositPolygonToOptimismProd \
	--broadcast \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_POLYGON}

set-exiting-arbitrum-fork :; forge script SetExitingArbitrumProd \
	--broadcast \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_ARBITRUM}


### DOCTOR ASSERTS ###

# Unlock multiple accounts
doctor-polygon :; forge script Doctor \
	-vvvv \
	--fork-url http://127.0.0.1:${PORT_POLYGON} \
	--private-keys ${GOVERNOR_PRIVATE_KEY} ${NON_GOVERNOR_PRIVATE_KEY}

doctor-arbitrum :; forge script Doctor \
	-vvvv \
	--fork-url http://127.0.0.1:${PORT_ARBITRUM} \
	--private-keys ${GOVERNOR_PRIVATE_KEY} ${NON_GOVERNOR_PRIVATE_KEY}


# Admin

admin-resume-deposit-arbitrum-fork :; forge script ResumeDepositArbitrumFork \
	--broadcast \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--fork-url http://127.0.0.1:${PORT_ARBITRUM}

admin-resume-deposit-arbitrum-prod :; forge script ResumeDepositArbitrumFork \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	--rpc-url https://arbitrum-mainnet.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	-vvvv

upgrade-chain-polygon-optimism-fork :; forge script UpgradePolygonToOptimismChainId \
	--fork-url http://127.0.0.1:${PORT_POLYGON} \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	-vvvv

upgrade-chain-optimism-polygon-fork :; forge script UpgradeOptimismToPolygonChainId \
	--fork-url http://127.0.0.1:${PORT_OPTIMISM} \
	--private-key ${GOVERNOR_PRIVATE_KEY} \
	-vvvv