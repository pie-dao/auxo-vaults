import pytest
import brownie

from brownie import ZERO_ADDRESS, MockStrategy, Vault

MAX_UINT256 = 2**256 - 1


def test_deposit_without_allowance(misc_accounts, gov, token, auth, Vault):
    # mint some tokens to alice
    alice = misc_accounts[0]
    token.mint(alice, 10_000e18)

    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    # this should revert
    with brownie.reverts():
        vault.deposit(alice, 10_000e18, {"from": alice})


def test_deposit(misc_accounts, gov, token, auth, Vault):
    # mint some tokens to alice
    alice = misc_accounts[0]
    token.mint(alice, 10_000e18)

    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    # should pass
    balanceBefore = token.balanceOf(alice)
    exchangeRate = vault.exchangeRate()
    token.approve(vault, 10_000e18, {"from": alice})
    vault.deposit(alice, 10_000e18, {"from": alice})

    assert vault.totalFloat() == 10_000e18
    assert vault.balanceOf(alice) == 10_000e18 * exchangeRate / vault.baseUnit()
    assert token.balanceOf(alice) == (balanceBefore - 10_000e18)
    assert token.balanceOf(vault) == 10_000e18

def test_user_deposit_when_paused(misc_accounts, gov, token, auth, Vault):
    # mint some tokens to alice
    alice = misc_accounts[0]
    token.mint(alice, 10_000e18)

    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)

    # should pass
    token.approve(vault, 10_000e18, {"from": alice})

    with brownie.reverts("Pausable: paused"):
        vault.deposit(alice, 10_000e18, {"from": alice})

def test_user_deposit_not_approved(misc_accounts, gov, token, auth, Vault):
    # mint some tokens to alice
    alice = misc_accounts[0]
    token.mint(alice, 10_000e18)

    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)

    with brownie.reverts():
        vault.deposit(alice, 10_000e18, {"from": alice})

def test_user_deposit_over_user_limit(misc_accounts, gov, token, auth, Vault):
    # mint some tokens to alice
    alice = misc_accounts[0]
    token.mint(alice, 10_000e18)

    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(1_000e18, MAX_UINT256)

    # should pass
    token.approve(vault, 10_000e18, {"from": alice})

    with brownie.reverts("_deposit::USER_DEPOSIT_LIMITS_REACHED"):
        vault.deposit(alice, 10_000e18, {"from": alice})

def test_user_deposit_over_user_limit(misc_accounts, gov, token, auth, Vault):
    # mint some tokens to alice
    alice = misc_accounts[0]
    token.mint(alice, 10_000e18)

    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, 9_999e18)

    # should pass
    token.approve(vault, 10_000e18, {"from": alice})

    with brownie.reverts("_deposit::VAULT_DEPOSIT_LIMITS_REACHED"):
        vault.deposit(alice, 10_000e18, {"from": alice})

def deposit_after_exchange_rate_change(
    misc_accounts, gov, token, auth, Vault
):
    # mint some tokens to alice
    [alice, bob] = misc_accounts[0:2]
    token.mint(alice, 10_000e18)
    token.mint(bob, 10_000e18)

    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    # deploy and set strategy for vault
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, gov, "MockStrategy")
    vault.trustStrategy(strategy)

    # alice deposits
    token.approve(vault, 10_000e18, {"from": alice})
    vault.deposit(alice, 10_000e18, {"from": alice})
    vault.depositIntoStrategy(10_000e18)

    # mint 10% of yield
    exchangeRateBefore = vault.exchangeRate()
    token.mint(strategy, int(token.balanceOf(strategy) * 0.1))
    vault.harvest([strategy])

    assert vault.exchangeRate() > exchangeRateBefore

    # bob deposits after increase
    token.approve(vault, 10_000e18, {"from": bob})
    vault.deposit(bob, 10_000e18, {"from": bob})
    vault.depositIntoStrategy(10_000e18)

    assert vault.balanceOf(bob) < vault.balanceOf(alice)
