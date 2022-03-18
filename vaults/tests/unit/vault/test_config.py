import pytest
import brownie

from brownie import ZERO_ADDRESS


def test_vault_deployment(gov, token, auth, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)

    # asserts for initial state
    assert vault.paused()
    assert vault.auth() == auth
    assert vault.batchBurnRound() == 1
    assert vault.underlying() == token
    assert vault.symbol() == "auxo" + token.symbol()
    assert vault.baseUnit() == 10 ** token.decimals()
    assert vault.name() == "Auxo " + token.name() + " Vault"
    assert vault.blocksPerYear() == 0

    # assert for initial share exchange rate
    assert vault.exchangeRate() / vault.baseUnit() == 1.0

    # asserts for limits
    assert vault.userDepositLimit() == 0
    assert vault.vaultDepositLimit() == 0

    # asserts for fee percent
    assert vault.harvestFeePercent() == 0
    assert vault.burningFeePercent() == 0

    # asserts for fee receivers
    assert vault.harvestFeeReceiver() == ZERO_ADDRESS
    assert vault.burningFeeReceiver() == ZERO_ADDRESS

    # asserts for harvest window/delay
    assert vault.harvestDelay() == 0
    assert vault.harvestWindow() == 0

    # asserts for withdrawal queue
    assert vault.getWithdrawalQueue() == []


def test_vault_configuration(gov, token, auth, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)

    # asserts for initial state

    vault.triggerPause()
    assert not vault.paused()

    vault.setBlocksPerYear(365)
    assert vault.blocksPerYear() == 365

    # asserts for limits
    vault.setDepositLimits(5000 * 1e18, 2000 * 1e18)
    assert vault.userDepositLimit() == 5000 * 1e18
    assert vault.vaultDepositLimit() == 2000 * 1e18

    # asserts for fee percent
    vault.setHarvestFeePercent(1e17)
    assert vault.harvestFeePercent() == 1e17

    vault.setBurningFeePercent(1e17)
    assert vault.burningFeePercent() == 1e17

    # asserts for fee receivers
    vault.setHarvestFeeReceiver(gov)
    assert vault.harvestFeeReceiver() == gov

    vault.setBurningFeeReceiver(gov)
    assert vault.burningFeeReceiver() == gov

    # asserts for harvest window/delay
    vault.setHarvestDelay(1000)
    assert vault.harvestDelay() == 1000

    vault.setHarvestWindow(10)
    assert vault.harvestWindow() == 10

    # asserts for withdrawal queue
    vault.setWithdrawalQueue([ZERO_ADDRESS])
    assert vault.getWithdrawalQueue() == [ZERO_ADDRESS]
