from brownie import Contract, interface
from ape_safe import ApeSafe

vaults = [
    {
        "vault": "0x662556422AD3493fCAAc47767E8212f8C4E24513",
        "harvest_strategies": [
            "0x7ee2de6C955aB59d9bBF7691590b871cd324aD93",
            "0xE85E08406369C08Fbf338ff25C37d12FeA3c7e86",
        ],
        "deposit_strategies": [
            "0x7ee2de6C955aB59d9bBF7691590b871cd324aD93",
            "0xE85E08406369C08Fbf338ff25C37d12FeA3c7e86",
        ],
    },  # usdc
    {
        "vault": "0xBC4639E6056C299B5A957C213BCE3EA47210E2BD",
        "harvest_strategies": ["0xeb8De8047fD66979490629c34288f8a78e97B00B"],
        "deposit_strategies": ["0xeb8De8047fD66979490629c34288f8a78e97B00B"],
    },  # frax
    {
        "vault": "0x16AD251B49E62995EC6F1B6A8F48A7004666397C",
        "harvest_strategies": ["0xEC33b70681e0c7b9A8FCb72931B656e3F6Ff971c"],
        "deposit_strategies": ["0xEC33b70681e0c7b9A8FCb72931B656e3F6Ff971c"],
    },  # wftm
    {
        "vault": "0xA9DD5345ED912B359102DDD03F72738291F9F389",
        "harvest_strategies": ["0x40BceC61AfCA3E8B02d61240dAaE9c07dfd67893"],
        "deposit_strategies": ["0x40BceC61AfCA3E8B02d61240dAaE9c07dfd67893"],
    },  # mim
    {
        "vault": "0xF939A5C11E6F9884D6052828981E5D95611D8B2E",
        "harvest_strategies": ["0x3001444219dF37a649784e86d5A9c5E871a41E9E"],
        "deposit_strategies": ["0x3001444219dF37a649784e86d5A9c5E871a41E9E"],
    },  # dai
]


def deposit_underlying_if_any(vault, strategies, account):
    total_float = vault.totalFloat()
    share = int(total_float / len(strategies))

    if total_float > 0 and share > 0:
        for s in strategies:
            actual_float = vault.totalFloat()
            amount = actual_float if share > actual_float else share
            
            print(amount)

            vault.depositIntoStrategy(s, amount)

            strategy = Contract.from_explorer(s, owner=account)

            if strategy.name() != "BeethovenLPSingleSided USDC":
                strategy.depositUnderlying(amount)


def main():
    safe = ApeSafe("0x309DCdBE77d9D73805e96662503B08FEe229597A")

    aprs = []

    for v in vaults:
        vault = Contract.from_explorer(v["vault"], owner=safe.account)

        if vault.totalStrategyHoldings() > 0:
            vault.harvest(v["harvest_strategies"])  # harvest before depositing

        deposit_underlying_if_any(vault, v["deposit_strategies"], safe.account)

        aprs.append({"vault": vault.name(), "estimated": vault.estimatedReturn()})

    for apr in aprs:
        print(
            f'(decimals: {vault.decimals()}) apr for {apr["vault"]} is {apr["estimated"] / (10 ** vault.decimals())} %'
        )

    safe_tx = safe.multisend_from_receipts()
    safe.sign_with_frame(safe_tx)
    safe.post_transaction(safe_tx)
