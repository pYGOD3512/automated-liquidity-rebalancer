# Automated Liquidity Rebalancer

A smart contract system that automatically rebalances liquidity positions across different pools based on market conditions, using historical data and price feeds to optimize yield with a dynamic fee structure.

## Disclaimer: Use of Unaudited Code for Educational Purposes Only
This code is provided strictly for educational purposes and has not undergone any formal security audit. 
It may contain errors, vulnerabilities, or other issues that could pose risks to the integrity of your system or data.

By using this code, you acknowledge and agree that:
- No Warranty: The code is provided "as is" without any warranty of any kind, either express or implied. The entire risk as to the quality and performance of the code is with you.
- Educational Use Only: This code is intended solely for educational and learning purposes. It is not intended for use in any mission-critical or production systems.
- No Liability: In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the use or performance of this code.
- Security Risks: The code may not have been tested for security vulnerabilities. It is your responsibility to conduct a thorough security review before using this code in any sensitive or production environment.
- No Support: The authors of this code may not provide any support, assistance, or updates. You are using the code at your own risk and discretion.

Before using this code, it is recommended to consult with a qualified professional and perform a comprehensive security assessment. By proceeding to use this code, you agree to assume all associated risks and responsibilities.

## Features
- Automated rebalancing based on market volatility
- Dynamic fee structure that adjusts with market conditions
- Price history tracking for volatility calculations
- Configurable rebalancing parameters
- Event emission for tracking important operations

## Setup

### Prerequisites
Before we proceed, we should install a couple of things. Also, if you are using a Windows machine, it's recommended to use WSL2.

On Ubuntu/Debian/WSL2(Ubuntu):
```
sudo apt update
sudo apt install curl git-all cmake gcc libssl-dev pkg-config libclang-dev libpq-dev build-essential -y
```
On MacOs:
```
brew install curl cmake git libpq
```
If you don't have `brew` installed, run this:
```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Next, we need rust and cargo:
```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```
if you get an error like this:
```
error: could not amend shell profile: '/home/codespace/.config/fish/conf.d/rustup.fish': could not write rcfile file: '/home/codespace/.config/fish/conf.d/rustup.fish': No such file or directory (os error 2)
```
run these commands and re-run the rustup script:
```
mkdir -p /home/codespace/.config/fish/conf.d
touch /home/codespace/.config/fish/conf.d/rustup.fish
```

### Install Sui
If you are using Github codespaces, it's recommended to use pre-built binaries rather than building them from source.

To download pre-built binaries, you should run `download-sui-binaries.sh` in the terminal. 
This scripts takes three parameters (in this particular order) - `version`, `environment` and `os`:
- sui version, for example `1.15.0`. You can lookup a more up-to-date version available here [SUI Github releases](https://github.com/MystenLabs/sui/releases).
- `environment` - that's the environment that you are targeting, in our case it's `testnet`. Other available options are: `devnet` and `mainnet`.
- `os` - name of the os. If you are using Github codespaces, put `ubuntu-x86_64`. Other available options are: `macos-arm64`, `macos-x86_64`, `ubuntu-x86_64`, `windows-x86_64` (not for WSL).

To donwload SUI binaries for codespace, run this command:
```
./download-sui-binaries.sh "v1.21.1" "testnet" "ubuntu-x86_64"
```
and restart your terminal window.

If you prefer to build the binaries from source, run this command in your terminal:
```
cargo install --locked --git https://github.com/MystenLabs/sui.git --branch testnet sui
```

### Install dev tools (not required, might take a while when installin in codespaces)
```
cargo install --git https://github.com/move-language/move move-analyzer --branch sui-move --features "address32"

```

### Run a local network
To run a local network with a pre-built binary (recommended way), run this command:
```
RUST_LOG="off,sui_node=info" sui-test-validator
```

Optionally, you can run it from sources.
```
git clone --branch testnet https://github.com/MystenLabs/sui.git

cd sui

RUST_LOG="off,sui_node=info" cargo run --bin sui-test-validator
```

### Install SUI Wallet (optionally)
```
https://chrome.google.com/webstore/detail/sui-wallet/opcgpfmipidbgpenhmajoajpbobppdil?hl=en-GB
```

### Configure connectivity to a local node
Once the local node is running (using `sui-test-validator`), you should the url of a local node - `http://127.0.0.1:9000` (or similar).
Also, another url in the output is the url of a local faucet - `http://127.0.0.1:9123`.

Next, we need to configure a local node. To initiate the configuration process, run this command in the terminal:
```
sui client active-address
```
The prompt should tell you that there is no configuration found:
```
Config file ["/home/codespace/.sui/sui_config/client.yaml"] doesn't exist, do you want to connect to a Sui Full node server [y/N]?
```
Type `y` and in the following prompts provide a full node url `http://127.0.0.1:9000` and a name for the config, for example, `localnet`.

