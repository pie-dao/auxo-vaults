# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# update interfaces from the hub
tests :; cp hub/src/interfaces/* interfaces && forge test


