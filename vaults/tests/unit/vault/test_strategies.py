import pytest
import brownie

from brownie import ZERO_ADDRESS, MockStrategy, Vault

MAX_UINT256 = 2**256 - 1


def test_trust_strategy(gov, token, auth, MockStrategy, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)

    # deploy the strategy
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, gov, "MockStrategy")

    # calling set strategy should not revert
    assert not vault.getStrategyData(strategy)["trusted"]
    vault.trustStrategy(strategy, {"from": gov})
    assert vault.getStrategyData(strategy)["trusted"]


def test_distrust_strategy(gov, token, auth, MockStrategy, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)

    # deploy the strategy
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, gov, "MockStrategy")

    # trust the strategy
    vault.trustStrategy(strategy, {"from": gov})
    assert vault.getStrategyData(strategy)["trusted"]

    # calling set strategy should not revert
    vault.distrustStrategy(strategy, {"from": gov})
    assert not vault.getStrategyData(strategy)["trusted"]


def test_can_deposit_underlying_in_trusted_strategy(
    gov, token, auth, MockStrategy, Vault
):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)
    vault.triggerPause()

    # deploy the strategy
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, gov, "MockStrategy")

    # trust the strategy
    vault.trustStrategy(strategy, {"from": gov})

    # deposit underlying in the vault
    token.approve(vault, 1e19)
    vault.deposit(gov, 1e19)

    # deposit underlying in the strategy
    vault.depositIntoStrategy(strategy, 9e18)

    # assert balances
    assert token.balanceOf(vault) == 1e18
    assert token.balanceOf(strategy) == 9e18
    assert vault.totalFloat() == 1e18
    assert vault.totalStrategyHoldings() == 9e18
    assert vault.totalUnderlying() == 1e19


def test_cant_deposit_underlying_in_untrusted_strategy(
    gov, token, auth, MockStrategy, Vault
):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)
    vault.triggerPause()

    # deploy the strategy
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, gov, "MockStrategy")

    # deposit underlying in the vault
    token.approve(vault, 1e19)
    vault.deposit(gov, 1e19)

    # deposit underlying in the strategy
    with brownie.reverts("depositIntoStrategy::UNTRUSTED_STRATEGY"):
        vault.depositIntoStrategy(strategy, 1e18)


def test_withdraw_underlying_strategy(gov, token, auth, MockStrategy, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)
    vault.triggerPause()

    # deploy the strategy
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, gov, "MockStrategy")

    # trust the strategy
    vault.trustStrategy(strategy, {"from": gov})

    # deposit underlying in the vault
    token.approve(vault, 1e19)
    vault.deposit(gov, 1e19)

    # deposit underlying in the strategy
    vault.depositIntoStrategy(strategy, 9e18)

    # withdraw underlying from strategy
    vault.withdrawFromStrategy(strategy, 9e18)

    assert vault.totalFloat() == 1e19
    assert vault.totalUnderlying() == 1e19
