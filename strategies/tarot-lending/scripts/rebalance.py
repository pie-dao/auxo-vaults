from ape_safe import ApeSafe
from brownie import Contract, BorrowableHelpers, accounts

import json
import click
import requests

strategies = [
    { # wftm
        'underlying': '0x21be370d5312f44cb42ce377bc9b8a0cef1a4c83',
        'strategy': '0xEC33b70681e0c7b9A8FCb72931B656e3F6Ff971c'
    },
    { # frax
        'underlying': '0xdc301622e621166bd8e82f2ca0a26c13ad0be355',
        'strategy': '0xeb8De8047fD66979490629c34288f8a78e97B00B'
    },
    { # usdc
        'underlying': '0x04068da6c83afcfa0e13ba15a6696662335d5b75',
        'strategy': '0xE85E08406369C08Fbf338ff25C37d12FeA3c7e86'
    }
]

def do_query(underlying):
    query = f'query {{ borrowables(where: {{underlying: "{underlying}"}}) {{id}} }}'
    api = "https://api.thegraph.com/subgraphs/name/tarot-finance/tarot"
    response = requests.post(api, json={"query": query}).json()
    return response['data']['borrowables']

def query(underlying):
    borrowables = do_query(underlying)
    json.dump(borrowables, open(f'scripts/borrowables/borrowables-{underlying}.json', 'w+'), indent=4)

def compute_best(strat_addr, underlying, safe):
    account = accounts[0]
    strat = Contract.from_explorer(strat_addr)
    borrowables = json.load(open(f'scripts/borrowables/borrowables-{underlying}.json', 'r+'))
    borrowable_helper = BorrowableHelpers.deploy({'from': account})

    current_borrowable = strat.allocations(0).dict()['bor']

    best = -1
    best_borr = ''
    for borr in borrowables:
        if borr["id"] != current_borrowable:
            ret = borrowable_helper.getNextSupplyRate(borr["id"], strat.estimatedUnderlying(), 0).return_value.dict()
        else:
            ret = borrowable_helper.getCurrentSupplyRate(borr["id"]).return_value.dict()

        if ret['supplyRate_'] > best:
            best = ret['supplyRate_']
            best_borr = borr["id"]
        
    print(f'best borrowable: {best_borr}')
    print(f'supply rate: {best}')

    if best_borr != current_borrowable:
        strat.setAllocations([(best_borr, 1e18)], {'from': safe.account})

    return True

def main():
    safe = ApeSafe('0x309DCdBE77d9D73805e96662503B08FEe229597A')

    for item in strategies:
        query(item['underlying'])
        compute_best(item['strategy'], item['underlying'], safe)

    safe_tx = safe.multisend_from_receipts()
    safe.sign_with_frame(safe_tx)
    safe.post_transaction(safe_tx)
