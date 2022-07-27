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

# Addressing Security Considerations in sgReceive

While LayerZero Endpoints expose the `srcAddress` of the sending contract, Stargate Receiever only exposes the address of the Stargate Router on the source chain.

This exposes a particular attack vector on all sgReceive functions:

- The address of the Auxo Hub is public
- The contract code of the Auxo Hub is also made public
- Anyone can send a message to the Stargate Receiever, forwarding the message to the Auxo Hub.

An attacker could therefore:

- Call the Stargate Router on any chain, encoding a malicious payload with a destination of the Hub.
- Stargate will forward the message to the Hub, which will be accepted as the sgReceive function accepts all calls from the Stargate Router.
- The attacker has full control of the `_payload` data, so in the Payload.Message can encode the exploit.

## Potential exploit

- We whitelist specific actions then forward them through the _reducer function. We will be exploring the `DEPOSIT_ACTION` (86) which will be sent to the `_depositAction` function:

```sol
    function _depositAction(
        uint16 _srcChainId,
        bytes memory _payload,
        uint256 _amountReceived
    ) internal virtual {

        /// at this point, we cannot trust the authenticity of the payload

        IHubPayload.DepositPayload memory payload = abi.decode(
            _payload,
            (IHubPayload.DepositPayload)
        );

        /// vault must be trusted, but it might not match the strategy

        IVault vault = IVault(payload.vault);
        require(
            trustedVault[address(vault)],
            "XChainHub::_depositAction:UNTRUSTED"
        );

        /// underyling is derived from vault, so it is safe at the moment

        IERC20 underlying = vault.underlying();

        uint256 vaultBalance = vault.balanceOf(address(this));

        /// _amountReceived is passed from stargate swap - assume safe for now

        underlying.safeApprove(address(vault), _amountReceived);

        /// deposit performs validations and will revert the tx if amount and balance don't line up

        vault.deposit(address(this), _amountReceived);

        uint256 mintedShares = vault.balanceOf(address(this)) - vaultBalance;

        require(
            mintedShares >= payload.min,
            "XChainHub::_depositAction:INSUFFICIENT MINTED SHARES"
        );

        /// This is the exploit: 
        /// First, strategy is not checked, it can be any address
        /// Secondly, _srcChainId comes from stargate BUT there is no guarantee it corresponds to the correct strategy on that chain
        /// Attacker can break reporting by sending from (eg) Optimism
        /// with strategy address on (eg) Arbitrum. 

        sharesPerStrategy[_srcChainId][payload.strategy] += mintedShares;
    }
```

## Fix

One fix is to change the structure of the XChainHub. Instead of having a universal Hub accounting for multiple strategies and vaults, we can change the setup to have a single hub, responsible for a single vault. 


```py
Vault_Chain_Token_Src -----┐                                           
                           ↓	                                         |
                XChainStrategy_Chain_Token ---> Hub_Vault_Src ---//|
                                                                         |

|
|// ----> Hub_Vault_Dst ----> Vault_Chain_Token_Dst
|
                                                                    
```

In this situation, the vault is not encoded in the payload, instead it can be set by the admin.

The situation therefore would be:

- Each Hub is responsible for one vault. 
- Any XChainStrategy depositing into the Hub will therefore deposit into a corresponding Vault
- Each XChainStrategy will be unique to a ChainId and Token.

Potential Exploits:
- It is still possible to make deposits into the Hub from an unknown place. For example, an attacker could send 100 USDC to a USDC Vault through Stargate:

Deposit Workflow

- The hub would accept the deposit
- ~ 1000 USDC would be added to the vault
- The vault would send ~ 1000 auxoUSDC to the hub
- We can check the # shares by calling auxoUSDC{chain}.balanceOf(hub)
OR 
- Keep shares per chain

- The strategy would be unaware that +1000 USDC were sent.
- When report is called, reportedUnderlying would increase by 1000
- Our amount depositied would be low, so we would report a very large APY if we take raw numbers from the vault.
- The attacker has caused some confusion, but as yet no clear profit nor DoS

Report Workflow
- sharesPerStrategy is replaced with sharesPerChain, reporting would operate as normal but with the aforementioned jump in reportedUnderlying

Withdraw Workflow:
- Finalize Withdraw will be called on the DST chain and will send tokens to the destination hub using stargate swap. This needs a rewrite.

Withdraw from Hub:
- The strategy can withdraw from the src hub when available

Questions/Comments:
- We cannot trust APY coming from the change in underlying, needs to be computed off chain most likely on %age basis (not differentials)
- What if someone sent AuxoTokens to the hub (we need shares per chain)


Todo:
[]: Replace shares per strate




/**
    single chain strategies
    Changes ~~~~~~ sgReceive functions - make external functions external

*/


