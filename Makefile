-include .env

.PHONY: all test deploy

build :; forge build

test :; forge test fork-url 127.0.0.1:8545 --fork-block-number 1

test-anvil :; forge test --fork-url https://github.com/Cyfrin/foundry-full-course-cu/discussions/2246

install :; forge install cyfrin/foundry-devops@0.3.2 && forge install smartcontractkit/chainlink-brownie-contracts@1.3.0 && forge install OpenZeppelin/openzeppelin-contracts@v5.3.0 && forge install foundry-rs/forge-std@v1.9.7 && forge install transmissions11/solmate@v6

deploy-sepolia :; 
forge script script/DeployRaffle.s.sol:deployStablecoinRaffle --rpc-url $(SEPOLIA_RPC_URL) --account defaultKey --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
