import click

from ape_safe import ApeSafe
from brownie import (VaultBase, interface)

SAFE_ADDRESS = '0x309DCdBE77d9D73805e96662503B08FEe229597A'

def print_vault_state(vault):
    underlying_token = interface.ERC20(vault.underlying())
    
    print(f'Vault name: {vault.symbol()}, {vault.name()}')
    print(f'Vault underlying: {underlying_token.name()} ({vault.underlying()})')
    print(f'Vault float: {vault.totalFloat()}')

def deposit_float(vault, account):
    strategy_addr = click.prompt('Strategy address')
    amount = click.prompt(f'Amount (float is {vault.totalFloat()})')

    strategy = interface.IStrategy(strategy_addr)

    vault.depositIntoStrategy(strategy, amount, {'from': account})
    strategy.depositUnderlying(strategy.float(), {'from': account})

def build_tx_and_send(safe):
    safe_tx = safe.multisend_from_receipts()
    
    safe.preview(safe_tx)
    safe.sign_with_frame(safe_tx)
    safe.post_transaction(safe_tx)

def main():
    safe = ApeSafe(SAFE_ADDRESS)

    conf = {}
    conf["vault_address"] = click.prompt("Vault address")

    vault = VaultBase.at(conf["vault_address"])

    print_vault_state(vault)
    deposit_float(vault, safe.account)

    build_tx_and_send(safe)