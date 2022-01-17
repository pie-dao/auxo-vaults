import pytest

from brownie import accounts, chain, VaultBase, VaultAuthBase, MockToken, MockStrategy


@pytest.fixture
def deployer():
    return accounts[0]


@pytest.fixture
def mock_accounts():
    return accounts[1:10]


@pytest.fixture
def token(deployer):
    token = MockToken.deploy("Mock Token", "MOCK", {"from": deployer})
    return token


@pytest.fixture
def auth(deployer):
    auth = VaultAuthBase.deploy(deployer.address, {"from": deployer})
    return auth


@pytest.fixture
def vault(deployer, token, auth):
    vault_base = VaultBase.deploy({"from": deployer})
    vault_base.initialize(
        token.address, auth, deployer.address, deployer.address, {"from": deployer}
    )

    auth.addAdmin(vault_base.address, deployer.address, {"from": deployer})
    auth.addHarvester(vault_base.address, deployer.address, {"from": deployer})

    vault_base.triggerPause({"from": deployer})

    return vault_base


@pytest.fixture
def strategy(deployer, token, vault):
    mock_strategy = MockStrategy.deploy({"from": deployer})
    mock_strategy.initialize(
        vault.address,
        token.address,
        deployer.address,
        deployer.address,
        "mock_strategy",
        {"from": deployer},
    )
    return mock_strategy


def test_set_strategy(deployer, vault, strategy):
    vault.trustStrategy(strategy, {"from": deployer})
    vault.setWithdrawalQueue([strategy], {"from": deployer})

    assert vault.withdrawalQueue(0) == strategy.address


def test_deposit_strategy(deployer, token, vault, strategy, mock_accounts):
    users = mock_accounts[:3]
    vault.trustStrategy(strategy, {"from": deployer})

    for user in users:
        token.mint(user.address, 1000 * 1e18, {"from": deployer})

        token.approve(vault, 1000 * 1e18, {"from": user})
        vault.deposit(user.address, 1000 * 1e18, {"from": user})

    assert token.balanceOf(vault) == 3000 * 1e18

    vault.depositIntoStrategy(strategy, token.balanceOf(vault), {"from": deployer})

    assert token.balanceOf(vault) == 0
    assert token.balanceOf(strategy) == 3000 * 1e18


def test_withdraw_strategy(deployer, token, vault, strategy, mock_accounts):
    users = mock_accounts[:3]
    vault.trustStrategy(strategy, {"from": deployer})

    for user in users:
        token.mint(user.address, 1000 * 1e18, {"from": deployer})

        token.approve(vault, 1000 * 1e18, {"from": user})
        vault.deposit(user.address, 1000 * 1e18, {"from": user})

    vault.depositIntoStrategy(strategy, token.balanceOf(vault), {"from": deployer})

    assert token.balanceOf(vault) == 0
    assert token.balanceOf(strategy) == 3000 * 1e18

    vault.withdrawFromStrategy(strategy, 1000 * 1e18, {"from": deployer})

    assert token.balanceOf(vault) == 1000 * 1e18
    assert token.balanceOf(strategy) == 2000 * 1e18


def test_batch_burning(deployer, token, vault, strategy, mock_accounts):
    users = mock_accounts[:3]
    vault.trustStrategy(strategy, {"from": deployer})
    vault.setWithdrawalQueue([strategy], {"from": deployer})

    for user in users:
        token.mint(user.address, 1000 * 1e18, {"from": deployer})

        token.approve(vault, 1000 * 1e18, {"from": user})
        vault.deposit(user.address, 1000 * 1e18, {"from": user})

    vault.depositIntoStrategy(strategy, token.balanceOf(vault), {"from": deployer})

    for user in users:
        balance = vault.balanceOf(user)
        vault.enterBatchBurn(balance, {"from": user})

    vault.execBatchBurn({"from": deployer})

    for user in users:
        vault.exitBatchBurn({"from": user})
        assert token.balanceOf(user) == 1000 * 1e18


