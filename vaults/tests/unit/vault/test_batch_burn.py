import pytest
import brownie

from brownie import ZERO_ADDRESS, MockStrategy, Vault

MAX_UINT256 = 2**256 - 1


def test_fail_enter_batch_burn_transfer_fails(misc_accounts, gov, token, auth, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    account = misc_accounts[0]

    token.mint(account, 1000 * 1e18)
    token.approve(vault, 1000 * 1e18, {'from': account})
    vault.deposit(account, 1000 * 1e18, {'from': account})

    with brownie.reverts("ERC20: transfer amount exceeds balance"):
        vault.enterBatchBurn(vault.balanceOf(account) + 1, {"from": account})

def test_fail_enter_batch_burn_different_round(misc_accounts, gov, token, auth, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    account = misc_accounts[0]

    token.mint(account, 1000 * 1e18)
    token.approve(vault, 1000 * 1e18, {'from': account})
    vault.deposit(account, 1000 * 1e18, {'from': account})

    vault.enterBatchBurn(500 * 1e18, {"from": account})
    vault.execBatchBurn()

    with brownie.reverts("enterBatchBurn::DIFFERENT_ROUNDS"):
        vault.enterBatchBurn(vault.balanceOf(account), {'from': account})

def test_exit_batch_burn_fails_if_no_deposit(misc_accounts, gov, token, auth, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    account = misc_accounts[0]

    token.mint(account, 1000 * 1e18)
    token.approve(vault, 1000 * 1e18, {'from': account})
    vault.deposit(account, 1000 * 1e18, {'from': account})

    with brownie.reverts("exitBatchBurn::NO_DEPOSITS"):
        vault.exitBatchBurn({"from": account})

def test_exit_batch_burn_fails_if_round_not_executed(misc_accounts, gov, token, auth, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    account = misc_accounts[0]

    token.mint(account, 1000 * 1e18)
    token.approve(vault, 1000 * 1e18, {'from': account})
    vault.deposit(account, 1000 * 1e18, {'from': account})
    vault.enterBatchBurn(vault.balanceOf(account), {'from': account})

    with brownie.reverts("exitBatchBurn::ROUND_NOT_EXECUTED"):
        vault.exitBatchBurn({"from": account})

def test_enter_batch_burn_different_round(misc_accounts, gov, token, auth, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    account = misc_accounts[0]

    token.mint(account, 1000 * 1e18)
    token.approve(vault, 1000 * 1e18, {'from': account})
    vault.deposit(account, 1000 * 1e18, {'from': account})

    vault.enterBatchBurn(500 * 1e18, {"from": account})
    vault.enterBatchBurn(vault.balanceOf(account), {'from': account})

    receipt = vault.userBatchBurnReceipts(account).dict()

    assert receipt["round"] == 1
    assert receipt["shares"] == 1000 * 1e18

def test_fails_exec_batch_harvest_not_expired(misc_accounts, gov, token, auth, Vault, MockStrategy):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    account = misc_accounts[0]

    token.mint(account, 1000 * 1e18)
    token.approve(vault, 1000 * 1e18, {'from': account})
    vault.deposit(account, 1000 * 1e18, {'from': account})

    vault.setHarvestDelay(86400)
    vault.harvest([])

    with brownie.reverts("batchBurn::LATEST_HARVEST_NOT_EXPIRED"):
        vault.execBatchBurn()

def test_fails_exec_batch_burn_zero_shares(misc_accounts, gov, token, auth, Vault, MockStrategy):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    account = misc_accounts[0]

    token.mint(account, 1000 * 1e18)
    token.approve(vault, 1000 * 1e18, {'from': account})
    vault.deposit(account, 1000 * 1e18, {'from': account})

    with brownie.reverts("batchBurn::TOTAL_SHARES_CANNOT_BE_ZERO"):
        vault.execBatchBurn()

def test_fails_exec_batch_burn_not_enough_underlying(misc_accounts, gov, token, auth, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    account = misc_accounts[0]

    token.mint(account, 1000 * 1e18)
    token.approve(vault, 1000 * 1e18, {'from': account})
    vault.deposit(account, 1000 * 1e18, {'from': account})
    vault.enterBatchBurn(vault.balanceOf(account), {'from': account})
    
    # deploy the strategy
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, gov, "MockStrategy")

    vault.trustStrategy(strategy)
    vault.depositIntoStrategy(strategy, 10 * 1e18)

    assert vault.totalFloat() == 990 * 1e18

    with brownie.reverts("batchBurn::NOT_ENOUGH_UNDERLYING"):
        vault.execBatchBurn()

def test_exec_batch_burn_fees_check(misc_accounts, gov, token, auth, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.triggerPause()
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)

    (account, receiver) = (misc_accounts[0], misc_accounts[1])

    vault.setBurningFeePercent(1e16)
    vault.setBurningFeeReceiver(receiver)

    token.mint(account, 1000 * 1e18)
    token.approve(vault, 1000 * 1e18, {'from': account})
    vault.deposit(account, 1000 * 1e18, {'from': account})
    vault.enterBatchBurn(vault.balanceOf(account), {'from': account})    
    vault.execBatchBurn()

    assert token.balanceOf(receiver) == 10 * 1e18

def test_e2e_batched_burning(misc_accounts, gov, token, auth, Vault, MockStrategy):
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

def test_e2e_batched_burning_loss(misc_accounts, gov, token, auth, Vault):
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
