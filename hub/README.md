# Auxo X Chain

<span style="
    font-weight:bold;
    color:orange;
    border:1px solid orange;
    padding:5px;
">
    Warning! This repository is incomplete state and will be changing heavily
</span>

This repository contains the source code for the Auxo Cross chain hub. There is additional context in the [PieDAO Notion](https://www.notion.so/piedao/Cross-Chain-Contracts-a6dee31247cb4f3f82db49ea4c026a8c)

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

Currently the Hub uses Stargate to handle Swaps, and LayerZero to handle non-swap transactions. 

### Advantages of Stargate:
- Guaranteed instant finality if the transaction is approved, due to Stargate's cross-chain liquidity pooling.
- We can pass our payload data to the Stargate router and use `sgReceive` to both handle the swapping, and post-swap logic. This would remove the need for calls to both the LayerZero endpoint and to Anyswap router.

# Deployment
Deployment scripts are in the scripts folder, as of right now we have a large part of the vault scripts in the [Vaults Repo](../vaults), there is a pending task to create a unified deployer.

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

# Strategies & XChainStrategies

The cross chain strategy inherits from the BaseStrategy contract.

The BaseStrategy provides a lightweight api containing a set of relevant virtual methods for same chain deposits and withdrawals. These can be safely ignored in the cross-chain world. Our relevant methods from the BaseStrategy are:

- Set{Role}: Access control allowing the manager to set a new manager or strategist.
    - Managers can change the hub, vault and router, deposit and withdraw
    - Strategists can deposit and withdraw
    - The hub can call report
    - The stargate router can call sgReceive
- float: see below.
- estimatedUnderlying(): get the estimated underlying tokens deployed in yield bearing sources.

For CrossChain, we have the standard deposit and withdraw methods for the current chain. We then have the cross chain functions to requestWithdrawUnderlying and finalizeWithdrawUnderlying. 

Importantly, we have the `report` function, this is crucial for making sure that the strategy is kept up to date with the latest data.

The flow is:

- DstHub: `reportUnderlying()`
    - Pass the list of strategies and chains
    - Calculate the underlying for each strategy on each chain
        - Assumes the same underlying token
    - Send a XChain message to the layerzero endpoint
- SrcHub: `_lzReceive`:
    - decode the payload and forward to _reportUnderlying through the reducer
    - _reportUnderlying calls IStrategy.report and updates the chain
    - If a zero value is reported, we reset the state of the strategy.

## Understanding float & Estimated underlying

Understand that underyling deposited into a strategy is typically redeployed elsewhere. This is important because if tokens are deposited into other protocols, we cannot use IERC20.balanceOf to get the ERC20 value locked into a particular strategy.

Addressing this challenge requires the strategy keep a record of the last balance of underlying at the point at which underlying tokens are deposited or withdrawn.

The `depositedUnderlying` represents the last known qty of tokens deployed elsewhere.
The `float` represents tokens held in the strategy.
Therefore the estimated total strategy holdings will be `depositedUnderlying` + `float`

Example:

Strategy X has 1000 USDC, deposits 500 into Balancer. Record a float of 500 and a lastBalance depositedUnderlying of 500, for a total of 1000 USDC.

If the balancer strategy loses 50% of the USDC, the reported underlying is still 1000 USDC, even though the value is now 750 USDC

On withdrawal, we are able to withdraw 250 USDC from Balancer, so we subtract 250 USDC from the depositedUnderlying variable, which is added to the float.

It should be also possible to update the underlying balance so that the remaining depositedUnderlying is zero, if the funds are lost.

## Lifecycle
XChainStrategy currently maintains a single global deposit state:
- NOT_DEPOSITED is the initial state
    - In this state, report cannot be called
- DEPOSITING is set when a deposit request is made to the hubDst
- DEPOSITED is set when the hubSrc calls the `report` function AND the state is DEPOSITING
    - It is also called after a withdrawal resolves*.
    - This is the only state in which `withdrawUnderlying` can be called
- WITHDRAWING is set when a request for withdrawal is made
    - In this state, deposits cannot be made
    - In this state the contract can receive tokens from the stargate router
- NOT_DEPOSITED (same as above) is set again when sgReceive resolves (i.e the underlying tokens have been withdrawn to the XChainStrategy)


Some implications:

`report()` can be called in the DEPOSITING, DEPOSITED or WITHDRAWING state.
- If called in the DEPOSITED state, this could be an update from the reportUnderlying function. 
    - Hubs can make batch calls to update the underlying of all strategies on all destination chains at any time, for example.
    - If the quantity is set to zero, the strategies state is reset to NOT_DEPOSITED
- If called in DEPOSITING state, the status will change to DEPOSITED, indicating a successful deposit.
- If called in a WITHDRAWING state, this again could be an update from the hub.

`depositUnderlying()` can be called in NOT_DEPOSITED, DEPOSITING or DEPOSITED state:
    - NOT_DEPOSITED is simply the base case
    - DEPOSITING suggests more float is being deposited, while a deposit is already underway
    - DEPOSITED is the same but suggest the deposit has completed.

*NB: Might be tempting to rest the state to NOT_DEPOSITED after a withdrawal, however this would cause issues:
1. Make a deposit of X tokens.
2. Begin a withdrawal for x < X.
3. The withdrawal completes, the status is NOT_DEPOSITED.
4. We cannot make a further withdrawal at this stage due to the guard clauses.
5. We would need to make a further deposit to bring the state back to DEPOSITED, then withdraw again. 

### Questions
- How does the BaseStrategy handle the case where underlying changes? Is this expected to be implemented in the inherited contract?
- A lot of the XChainStrategy logic is replicated in the XChainHub. What exactly is the purpose of this contract? Is the aim that it is extended with 'real' strategies.
- BaseStrategy defines 2 virtual methods `depositUnderlying` and `withdrawUnderlying`, but XChain withdrawals from vaults need to go through a batch burn process after requesting withdrawal. Is there a 3rd method that is needed?
- It looks technically possible to make cross chain deposits to multiple places, from the same XChain strategy, is this what we want?
    - We could change the chain
    - We could change the vault
    - How does that work?

### Considerations
- L0 does not revert if the message goes through, it just fails on the dstChain. For reporting, how are we handling such cases?


Changes Requested:
[x] At least 0.8.14 - check changelog for .15
[x] Remove setter on stargate router and set to immutable
[x/U] Check to make sure sg/lz only called by our hub
- Revert if minOutTooHigh - stargate router
- rename to _finalizeWithdrawFromChainAction

- can we store underlying qty on withdraw and pull it
- change nonBlockingLzReceive to lzReceive and define the exceptions

