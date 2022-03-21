import pytest

from brownie import (
    ZERO_ADDRESS,
    MockToken,
    MockStrategy,
    MultiRolesAuthority,
    Vault,
    VaultFactory,
)


GOV_ROLE = 0
KEEPER_ROLE = 1

GOV_CAPABILITIES = [
    "triggerPause",
    "setDepositLimits",
    "setAuth",
    "setBlocksPerYear",
    "setHarvestFeePercent",
    "setBurningFeePercent",
    "setHarvestFeeReceiver",
    "setBurningFeeReceiver",
    "setHarvestWindow",
    "setHarvestDelay",
    "setWithdrawalQueue",
    "trustStrategy",
    "distrustStrategy",
    "execBatchBurn",
    "harvest",
    "depositIntoStrategy",
    "withdrawFromStrategy",
]

KEEPER_CAPABILITIES = [
    "execBatchBurn",
    "harvest",
    "depositIntoStrategy",
    "withdrawFromStrategy",
]


def set_capabilities_for_auth(auth, role, capabilities):
    for c in capabilities:
        auth.setRoleCapability(role, Vault.signatures[c], True)


@pytest.fixture
def gov(accounts):
    yield accounts[0]


@pytest.fixture
def keeper(accounts):
    yield accounts[1]


@pytest.fixture
def misc_accounts(accounts):
    yield accounts[2:5]


@pytest.fixture
def create_token(gov):
    def create_token(name="Mock Token", symbol="MCK"):
        token = gov.deploy(MockToken, name, symbol)
        token.mint(gov, 1_000_000 * 1e18)
        return token

    yield create_token


@pytest.fixture
def token(create_token):
    yield create_token()


@pytest.fixture
def create_auth(gov, keeper):
    def create_auth():
        auth = gov.deploy(MultiRolesAuthority, gov, ZERO_ADDRESS)

        # set user roles and public capabilities
        auth.setUserRole(gov, GOV_ROLE, True)
        auth.setUserRole(keeper, KEEPER_ROLE, True)
        auth.setPublicCapability(Vault.signatures["deposit"], True)

        # set role-specific capabilities
        set_capabilities_for_auth(auth, GOV_ROLE, GOV_CAPABILITIES)
        set_capabilities_for_auth(auth, KEEPER_ROLE, KEEPER_CAPABILITIES)

        return auth

    yield create_auth


@pytest.fixture
def auth(create_auth):
    yield create_auth()


@pytest.fixture
def create_vault_implementation(gov):
    def create_vault_implementation():
        return gov.deploy(Vault)

    yield create_vault_implementation


@pytest.fixture
def vault_implementation(create_vault_implementation):
    yield create_vault_implementation()


@pytest.fixture
def create_factory(gov, vault_implementation):
    def create_factory():
        factory = gov.deploy(VaultFactory)
        factory.setImplementation(vault_implementation)
        return factory

    yield create_factory


@pytest.fixture
def factory(create_factory):
    yield create_factory()


@pytest.fixture
def create_vault(gov, token, auth, factory):
    def create_vault():
        tx = factory.deployVault(token, auth, ZERO_ADDRESS, ZERO_ADDRESS, {"from": gov})
        return tx.return_value

    yield create_vault


@pytest.fixture
def vault(create_vault):
    yield create_vault()


@pytest.fixture
def create_strategy(gov, keeper, token, vault):
    def create_strategy():
        strategy = gov.deploy(MockStrategy)
        strategy.initialize(vault, token, gov, keeper, "MockStrategy")

        return strategy

    yield create_strategy


@pytest.fixture
def strategy(create_strategy):
    yield create_strategy()
