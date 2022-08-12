# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# update interfaces from the hub
tests :; cp hub/src/interfaces/* interfaces && forge test

# runs a preview of the deploy on the arbitrum testnet
deploy-preview-arbitrum-test :; forge script script/Deploy.s.sol:DeployArbitrumRinkeby \
	-vvvv \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY}


# runs a preview of the deploy on the optimism testnet
deploy-preview-optimism-test :; forge script script/Deploy.s.sol:DeployOptimismKovan \
	-vvvv \
	--fork-url https://optimism-kovan.infura.io/v3/${INFURA_API_KEY}


# deploys on the arbitrum testnet
# Note: order of commands matters
deploy-arbitrum-test :; forge script script/Deploy.s.sol:DeployArbitrumRinkeby \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${ARBITRUM_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--verify \
	-vvvv

# deploys on the polygon mumbai testnet
# Note: order of commands matters
deploy-polygon-test :; forge script script/Deploy.s.sol:DeployPolygonMumbai \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${POLYGONSCAN_KEY} \
	--rpc-url https://polygon-mumbai.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--verify \
	-vvvv


# deploys on the optimism testnet
# Note: order of commands matters
deploy-optimism-test :; forge script script/Deploy.s.sol:DeployOptimismKovan \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${OPTIMISTIC_KEY} \
	--rpc-url https://optimism-kovan.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--verify \
	-vvvv

# deploys on the avalanche fuji testnet
# Note: order of commands matters
deploy-avax-test :; forge script script/Deploy.s.sol:DeployAvaxFuji \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${AVAXSCAN_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--resume \
	--broadcast \
	--verify \
	-vvvv	

# run forks (mainnets only)
fork-arbitrum :; anvil -f https://rpc.ankr.com/arbitrum -p ${PORT_ARBITRUM}

fork-optimism :; anvil -f https://rpc.ankr.com/optimism -p ${PORT_OPTIMISM}

# runs a preview of the deploy on a local fork of the arbitrum mainnet 
deploy-fork-arbitrum :; forge script script/Deploy.s.sol:DeployArbitrum \
	-vvvv \
	--broadcast \
	--private-key ${PK_f39f_PUBLIC} \
	--fork-url http://127.0.0.1:${PORT_ARBITRUM}

# runs a preview of the deploy on a local fork of the optimism mainnet 
deploy-fork-optimism :; forge script script/Deploy.s.sol:DeployOptimism \
	-vvvv \
	--broadcast \
	--private-key ${PK_f39f_PUBLIC} \
	--fork-url http://127.0.0.1:${PORT_OPTIMISM}


# Prepare for a XChain Deposit SRC as Arbitrum dst Avax Fuji
prepare-deposit-arbitrum-avax-test :; forge script script/Deploy.s.sol:DepositPrepareArbitrumToAvaxTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${ARBITRUM_KEY} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--verify \
	--broadcast \
	-vvvv

# Prepare for a XChain Deposit SRC as Avax Fuji dst Arbitrum Rinkeby
prepare-deposit-avax-arbitrum-test :; forge script script/Deploy.s.sol:DepositPrepareAvaxToArbitrunTest \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--etherscan-api-key ${AVAXSCAN_KEY} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--verify \
	--broadcast \
	-vvvv

# deposit into the vault as a user, om the avax fuji network
deposit-avax-vault-test :; forge script script/Deploy.s.sol:DepositIntoAvaxVault \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv

# this will fail on the simulation
deposit-arbitrum-vault-test :; forge script script/Deploy.s.sol:DepositIntoArbitrumVault \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--skip-simulation \
	-vvvv 

# make a XChainDeposit from the strategy to the hub to stargate
xchain-deposit-avax-arbitrum-test :; forge script script/Deploy.s.sol:XChainDepositAvaxToArbitrum \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://api.avax-test.network/ext/bc/C/rpc \
	--broadcast \
	-vvvv 

# make a XChainDeposit from the strategy to the hub to stargate
xchain-deposit-arbitrum-avax-test :; forge script script/Deploy.s.sol:XChainDepositArbitrumToAvax \
	--private-key ${PRIVATE_KEY_TEST_ACCOUNT} \
	--rpc-url https://arbitrum-rinkeby.infura.io/v3/${INFURA_API_KEY} \
	--broadcast \
	--skip-simulation \
	-vvvv 

