# Auxo X Chain

<span style="
    font-weight:bold;
    color:orange;
    border:1px solid orange;
    padding:5px;
">
    Warning! This repository is incomplete state and will be changing heavily
</span>

This repository contains the source code for the Auxo Cross chain hub, it consists of 3 parts:

1. The XChainHub - an interface for interacting with vaults and strategies deployed on multiple chains.

2. The XChainStrategy - an implementation of the same BaseStrategy used in the Auxo Vaults that adds support for using the XChainHub.

3. LayerZeroApp - an implementation of a nonBlockingLayerZero application that allows for cross chain messaging using the LayerZero protocol.


## The Hub
----------
The hub itself allows users to intiate vault actions from any chain and have them be executed on any other chain with a [LayerZero endpoint](https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids). 

LayerZero applications initiate cross chain requests by calling the `endpoint.send` method, which then invokes `_nonBlockingLzReceive` on the destination chain. 

The hub itself implements a reducer pattern to route inbound messages from the `_nonBlockingLzReceive` function, to a particular internal action. The main actions are:

1. Deposit into a vault.
2. Request to withdraw from a vault (this begins the batch burn process).
3. Provided we have a successful batch burn, complete a batch burn request and send underlying funds from a vault to a user.
4. Report changes in the underlying balance of each strategy on a given chain.

Therefore, each cross chain request will go through the following workflow:

1. Call the Cross Chain function on the source chain (i.e. `depositToChain`)
2. Cross chain function will call the `_lzSend` method, which in turn calls the `LayerZeroEndpoint.send` method.
3. The LZ endpoint will call `_nonBlockingLzReceive` on the destination chain.
4. The reducer at `_nonBlockingLzReceive` will call the corresponding action passed in the payload (i.e. `_depositAction`)


A simple Diagram outlining the hub's interaction with strategies:
```
User -->  Vault
            --> Strategy A
            --> Strategy B
            --> Strategy C // x-chain
                --> Origin HUB --------------------------> Dest Hub
                               <-------------------------- Report
                <--------------                                   ------------> Dest Vault 
                                                                                --> Strategy A
                                                                                --> Strategy B
                                                                                --> Strategy C
```

## Swaps
----------
Currently, the hub utilises the [Anyswap router](https://github.com/anyswap/CrossChain-Router/wiki/How-to-integrate-AnySwap-Router) to execute cross chain deposits of the underlying token into the auxo vault. We are discussing removing the router and replacing with stargate. 

### Advantages of Stargate:
- Guaranteed instant finality if the transaction is approved, due to Stargate's cross-chain liquidity pooling.
- We can pass our payload data to the Stargate router and use `sgReceive` to both handle the swapping, and post-swap logic. This would remove the need for calls to both the LayerZero endpoint and to Anyswap router.


### Advantages of Anyswap:
- Anyswap supports a much larger array of tokens, whereas stargate only implements a few stables and Eth. 


## Known set of implementation tasks to work on:
- [ ] Implement events at different stages of the contract
- [x] Remove the NI error if we don't need it
- [ ] Connect finalizeWithdrawFromVault to a cross chain action
- [ ] Confirm that finalizeWithdrawFromVault is a step in _finalizeWithdrawAction
- [x] Ensure the format of messages in `sgReceive` matches the encoding in `IStargateRouter.swap` - currently in format `encoded(Message(, encoded(payload)))`
    - [x] Pass all payloads a Message structs
    - [x] Check encodings, in particular encoding IVaults and IStrategies
    - [x] Consider defining structs for all payloads to ensure consistent serialisation and deserialisation
- [x] See if the reducers can be combined by passing the payloads from both entrypoints
- [ ] Confirm the params for both stargate swaps:
    - [ ] default lzTxObj
    - [x] minAmountOut
    - [x] destination (strategy?)
- [ ] Refactoring: start to break down some of the larger functions into smaller chunks


## Testing
- [x] Setup the mocks:
    - [x] LayerZero
    - [x] Stargate
- [x] Define the unit test suite
- [x] Build integration test scripts for the testnets
- [ ] Unit testing on src
- [x] Unit testing on dst
- [ ] Unit testing cross chain with mocks
- [ ] Completed Integration testing

# Deployment
Deployment scripts are in the scripts folder, as of right now we have a large part of the vault scripts in the [Auxo Vaults Repo](https://github.com/pie-dao/auxo-vaults/tree/main), there is a pending task to create a unified deployer.

# Deploying a Cross Chain Application

Instructions below for deploying all the components, if you want to do it manually:
### Components

- XChainHub:
    - (R) Src 
    - (R) Dest

- XChainStrategy?
    - (R) Src
    - Dest

- Vault:
    - (R) Src
    - (R) Dst

- Vault Auth:
    - (R) Src
    - (R) Src

- Token:
    - (R) Src
    - (R) Src

- Dependencies (these must be present on the src and dst chains):
    - Stargate
    - LayerZero

Ordering:
- (Factory)
- Auth
- Vault
- XHub
- XStrategy

# Order of Execution
1. Deploy the contracts & link them
2. Trust:
    2.1 The strategy on the Vault `trustStrategy`
    2.2 Vault on the hub `setTrustedVault`

3. MerkleRoot
    3.1 Open (No permissions)
    3.2 Restricted
4. Set trustedRemote for the LayerZero Application on the dst chainId
5. User deposit into origin (src) vault
6. (As Admin) call deposit into Strategy
7. (As XChainStrategy manager or strategist) call deposit assets to Chain, `hub::depositToChain`
8. (Call swap) - tokens should appear on target/dst chain (query the USDC balance of the strategy)

