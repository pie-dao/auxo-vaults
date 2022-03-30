import pytest
import brownie

from brownie import ZERO_ADDRESS, MockStrategy, Vault

MAX_UINT256 = 2**256 - 1


def test_batched_burning(misc_accounts, gov, token, auth, Vault, MockStrategy):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    for u in misc_accounts:
        token.mint(u, 1000 * 1e18)

        token.approve(vault, 1000 * 1e18, {"from": u})
        vault.deposit(u, 1000 * 1e18, {"from": u})

    for u in misc_accounts:
        balance = vault.balanceOf(u)
        vault.enterBatchBurn(balance, {"from": u})

        receipt = vault.userBatchBurnReceipts(u).dict()

        assert receipt["round"] == 1
        assert receipt["shares"] == balance

    total_shares = vault.totalSupply()

    vault.execBatchBurn()

    batch_burn = vault.batchBurns(1).dict()
    assert batch_burn["totalShares"] == total_shares
    assert batch_burn["amountPerShare"] == 1e18

    for u in misc_accounts:
        vault.exitBatchBurn({"from": u})
        assert token.balanceOf(u) == 1000 * 1e18


def test_batched_burning_loss(misc_accounts, gov, token, auth, Vault, MockStrategy):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    for u in misc_accounts:
        token.mint(u, 1000 * 1e18)

        token.approve(vault, 1000 * 1e18, {"from": u})
        vault.deposit(u, 1000 * 1e18, {"from": u})

    for u in misc_accounts:
        balance = vault.balanceOf(u)
        vault.enterBatchBurn(balance, {"from": u})

    token.burn(vault, 100 * 1e18)

    total_shares = vault.totalSupply()
    exchange_rate = vault.exchangeRate()

    vault.execBatchBurn()

    batch_burn = vault.batchBurns(1).dict()
    assert batch_burn["totalShares"] == total_shares
    assert batch_burn["amountPerShare"] == exchange_rate

    for u in misc_accounts:
        vault.exitBatchBurn({"from": u})
        assert token.balanceOf(u) == (1000 * exchange_rate)
