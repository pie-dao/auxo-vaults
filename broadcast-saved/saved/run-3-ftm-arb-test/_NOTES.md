Testnet TX between FTM Test <-> Arbitrum Rinkeby

1000 USDC was sent each way.

This failed due to a bug in the contract: the request withdraw method was not marked as payable.

# Deployer addresses

[Arbitrum Rinkeby](https://testnet.arbiscan.io/address/0xb0509dcf35d1683e398bb42069dc19ac472747ea#readContract)

[Fantom Testnet](https://testnet.ftmscan.com/address/0xb5eb2afe697e4cadbefa385104b52234ad871266#readContract)

# Notes and areas for improvement

* LayerZero fee estimates can be wildly high. FTM a good example. Best to cap the fee at a sensible level as I have spent close to 3 FTM on a single TX based on estimates.

* Nonce is probably required to track transactions

* The deployer is handy, but an offchain executor and registry would be the cheapest and easiest way to handle all addresses

* We need to check refund address and amounts - where do they go?

# Checklist

## Fantom

[x] Deploy/Setup Components
[x] Deposit into Vault
[x] Initiate XChainDeposit
[x] Receive XChainDeposit
[x] Report underlying send
[x] Report underlying receive
[x] Set vault as exiting
[] Initiate withdraw request
[] Receive withdraw request
[] Execute batch burn
[] Exit batch burn
[] Return tokens
[] Receive tokens
[] Withdraw to strategy
[] Withdraw to Vault
[] Withdraw to user

## Arbitrum

[x] Deploy/Setup Components
[x] Deposit into Vault
[x] Initiate XChainDeposit
[x] Receive XChainDeposit
[x] Report underlying send
[x] Report underlying receive
[x] Set vault as exiting
[] Initiate withdraw request
[] Receive withdraw request
[] Execute batch burn
[] Exit batch burn
[] Return tokens
[] Receive tokens
[] Withdraw to strategy
[] Withdraw to Vault
[] Withdraw to user