def test_batch_burning_with_float(deployer, token, vault, strategy, mock_accounts):
    users = mock_accounts[:3]
    vault.trustStrategy(strategy, {"from": deployer})
    vault.setWithdrawalQueue([strategy], {"from": deployer})

    for user in users:
        token.mint(user.address, 1000 * 1e18, {"from": deployer})

        token.approve(vault, 1000 * 1e18, {"from": user})
        vault.deposit(user.address, 1000 * 1e18, {"from": user})

    vault.depositIntoStrategy(strategy, 2000 * 1e18, {"from": deployer})

    for user in users:
        balance = vault.balanceOf(user)
        vault.enterBatchBurn(balance, {"from": user})

    vault.execBatchBurn({"from": deployer})

    for user in users:
        vault.exitBatchBurn({"from": user})
        assert token.balanceOf(user) == 1000 * 1e18


def test_batch_burning_with_loss(deployer, token, vault, strategy, mock_accounts):
    users = mock_accounts[:3]
    vault.trustStrategy(strategy, {"from": deployer})
    vault.setWithdrawalQueue([strategy], {"from": deployer})

    for user in users:
        token.mint(user.address, 1000 * 1e18, {"from": deployer})

        token.approve(vault, 1000 * 1e18, {"from": user})
        vault.deposit(user.address, 1000 * 1e18, {"from": user})

    vault.depositIntoStrategy(strategy, 3000 * 1e18, {"from": deployer})
    strategy.simulateLoss(500 * 1e18, {"from": deployer})

    assert token.balanceOf(strategy) == 2500 * 1e18

    vault.harvest([strategy], {"from": deployer})

    assert vault.totalStrategyHoldings() == 2500 * 1e18
    assert vault.lockedProfit() == 0

    for user in users:
        vault.enterBatchBurn(vault.balanceOf(user.address), {"from": user})

    vault.execBatchBurn({"from": deployer})

    assert token.balanceOf(vault) == 2499999999999999999000
    assert vault.totalUnderlying() == 1000
    assert vault.totalStrategyHoldings() == 1000

    for user in users:
        vault.exitBatchBurn({"from": user})
        expected = 833333333333333333000  # ~ 2500 / 3
        assert token.balanceOf(user) == expected


def test_expected_return(deployer, token, vault, strategy, mock_accounts):
    users = mock_accounts[:3]
    vault.trustStrategy(strategy, {"from": deployer})
    vault.setWithdrawalQueue([strategy], {"from": deployer})

    for user in users:
        token.mint(user.address, 1000 * 1e18, {"from": deployer})

        token.approve(vault, 1000 * 1e18, {"from": user})
        vault.deposit(user.address, 1000 * 1e18, {"from": user})

    vault.depositIntoStrategy(strategy, 3000 * 1e18, {"from": deployer})

    assert token.balanceOf(strategy) == 3000 * 1e18

    vault.setBlocksPerYear(365, {"from": deployer})

    # mine for approx 7 days
    chain.mine(7, (chain.time() + 604800))

    # yield 150 tokens in a week (approx 10% apr)
    # apr = exchange_rate_increase * (365 days / latest_harvest_days_interval)
    # or in blocks terms:
    # apr = exchange_rate_increase * (blocks_in_a_year / latest_harvest_blocks_interval)
    # in this case:
    # apr = (1 - (3150 / 3000)) * (blocks_in_a_year / latest_harvest_blocks_interval)
    token.mint(strategy.address, 150 * 1e18, {"from": deployer})
    assert token.balanceOf(strategy) == 3150 * 1e18

    vault.harvest([strategy], {"from": deployer})
    assert vault.totalStrategyHoldings() == 3150 * 1e18

    # expected apr should be 10
    assert (vault.estimatedReturn({"from": deployer}) / 1e18) == 10
