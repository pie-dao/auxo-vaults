import pytest
import brownie

from brownie import ZERO_ADDRESS


def test_vault_creation(factory, gov, token, auth, Vault):
    # deploy the vault
    vault_implementation = gov.deploy(Vault)
    factory.setImplementation(vault_implementation)
    creation_tx = factory.deployVault(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)

    assert creation_tx.return_value != ZERO_ADDRESS

    vault = Vault.at(creation_tx.return_value, owner=gov)

    # asserts for initial state
    assert vault.paused()
    assert vault.auth() == auth
    assert vault.batchBurnRound() == 1
    assert vault.underlying() == token
    assert vault.symbol() == "auxo" + token.symbol()
    assert vault.baseUnit() == 10 ** token.decimals()
    assert vault.name() == "Auxo " + token.name() + " Vault"
    assert vault.blocksPerYear() == 0