On the last prompt you will be asked which key scheme to use, just pick the first one (`0` for `ed25519`).

After this, you should see the ouput with the wallet address and a mnemonic phrase to recover this wallet. You can save so later you can import this wallet into SUI Wallet.

Additionally, you can create more addresses and to do so, follow the next section - `Create addresses`.

### Testnet configuration

For the sake of this tutorial, let's add a testnet node:
```
sui client new-env --rpc https://fullnode.testnet.sui.io:443 --alias testnet
```
and switch to `testnet`:
```
sui client switch --env testnet
```

### Create addresses
For this tutorial we need two separate addresses. To create an address run this command in the terminal:
```
sui client new-address ed25519
```
where:
- `ed25519` is the key scheme (other available options are: `ed25519`, `secp256k1`, `secp256r1`)

And the output should be similar to this:
```
╭─────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Created new keypair and saved it to keystore.                                                   │
├────────────────┬────────────────────────────────────────────────────────────────────────────────┤
│ address        │ 0x05db1e318f1e4bc19eb3f2fa407b3ebe1e7c3cd8147665aacf2595201f731519             │
│ keyScheme      │ ed25519                                                                        │
│ recoveryPhrase │ lava perfect chef million beef mean drama guide achieve garden umbrella second │
╰────────────────┴────────────────────────────────────────────────────────────────────────────────╯
```
Use `recoveryPhrase` words to import the address to the wallet app.


### Get localnet SUI tokens
```
curl --location --request POST 'http://127.0.0.1:9123/gas' --header 'Content-Type: application/json' \
--data-raw '{
    "FixedAmountRequest": {
        "recipient": "<ADDRESS>"
    }
}'
```
`<ADDRESS>` - replace this by the output of this command that returns the active address:
```
sui client active-address
```

You can switch to another address by running this command:
```
sui client switch --address <ADDRESS>
```
abd run the HTTP request to mint some SUI tokens to this account as well.

Also, you can top up the balance via the wallet app. To do that, you need to import an account to the wallet.

### Get testnet SUI tokens
After you switched to `testnet`, run this command to get 1 testnet SUI:
```
sui client faucet
```
it will use the the current active address and the current active network.

## Build and publish the Rebalancer contract

### Build package
```bash
sui move build
```

### Publish package
```bash
sui client publish --gas-budget 100000000 --json
```

After the contract is published, set these environment variables:
- `PACKAGE_ID` - the published package ID
- `CLOCK_OBJECT_ID` - default to `0x6`
- `ADMIN_ADDRESS` - your admin address from `sui client active-address`

## Interact with the Rebalancer

### Create a new pool
```bash
sui client call --package $PACKAGE_ID --module rebalancer --function create_pool --gas-budget 10000000000
```

### Deposit funds
```bash
sui client call --package $PACKAGE_ID --module rebalancer --function deposit \
    --args $POOL_ID $COIN_ID $CLOCK_OBJECT_ID \
    --gas-budget 10000000000 --json
```

### Update price and trigger rebalancing
```bash
sui client call --package $PACKAGE_ID --module rebalancer --function update_price_and_volatility \
    --args $POOL_ID $NEW_PRICE $CLOCK_OBJECT_ID \
    --gas-budget 10000000000 --json
```

### Withdraw funds
```bash
sui client call --package $PACKAGE_ID --module rebalancer --function withdraw \
    --args $POOL_ID $AMOUNT $CLOCK_OBJECT_ID \
    --gas-budget 10000000000 --json
```

## Testing

Run the test suite:
```bash
sui move test
```

The test suite includes:
- Initialization tests
- Pool creation tests
- Deposit and withdrawal tests
- Price update and volatility calculation tests
- Rebalancing logic tests

## Key Parameters

- `VOLATILITY_WINDOW`: 1 hour (in milliseconds)
- `MAX_PRICE_CHANGE_THRESHOLD`: 5% price change threshold
- `MIN_REBALANCE_INTERVAL`: 5 minutes (in milliseconds)
- Base fee rate: 0.1%
- Volatility multiplier: 2x (doubles fees in high volatility)

## Events Emitted

- `DepositEvent`: When funds are deposited
- `WithdrawEvent`: When funds are withdrawn
- Price updates and rebalancing operations are tracked through events

## Security Considerations

- The contract includes basic safety checks
- Implements access control for admin functions
- Includes minimum rebalance intervals to prevent manipulation
- Price updates are restricted to prevent extreme changes

## Future Improvements

- Implementation of more sophisticated volatility calculations
- Additional rebalancing strategies
- Integration with external price oracles
- Enhanced security features
