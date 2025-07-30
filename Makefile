-include .env

.PHONY: all test deploy

build :; forge build

install :; forge install cyfrin/foundry-devops@0.3.2 && forge install smartcontractkit/chainlink-brownie-contracts@1.3.0 && forge install OpenZeppelin/openzeppelin-contracts@v5.3.0 && forge install foundry-rs/forge-std@v1.9.7 && forge install transmissions11/solmate@v6

test :; forge test

test-anvil :; forge test --fork-url 127.0.0.1:8545

