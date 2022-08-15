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

# Stage 1: Deploy components

deploy-arbitrum-test :; forge script script/Deploy.s.sol:DeployArbitrumRinkeby \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${ARBITRUM_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--verify \
	--resume \
	-vvvv

deploy-polygon-test :; forge script script/Deploy.s.sol:DeployPolygonMumbai \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${POLYGONSCAN_KEY} \
	--rpc-url https://polygon-mumbai.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--verify \
	-vvvv

deploy-optimism-test :; forge script script/Deploy.s.sol:DeployOptimismKovan \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${OPTIMISTIC_KEY} \
	--rpc-url https://optimism-kovan.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--verify \
	-vvvv

deploy-avax-test :; forge script script/Deploy.s.sol:DeployAvaxFuji \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${AVAXSCAN_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	--verify \
	--resume \
	-vvvv	


deploy-ftm-test :; forge script script/Deploy.s.sol:DeployFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${FTMSCAN_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	--verify \
	-vvvv		

# Stage 2: Prepare components by setting up neccessary permissions

prepare-deposit-arbitrum-avax-test :; forge script script/Deploy.s.sol:DepositPrepareArbitrumToAvaxTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${ARBITRUM_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--verify \
	--broadcast \
	-vvvv

prepare-deposit-arbitrum-ftm-test :; forge script script/Deploy.s.sol:DepositPrepareArbitrumToFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${ARBITRUM_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--verify \
	--broadcast \
	-vvvv

prepare-deposit-avax-arbitrum-test :; forge script script/Deploy.s.sol:DepositPrepareAvaxToArbitrumTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${AVAXSCAN_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--verify \
	--broadcast \
	-vvvv


prepare-deposit-avax-ftm-test :; forge script script/Deploy.s.sol:DepositPrepareAvaxToFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${AVAXSCAN_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--verify \
	--broadcast \
	-vvvv	

prepare-deposit-ftm-arbitrum-test :; forge script script/Deploy.s.sol:DepositPrepareFTMToArbitrumTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${FTMSCAN_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--verify \
	--broadcast \
	-vvvv

prepare-deposit-ftm-avax-test :; forge script script/Deploy.s.sol:DepositPrepareFTMToAvaxTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${FTMSCAN_KEY} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--verify \
	--broadcast \
	-vvvv

# Stage 3: Make a deposit into the source chain vault
# Note: Arbitrum testnets appear to fail with OOG error unless you 'skip simulation'

deposit-avax-vault-test :; forge script script/Deploy.s.sol:DepositIntoAvaxVaultTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv

deposit-arbitrum-vault-test :; forge script script/Deploy.s.sol:DepositIntoArbitrumVaultTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--skip-simulation \
	-vvvv 


deposit-ftm-vault-test :; forge script script/Deploy.s.sol:DepositIntoFTMVaultTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 


# Stage 4: Execute the XChain Deposit from the XChainStrategy
# Note: Arbitrum testnets appear to fail with OOG error unless you 'skip simulation'

xchain-deposit-avax-arbitrum-test :; forge script script/Deploy.s.sol:XChainDepositAvaxToArbitrumTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv 

xchain-deposit-avax-ftm-test :; forge script script/Deploy.s.sol:XChainDepositAvaxToFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv 

xchain-deposit-arbitrum-avax-test :; forge script script/Deploy.s.sol:XChainDepositArbitrumToAvaxTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--skip-simulation \
	-vvvv 

xchain-deposit-arbitrum-ftm-test :; forge script script/Deploy.s.sol:XChainDepositArbitrumToFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--skip-simulation \
	-vvvv 

xchain-deposit-ftm-arbitrum-test :; forge script script/Deploy.s.sol:XChainDepositFTMToArbitrumTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--broadcast \
	--rpc-url https://rpc.testnet.fantom.network/ \
	-vvvv 

xchain-deposit-ftm-avax-test :; forge script script/Deploy.s.sol:XChainDepositFTMToAvaxTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 

# Stage 5: Update remote hubs with strategy report
xchain-report-avax-ftm-test :; forge script script/Deploy.s.sol:XChainReportAvaxToFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv 

xchain-report-arbitrum-ftm-test :; forge script script/Deploy.s.sol:XChainReportArbitrumToFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	-vvvv 

xchain-report-ftm-arbitrum-test :; forge script script/Deploy.s.sol:XChainReportFTMToArbitrumTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 

xchain-report-ftm-avax-test :; forge script script/Deploy.s.sol:XChainReportFTMToAvaxTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 


# Stage 6: Permit exit of vaults
set-exiting-arbitrum-test :; forge script script/Deploy.s.sol:SetExitingArbitrumTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
 	--broadcast \
	-vvvv 


set-exiting-ftm-test :; forge script script/Deploy.s.sol:SetExitingFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 


set-exiting-avax-test :; forge script script/Deploy.s.sol:SetExitingAvaxTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv

# stage 7: Request the withdraw
xchain-request-withdraw-avax-ftm-test :; forge script script/Deploy.s.sol:XChainRequestWithdrawAvaxToFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv


xchain-request-withdraw-ftm-avax-test :; forge script script/Deploy.s.sol:XChainRequestWithdrawFTMToAvaxTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 


xchain-request-withdraw-arbitrum-ftm-test :; forge script script/Deploy.s.sol:XChainRequestWithdrawArbitrumToFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	-vvvv 

# Stage 8, exit the vault
exit-vault-avax :; forge script script/Deploy.s.sol:ExitVaultAvaxTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv

exit-vault-ftm :; forge script script/Deploy.s.sol:ExitVaultFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 

# Stage 9, send tokens back
xchain-finalize-withdraw-avax-ftm-test :; forge script script/Deploy.s.sol:XChainFinalizeWithdrawAvaxToFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv

xchain-finalize-withdraw-ftm-avax-test :; forge script script/Deploy.s.sol:XChainFinalizeWithdrawFTMToAvaxTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 


# Stage 10 - remove tokens from the hub
hub-withdraw-ftm-test :; forge script script/Deploy.s.sol:HubWithdrawFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 

# Stage 11 - remember to report on the origin chain!

######## SEE ABOVE ##########

# Stage 12 - exit the strategy

strategy-withdraw-ftm-test :; forge script script/Deploy.s.sol:StrategyWithdrawFTMTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://rpc.testnet.fantom.network/ \
	--broadcast \
	-vvvv 

### -------- FORK Operations ---------- ####
# Cheaper, faster, less complicated than testnet. 
# Cannot be used for directly testing LayerZero workflows, but you can simulate the messages.

# runs local anvil fork on the selected network
fork-arbitrum :; anvil -f https://rpc.ankr.com/arbitrum -p ${PORT_ARBITRUM}
fork-optimism :; anvil -f https://rpc.ankr.com/optimism -p ${PORT_OPTIMISM}

# deploy components to local fork
deploy-fork-arbitrum :; forge script script/Deploy.s.sol:DeployArbitrum \
	-vvvv \
	--broadcast \
	--private-key ${PK_f39f_PUBLIC} \
	--fork-url http://127.0.0.1:${PORT_ARBITRUM}

deploy-fork-optimism :; forge script script/Deploy.s.sol:DeployOptimism \
	-vvvv \
	--broadcast \
	--private-key ${PK_f39f_PUBLIC} \
	--fork-url http://127.0.0.1:${PORT_OPTIMISM}
