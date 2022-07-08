from brownie import (
    ZERO_ADDRESS,
    Vault,
    VaultFactory,
    network,
    exceptions,
    accounts,
    MultiRolesAuthority,
    interface,
)
import os


"""
Deployed contracts 

VaultFactory 0x38733E49727839a06e1Ef37B67b24beF82Ef906a
Vault Impl 0x4fCC9951BB19AaCd34a8dbC1eDF616E297e52228
Auth 0x55be265EF1C89867724228522E75c7eb72eCf969

You need to have the API key ETHERSCAN_TOKEN
"""

# make sure your env file is setup, alternatively, use the console
# make sure you cd into vaults

# check you are on the correct network, add this:
# brownie networks add live optimism-kovan host=https://kovan.optimism.io chainid=69 explorer=https://api-kovan-optimistic.etherscan.io/api
# brownie networks add live arbitrum-rinkeby host=https://rinkeby.arbitrum.io/rpc chainid=421611 explorer=https://api-testnet.arbiscan.io/api


# check network
if not network.show_active() == "optimistic-kovan":
    # dev - custom exception
    raise exceptions.BrownieEnvironmentWarning("Connected to Wrong network")


# connect to account
# apparently you can get this automatically
accounts.add(os.environ.get("PRIVATE_KEY"))
# accounts.add($PRIVATE_KEY)

if not accounts:
    raise exceptions.BrownieEnvironmentWarning("Account not connected")

# choose governor accounts
gov = accounts[0]

# Deploy a new instance of the vault factory
VaultFactory.deploy({"from": gov}, publish_source=True)
vault_factory = VaultFactory[0]


# Deploy an instance of the vault and set the implementation
vault = Vault.deploy({"from": gov}, publish_source=True)
vault_factory.setImplementation(vault.address, {"from": gov})


# Deploy the auth module
auth = MultiRolesAuthority.deploy(gov, ZERO_ADDRESS, {"from": gov}, publish_source=True)

# set user roles and public capabilities
GOV_ROLE = 0
auth.setUserRole(gov, GOV_ROLE, True)
auth.setPublicCapability(Vault.signatures["deposit"], True)

# set role-specific capabilities
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

# iterate through capabilities to set role permissions
def set_capabilities_for_auth(auth, role, capabilities):
    for c in capabilities:
        auth.setRoleCapability(role, Vault.signatures[c], True)


# execute for the governor
set_capabilities_for_auth(auth, GOV_ROLE, GOV_CAPABILITIES)

# deploy the actual vault

# USDC_ADDRESS = "0x567f39d9e6d02078F357658f498F80eF087059aa" # opt-kov
USDC_ADDRESS = "0x1EA8Fb2F671620767f41559b663b86B1365BBc3d"  # arb rink
usdc = interface.IERC20(USDC_ADDRESS)
vault_factory.deployVault(usdc, auth, ZERO_ADDRESS, ZERO_ADDRESS, {"from": gov})


# approve deposits
MAX_INT = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
vault_proxy = Vault.at(""" Proxy address """)
usdc.approve(vault_proxy, MAX_INT, {"from": gov})

# admin shit
vault_proxy.triggerPause({"from": gov})
vault_proxy.setDepositLimits(MAX_INT, MAX_INT, {"from": gov})

# make deposit
vault_proxy.deposit(gov, 1e9, {"from": gov})

# validate: should equal deposits
vault.proxy.balanceOf(gov)

# Trust a strategy
KOVAN_XCHAIN_STRAT = "0xfa0299ef90f0351918ecdc8f091053335dcfb8c9"
vault_proxy.trustStrategy(KOVAN_XCHAIN_STRAT, {"from": gov})

ARBITRUM_XCHAIN_STRAT = "0x69b8c988b17bd77bb56bee902b7ab7e64f262f35"
vault_proxy.trustStrategy(ARBITRUM_XCHAIN_STRAT, {"from": gov})

# deposit into the strategy
vault_proxy.depositIntoStrategy(
    KOVAN_XCHAIN_STRAT, usdc.balanceOf(vault_proxy.address), {"from": gov}
)
# validate
vault_proxy.totalStrategyHoldings()
