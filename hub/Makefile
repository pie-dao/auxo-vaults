# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

all: clean install update build

# Install proper solc version.
solc:; nix-env -f https://github.com/dapphub/dapptools/archive/master.tar.gz -iA solc-static-versions.solc_0_8_14

# Clean the repo
clean :; forge clean

# Install the Modules
install :; forge install

# Update Dependencies
update :; forge update

# Builds
build :; forge build

# chmod scripts
scripts :; chmod +x ./scripts/*

# create a coverage report (requires lcov (linux) / genhtml (Mac))
coverage :; forge coverage --report lcov && genhtml lcov.info -o report --branch-coverage

# deployment scripts - opt
run-optimism-test :; forge script --rpc-url https://optimism-kovan.infura.io/v3/${INFURA_KEY} \
	scripts/DeployXChain.s.sol:XChainHubOptimism \
	--private-key ${PRIVATE_KEY} \
	-vvvv


run-optimism-real :; forge script --rpc-url https://optimism-kovan.infura.io/v3/${INFURA_KEY} \
	scripts/DeployXChain.s.sol:XChainHubOptimism \
	--private-key ${PRIVATE_KEY} \
	--broadcast \
	-vvvv

# deployment scripts - arb
run-arbitrum-test :; forge script --rpc-url https://rinkeby.arbitrum.io/rpc \
	scripts/DeployXChain.s.sol:XChainHubArbitrum \
	--private-key ${PRIVATE_KEY} \
    --legacy \
	-vvvv


run-arbitrum-real :; forge script --rpc-url https://rinkeby.arbitrum.io/rpc \
	scripts/DeployXChain.s.sol:XChainHubArbitrum \
	--private-key ${PRIVATE_KEY} \
	--broadcast \
	-vvvv

run-ftm-usdc :; forge script --rpc-url  https://rpc.testnet.fantom.network \
	scripts/SendUSDC.s.sol:SendUSDC \
	--private-key ${PRIVATE_KEY} \
	--broadcast \
    --trezor \
	-vvvv

run-ftm-real :; forge script --rpc-url  https://rpc.testnet.fantom.network \
	scripts/DeployXChain.s.sol:XChainFTM \
	--private-key ${PRIVATE_KEY} \
	--broadcast \
	-vvvv


# deploy polygon
# Deploy the xchain contract - mumbai
deploy-mumbai :; forge create --rpc-url https://polygon-mumbai.infura.io/v3/${INFURA_KEY} \
    --constructor-args "0x817436a076060D158204d955E5403b6Ed0A5fac0" "0xf69186dfBa60DdB133E91E9A4B5673624293d8F8" "0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79" \
    --private-key ${PRIVATE_KEY} src/XChainHub.sol:XChainHub \
    --etherscan-api-key ${ETHERSCAN_API_KEY_MUMBAI} \
    --verify


# Deploy the xchain contract - ftmtest
deploy-ftmtest :; forge create --rpc-url https://rpc.testnet.fantom.network \
    --constructor-args "0xa73b0a56B29aD790595763e71505FCa2c1abb77f" "0x7dcAD72640F835B0FA36EFD3D6d3ec902C7E5acf" "0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79" \
    --private-key ${PRIVATE_KEY} src/XChainHub.sol:XChainHub \
    --etherscan-api-key ${ETHERSCAN_API_KEY_FTMTEST} \
    # --verify    


# Deploy the xchain contract - kovan opt
deploy-kovan-opt :; forge create --rpc-url https://optimism-kovan.infura.io/v3/${INFURA_KEY} \
    --constructor-args "0xCC68641528B948642bDE1729805d6cf1DECB0B00" "0x72aB53a133b27Fa428ca7Dc263080807AfEc91b5" "0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79" \
    --private-key ${PRIVATE_KEY} src/XChainHub.sol:XChainHub \
    --etherscan-api-key ${ETHERSCAN_API_KEY_KOVAN_OPTIMISM} \
    --verify

# Deploy the xchain contract - arbi rink
deploy-arbitrum-rink :; forge create --rpc-url https://rinkeby.arbitrum.io/rpc \
    --constructor-args "0x6701D9802aDF674E524053bd44AA83ef253efc41" "0x4D747149A57923Beb89f22E6B7B97f7D8c087A00" "0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79" \
    --private-key ${PRIVATE_KEY} src/XChainHub.sol:XChainHub \
    --etherscan-api-key ${ETHERSCAN_API_KEY_ARBITRUM_RINKEBY} \
    --verify


# remember to set the hub as argument 0
# Deploy the xchain strategy - kovan opt
deploy-strat-kovan-opt :; forge create --rpc-url https://kovan.optimism.io \
    --constructor-args "0x348a6f9c19e381b3ae9b6f4e1e91b10995b773d2" "0xaf29ba76af7ef547b867eba712a776c61b40ed02" "0x567f39d9e6d02078F357658f498F80eF087059aa" "0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79" "0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79" "Test Strategy" \
    --private-key ${PRIVATE_KEY} src/strategy/XChainStrategy.sol:XChainStrategy \
    --etherscan-api-key ${ETHERSCAN_API_KEY_KOVAN_OPTIMISM} \
    --verify

# remember to set the hub as argument 0
# Deploy the xchain contract - arbi rink
deploy-strat-arbitrum-rink :; forge create --rpc-url https://rinkeby.arbitrum.io/rpc \
    --constructor-args "0x20dc84d2f4add06031a728f73e8adda04082ab73" "0x9053dfb5f286ef3f885f1f55cdec8eb85834655c" "0x1EA8Fb2F671620767f41559b663b86B1365BBc3d" "0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79" "0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79" "Strat 13 July" \
    --private-key ${PRIVATE_KEY} src/strategy/XChainStrategy.sol:XChainStrategy \
    --etherscan-api-key ${ETHERSCAN_API_KEY_ARBITRUM_RINKEBY} \
    --verify


# remember to set the hub as argument 0
# Deploy the xchain contract - mumbaii
deploy-strat-mumbai :; forge create --rpc-url https://polygon-mumbai.infura.io/v3/${INFURA_KEY} \
    --constructor-args "0x999c7c3da9d2aa6427c81e82570b5382e3bc0b29" "0x9053dfb5f286ef3f885f1f55cdec8eb85834655c" "0x742DfA5Aa70a8212857966D491D67B09Ce7D6ec7" "0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79" "0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79" "Strat 13 July" \
    --private-key ${PRIVATE_KEY} src/strategy/XChainStrategy.sol:XChainStrategy \
    --etherscan-api-key ${ETHERSCAN_API_KEY_MUMBAI} \
    --verify

# Deploy the xchain contract - ftmtest
deploy-strat-ftmtest :; forge create --rpc-url https://rpc.testnet.fantom.network \
    --constructor-args "0xe6489a6a6d85e5bcc2ce0f64bf76ca073892e344" "0x5545720918e64e86c03a691c056afdc727922fe5" "0x076488D244A73DA4Fa843f5A8Cd91F655CA81a1e" "0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79" "0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79" "Strat 13 July" \
    --private-key ${PRIVATE_KEY} src/strategy/XChainStrategy.sol:XChainStrategy \
    --etherscan-api-key ${ETHERSCAN_API_KEY_FTMTEST} \
    # --verify




# verify

verify-arbitrum-rink :; ARGS="$(cast abi-encode 'constructor(address,address,address) 0x6701D9802aDF674E524053bd44AA83ef253efc41 0x4D747149A57923Beb89f22E6B7B97f7D8c087A00 0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79)" & forge verify-contract --chain-id 421611 \
    --num-of-optimizations 200 \
    --compiler-version v0.8.12+commit.f00d7308 \
    --constructor-args ARGS 0x1869691b28756ad1556de08b82fd56339248f03b src/XChainHub.sol:XChainHub ${ETHERSCAN_API_KEY_ARBITRUM_RINKEBY}



# env var check
check-env :; echo $(PRIVATE_KEY)


