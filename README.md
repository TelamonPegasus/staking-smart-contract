### Requirements
solidity staking smart contract with following requirements:
1. Users should be able to stake their tokens at any time. Including the presale tokens
2. The staking should be available soon as the presale is over.
3. Users can stake tokens in 1 month intervals with a maximum stake of 5 years.
4. The APY will be calculated based on the number of months. With a cap of 50%
    - 1Q 10%
    - 2Q 25%
    - 3Q 35%
    - 4Q 50%
5. If a user breaks the stake before the time is up, they lose all rewards earned up to that point
6. The reward tokens can’t be claimed until the stake fully matures

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
