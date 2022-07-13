import pytest
import brownie

from brownie import ZERO_ADDRESS, MockStrategy, Vault, chain

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

def test_fails_trust_strategy_different_underlying(gov, create_token, token, auth, MockStrategy, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)

    # deploy the strategy
    diff_token = create_token()
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, diff_token, gov, gov, "MockStrategy")

    with brownie.reverts("trustStrategy::WRONG_UNDERLYING"):
        vault.trustStrategy(strategy, {"from": gov})
    
    assert not vault.getStrategyData(strategy)["trusted"]

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

def test_cant_deposit_amount_zero_in_trusted_strategy(gov, token, auth, MockStrategy, Vault):
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
    with brownie.reverts("depositIntoStrategy::AMOUNT_CANNOT_BE_ZERO"):
        vault.depositIntoStrategy(strategy, 0)

def test_cant_deposit_failed_minting(gov, token, auth, MockStrategy, Vault):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)
    vault.triggerPause()

    # deploy the strategy
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, gov, "MockStrategy")
    strategy.setSuccess(False)

    # trust the strategy
    vault.trustStrategy(strategy, {"from": gov})

    # deposit underlying in the vault
    token.approve(vault, 1e19)
    vault.deposit(gov, 1e19)

    # deposit underlying in the strategy
    with brownie.reverts("depositIntoStrategy::MINT_FAILED"):
        vault.depositIntoStrategy(strategy, 1e18)

def test_fails_withdraw_from_untrusted_strategy(gov, token, auth, MockStrategy, Vault):
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

    vault.distrustStrategy(strategy, {"from": gov})

    # withdraw underlying from strategy
    with brownie.reverts("withdrawFromStrategy::UNTRUSTED_STRATEGY"):
        vault.withdrawFromStrategy(strategy, 9e18)

def test_fails_withdraw_zero_from_strategy(gov, token, auth, MockStrategy, Vault):
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
    with brownie.reverts("withdrawFromStrategy::AMOUNT_CANNOT_BE_ZERO"):
        vault.withdrawFromStrategy(strategy, 0)

def test_fails_withdraw_more_than_deposit_from_strategy(gov, token, auth, MockStrategy, Vault):
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

    # simulate a loss: 
    #   - underlying accounted in vault is 9e18
    #   - actual underlying in the strategy is 8e18
    strategy.simulateLoss(1e18)

    # withdraw underlying from strategy
    with brownie.reverts("withdrawFromStrategy::REDEEM_FAILED"):
        vault.withdrawFromStrategy(strategy, 9e18)

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

def test_harvest_happy_path_profit_state(gov, keeper, token, auth, MockStrategy):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)
    vault.triggerPause()

    vault.setHarvestDelay(7200)
    vault.setHarvestWindow(900)

    # deploy the strategies
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, keeper, "MockStrategy")

    new_strategy = gov.deploy(MockStrategy)
    new_strategy.initialize(vault, token, gov, keeper, "MockStrategy")

    # deposit underlying in the vault
    token.approve(vault, 1e19)
    vault.deposit(gov, 1e19)

    vault.trustStrategy(strategy)
    vault.trustStrategy(new_strategy)

    # deposit underlying in the strategy
    vault.depositIntoStrategy(strategy, 5e18)
    vault.depositIntoStrategy(new_strategy, 5e18)

    # mint some tokens, simulating yield
    # 2 units of yield on 10 units of underlying is 20% of return 
    token.mint(strategy, 1e18)
    token.mint(new_strategy, 1e18)

    vault.harvest([strategy, new_strategy])

    assert vault.lastHarvestExchangeRate() == 1e18
    assert vault.lastHarvestWindowStartBlock() == chain[-1].number
    assert vault.lastHarvestWindowStart() == chain[-1].timestamp
    assert vault.totalStrategyHoldings() == 1e19 + 2e18
    assert vault.maxLockedProfit() == 2e18


def test_harvest_applies_new_harvest_delay(gov, keeper, token, auth, MockStrategy):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)
    vault.triggerPause()

    vault.setHarvestDelay(7200)
    vault.setHarvestWindow(900)
    vault.setHarvestFeePercent(1e16)
    vault.setHarvestFeeReceiver(keeper)

    # deploy the strategies
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, keeper, "MockStrategy")

    new_strategy = gov.deploy(MockStrategy)
    new_strategy.initialize(vault, token, gov, keeper, "MockStrategy")

    # deposit underlying in the vault
    token.approve(vault, 1e19)
    vault.deposit(gov, 1e19)

    vault.trustStrategy(strategy)
    vault.trustStrategy(new_strategy)

    # deposit underlying in the strategy
    vault.depositIntoStrategy(strategy, 5e18)
    vault.depositIntoStrategy(new_strategy, 5e18)

    assert vault.harvestDelay() == 7200

    vault.setHarvestDelay(14400)

    assert vault.nextHarvestDelay() == 14400

    vault.harvest([strategy, new_strategy])

    assert vault.harvestDelay() == 14400

