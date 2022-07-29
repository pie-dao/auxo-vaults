
## Overview

![](./vaults/overview.png)

### How batched burning works

Withdrawing from `vaults` is achieved through batched burning of shares. The flow for a batched burning round is:

- Users deposits shares when they want to withdraw. (contract-wise, the `userBatchBurnReceipts` mapping is populated when `enterBatchBurn` is called).
- Once enough deposits are done, an admin can call `execBatchBurn` to withdraw from strategies and burn the deposited shares. A snapshot of the current price per share will be done.
- Users can now withdraw their underlying using `exitBatchBurn`.

### Brownie

1. Create and activate a virtualenv for the project (using Python 3.8):

```
python3.8 -m venv venv
source venv/bin/activate
```

2. Install required packages:

```
pip install -r requirements.txt
```


3. Build the project:

```
brownie compile
```

4. Run tests

```
brownie test
```


# Foundry

Full details are in the [Hub Repo](./hub/README.md)

Ensure you have Foundry installed with `foundryup`, then install the required dependencies:

```sh
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
forge install paulrberg/prb-test@0.1.2


```
# Monorepo Gotchas

This repo is in a somewhat transitive state, we would like to move to a full monorepo style setup but the solidity tooling is still young.
For the time being, you can do the following:

- For single-package testing, cd into the relevant directory and either run the tests with brownie or foundry
    - Make sure to activate the venv if using brownie
    - For foundry, make sure to install dependencies in the [PACKAGE_NAME]/lib folder
    - For foundry, make sure your remappings.txt file in the package uses the same identifiers as in the root, but, importantly, point the identifier to the package location. Example


In the root:

```
# openzeppelin should be installed in the root `lib/` folder
@oz/=lib/openzeppelin-contracts/contracts/
@hub/=hub/src/
```

In the package:

```
# openzeppelin should ALSO be installed in the `hub/lib/` folder
@oz/=lib/openzeppelin-contracts/contracts/

# this is different from the root, but means your IDE and foundry will work regardless of whether running
# in context of package or root context
@hub/=src/
```
This is a little fiddly, but it's also fairly easy to do and check, i'll probably write a script to automate at a point in the future, or incorporate something like Nx with solidity.