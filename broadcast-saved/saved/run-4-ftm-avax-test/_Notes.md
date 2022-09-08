Testnet TX between FTM Test <-> Avax Fuju

1000 USDC was sent each way.

Completed

# Deployer addresses

[Avax Fuji](https://testnet.snowtrace.io/address/0xE6489A6a6D85e5BCC2CE0f64BF76cA073892E344#readContract)

[Fantom Testnet](https://testnet.ftmscan.com/address/0xE4F4290eFf20e4d0eef7AB43c3d139d078F6c0f2#readContract)

# Notes and areas for improvement

* LayerZero fee estimates can be wildly high. FTM a good example. Best to cap the fee at a sensible level as I have spent close to 3 FTM on a single TX based on estimates.

* Nonce is probably required to track transactions

* The deployer is handy, but an offchain executor and registry would be the cheapest and easiest way to handle all addresses

* We need to check refund address and amounts - where do they go?

* You lose bits and pieces of underlying due to fees, can all get quite hard to keep track of

// Check this...
* Reporting *might* be able to brick things on the strat side:
    * Call report too early and it'll reject
    * Call report before tokens removed, tokens can't be removed

# Checklist

## Fantom

[x] Deploy/Setup Components
[x] Deposit into Vault
[x] Initiate XChainDeposit
[x] Receive XChainDeposit
[x] Report underlying send
[x] Report underlying receive
[x] Set vault as exiting
[x] Initiate withdraw request
[x] Receive withdraw request
[x] Exit Vault
[x] Return tokens
[x] Receive tokens
[x] Withdraw to strategy
[] Withdraw to Vault
[] Withdraw to user

## Avax

[x] Deploy/Setup Components
[x] Deposit into Vault
[x] Initiate XChainDeposit
[x] Receive XChainDeposit
[x] Report underlying send
[x] Report underlying receive
[x] Set vault as exiting
[x] Initiate withdraw request
[x] Receive withdraw request
[x] Exit Vault
[x] Return tokens
[x] Receive tokens
[x] Withdraw to strategy
[x] Withdraw to Vault