def test_harvest_fees_check(gov, keeper, token, auth, MockStrategy):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)
    vault.triggerPause()

    vault.setHarvestDelay(7200)
    vault.setHarvestWindow(900)
    vault.setHarvestFeePercent(1e16)
    vault.setHarvestFeeReceiver(keeper)

    # deploy the strategies
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, keeper, "MockStrategy")

    new_strategy = gov.deploy(MockStrategy)
    new_strategy.initialize(vault, token, gov, keeper, "MockStrategy")

    # deposit underlying in the vault
    token.approve(vault, 1e19)
    vault.deposit(gov, 1e19)

    vault.trustStrategy(strategy)
    vault.trustStrategy(new_strategy)

    # deposit underlying in the strategy
    vault.depositIntoStrategy(strategy, 5e18)
    vault.depositIntoStrategy(new_strategy, 5e18)

    # mint some tokens, simulating yield
    # 2 units of yield at 0.1% fee should be 0,02 units of underlying
    token.mint(strategy, 1e18)
    token.mint(new_strategy, 1e18)

    vault.harvest([strategy, new_strategy])

    keeper_balance = vault.balanceOf(keeper)

    assert keeper_balance > 0
    assert vault.calculateUnderlying(keeper_balance) == 2e16


def test_harvest_consecutive(gov, keeper, token, auth, MockStrategy):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)
    vault.triggerPause()

    vault.setHarvestDelay(7200)
    vault.setHarvestWindow(900)

    # deploy the strategies
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, keeper, "MockStrategy")

    new_strategy = gov.deploy(MockStrategy)
    new_strategy.initialize(vault, token, gov, keeper, "MockStrategy")

    # deposit underlying in the vault
    token.approve(vault, 1e19)
    vault.deposit(gov, 1e19)

    vault.trustStrategy(strategy)
    vault.trustStrategy(new_strategy)

    # deposit underlying in the strategy
    vault.depositIntoStrategy(strategy, 4e18)
    vault.depositIntoStrategy(new_strategy, 5e18)

    vault.harvest([strategy])
    vault.harvest([new_strategy])

def test_fails_harvest_bad_harvest_time(gov, keeper, token, auth, MockStrategy):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)
    vault.triggerPause()

    vault.setHarvestDelay(7200)
    vault.setHarvestWindow(900)

    # deploy the strategies
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, keeper, "MockStrategy")

    new_strategy = gov.deploy(MockStrategy)
    new_strategy.initialize(vault, token, gov, keeper, "NewMockStrategy")

    vault.trustStrategy(strategy)
    vault.trustStrategy(new_strategy)

    # deposit underlying in the vault
    token.approve(vault, 1e19)
    vault.deposit(gov, 1e19)

    # deposit underlying in the strategy
    vault.depositIntoStrategy(strategy, 4e18)
    vault.depositIntoStrategy(strategy, 5e18)

    vault.harvest([strategy])
    chain.sleep(901)

    with brownie.reverts("harvest::BAD_HARVEST_TIME"):
        vault.harvest([new_strategy])


def test_fails_harvest_untrusted_strategy(gov, keeper, token, auth, MockStrategy):
    # deploy the vault
    vault = gov.deploy(Vault)
    vault.initialize(token, auth, ZERO_ADDRESS, ZERO_ADDRESS)
    vault.setDepositLimits(MAX_UINT256, MAX_UINT256)
    vault.triggerPause()

    # deploy the strategy
    strategy = gov.deploy(MockStrategy)
    strategy.initialize(vault, token, gov, keeper, "MockStrategy")

    # deposit underlying in the vault
    token.approve(vault, 1e19)
    vault.deposit(gov, 1e19)

    vault.trustStrategy(strategy)

    # deposit underlying in the strategy
    vault.depositIntoStrategy(strategy, 9e18)

    vault.distrustStrategy(strategy)

    with brownie.reverts("harvest::UNTRUSTED_STRATEGY"):
        vault.harvest([strategy])
