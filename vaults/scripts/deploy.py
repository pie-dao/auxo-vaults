import click
from brownie import (
    network,
    accounts,
    VaultFactory,
    VaultAuthBase,
)
from rich import print


def __prelude__():
    assert network.is_connected()

    prelude = {"network": network.show_active()}

    if prelude["network"] == "development":
        prelude["deployer"] = accounts[0]
    else:
        choice = click.prompt("Account", type=click.Choice(accounts.load()))
        prelude["deployer"] = accounts.load(choice)

    print(f"Active network: [green]{prelude['network']}[/green]")
    print(f"Deployer: [green]{prelude['deployer'].address}[/green]")

    return prelude


# this script will deploy the complete system:
#
# - VaultFactory: factory and registry
# - VaultAuthBase: base auth module
def main():
    prelude = __prelude__()

    # deploy factory
    factory = VaultFactory.deploy({"from": prelude["deployer"]})

    # deploy vault auth
    auth = VaultAuthBase.deploy(
        prelude["deployer"].address, {"from": prelude["deployer"]}
    )

    print(f"Deployed Factory at: {factory.address}")
    print(f"Deployed VaultAuthBase at: {auth.address}")
