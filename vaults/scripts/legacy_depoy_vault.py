```py
import click
from brownie import (
    network,
    accounts,
    VaultFactory,
    VaultBase,
)
from rich import print


'''
Prelude generates an object with the following fields:
    network: name of the network
    deployer: account addr of the deployer
    vault_factory: address of vault factory contract (must be deployed already)
    auth: address of the Vault auth contract
    underlying: address of the underlying token

There is an existing deploy script for VaultFactory and VaultAuth
'''
def __prelude__():
    assert network.is_connected()

    prelude = {"network": network.show_active()}

    # in dev use a mock account otherwisr connect to a specific account
    if prelude["network"] == "development":
        prelude["deployer"] = accounts[0]
    else:
        choice = click.prompt("Account", type=click.Choice(accounts.load()))
        prelude["deployer"] = accounts.load(choice)


    prelude["vault_factory"] = VaultFactory.at(click.prompt("Vault factory"))
    prelude["auth"] = click.prompt("IVaultAuth")
    prelude["underlying"] = click.prompt("Underlying address")

    print(f"Active network: [green]{prelude['network']}[/green]")
    print(f"Deployer: [green]{prelude['deployer'].address}[/green]")
    print(f"Factory address: {prelude['vault_factory']}")
    print(f"Underlying to deploy: {prelude['underlying']}")
    print(f"Auth address: {prelude['auth']}")

    return prelude


# this script will deploy following:
#
# - VaultBase: current implementation for VaultBase
# - A Vault for the chosen underlying.
def main():
    prelude = __prelude__()

    vault_base_impl = VaultBase.deploy({"from": prelude["deployer"]})

    prelude["vault_factory"].publish(
        vault_base_impl.address, {"from": prelude["deployer"]}
    )

    prelude["vault_factory"].deployVaultWithVersion(
        vault_base_impl.version(),
        prelude["underlying"],
        prelude["auth"],
        prelude["deployer"],
        prelude["deployer"],
        {"from": prelude["deployer"]},
    )

    # this needs the `debug_traceTransaction` RPC, only available in a local environment/local client
    # prelude["vault_factory"].registerVault(
    #     deploy_tx.return_value, prelude["underlying"], {"from": prelude["deployer"]}
    # )
```