# Signals and Slots in Smart Contract Execution
This repository presents a high level description of our conception and implementation of signals and slots in the context of smart contract execution. A more formal description will be in a seperate document. The term "signals and slots" is borrowed from the language construct introduced by Qt for communications between objects. As we describe later, we aim to provide a high level functionality that is similar to what was introduced by Qt, except with communications between contracts rather than objects. This document is split into the following sections:

1. Specifications
2. Proposed Syntax
    * Signals
    * Slots
    * Delayed Emit
3. Blockchain Support
    * EVM Opcodes
    * Signals
    * Slots
    * World State
    * Block Header
    * State Transitions
    * Mining Incentives
4. Potential Applications
    * MakerDAO
    * Compound
    * Augur
5. Implementation on Conflux

## 1. Specifications
The general idea of signals and slots is to provide a framework for contracts to execute a certain block of code when a certain event occurs. We call the event a 'signal' and the listener a 'slot'. In the signals/slots construct, the emitter of the signal does not need to know who is listening to the signal. This property is very useful for smart contract development because this allows developers to add slots to a certain signals without redeploying the contract that emits the signal. 

To summarize, the key pieces of functionality are the folowing:
1. Emission of signals that any number of slots can listen
2. Emission of signals with parameters that can be used by slots
3. Delayed emission of a signal by a certain amount of time (approximated by block numbers)
4. Execution of a block of code whenever a signal of interest is emitted using slots
5. Binding of a single slot to multiple different signals
6. Guarentee that slots will be executed eventually given that there is sufficient gas
7. Guarentee that slots are executed before any pending transactions in the contract

Further, limitations of this feature include:
1. Slots can only bind to one signal, and that signal must already exist on the network prior to deployment
2. Slots cannot unbind from a signal one binded
3. Slots must return void

## 2. Proposed Syntax
This section covers what the solidity syntax support for signals/slots might look like. This is tentative and may not be the best design. One source of bugs might come from developers either forgetting to bind the slots to signals in the constructor or mismatching the parameters of the slots with those of the signals they intend on listening to. This execution behaviour is undetermined for now. It would be best if such errors could be detected at compile time.

#### Signals
To emit a signal, declare the signal in a contract then use the emit keyword to broadcast it across the network. At this time we also declare the types of the parameters.
```
contract Sender {
	// Declare a signal
	signal Update(uint info);

	function sendUpdate(uint info) public {
		emit Update(info);
	}
}
```
#### Slots
To listen to a signal, declare a slot and bind it to a specific signal in the constructor.
```
contract Receiver {
	uint public info;
	Sender public s;

	// Declare a slot and define its code
    slot updateHandler(new_info) {
        info = new_info;
    }

    // Get ABI of Sender and bind updateHandler to it
    constructor(address sender_addr) public {
        s = Sender(sender_addr);
        updateHandler.bind(s.Update);
    }
}
```
#### Delayed Emit
To emit a signal after a time delay, emit with the delay method. The argument is the number of blocks to delay by. As of writing, ethereum generates around one block every 13 seconds.
```
contract Sender {   
	signal Update(uint info);

	function sendDelayedUpdate(uint info) public {
	    emit Update(info).delay(1000);
	}
}
```
A common useful example would be to create a contract that constantly updates its own state periodically.
```
contract Heartbeat {
	uint public count;
	signal Beep();

	slot countBeeps() {
        count = count + 1;
        emit Beep().delay(1000);
    }

	constructor() public {
		count = 0;
        countBeeps.bind(Beep);
		emit Beep().delay(1000);
	}
}
```

## 3. Blockchain Support
This section will cover the additional components added to the blockchain state to implement signals/slots as well as how the blockchain state changes to reflect the emission of a signal or execution of a slot. This section relies heavily on the content from the Ethereum Yellow Paper. A more formal description will be presented in a seperate document.

#### EVM Opcodes
Blockchains can be considered to be a large distributed state machine that transitions states through the execution of transactions. A big part of a transaction is the execution of a smart contract from start to finish on the Ethereum Virtual Machine (EVM). Ethereum smart contracts are mostly written in a domain specific language called Solidity, and are compiled down to EVM bytecode. The EVM opcodes are the cause for the majority of state transitions on the blockchain. Current EVM opcodes as well as their state transitions can be found in the Ethereum Yellow Paper. To implement signals/slots, we introduce three new EVM opcodes, BINDSIG and EMITSIG. We will describe what their state transition represents after describing the new pieces of the blockchain state.

#### Signals
For various reasons that will be apparent later, we need every signal on the network to have a unique identifier. We can get strong guarentees for a unique 32 byte identifier by using the `KEC()` hash function along with the contract address. For example, `sigID = KEC(contractAddr + offset)` should be sufficient to generate a unique identifier. If we have multiple signals in the same contract, we can adjust `offset` to produce multiple unique identifiers. This generation of unique identifiers should be done during contract creation.

#### Slots
Unlike signals, slots don't need an identifier. They exist as a pointer to the block of code that gets executed upon the emission of the signal that the slot binded to during contract creation. The signal that a slot binds to can be in any contract, including the same contract that contains the slot. The mechanism behind this binding is handled by the world state of the blockchain and will be explained next. When binding a slot to a signal, the exact location and identifier of the signal must be given. This includes the address of the contract that the signal resides in as well as the identifier discussed earlier. If an invalid contract address or signal identifier is used in the constructor, the handler code will never be executed. 

#### World State
To implement signals/slots, the system needs to keep a mapping between signals and their corresponding slots. We can accomplish this by adding to the world state. Recall that the world state in Ethereum is a large Patricia Merkle Tree (trie) that performs the mapping `KEC(A) -> RLP((A.nonce, A.balance, A.storageRoot, A.codeHash))` where `A` is an account. We add another field `A.signalMap`. This will be a trie that performs the mapping `KEC(S) -> RLP(slot, L)` where `S` is a signal identifier and `L` is a list of addresses belonging to the contracts that are listening to signal `S`. The slot referred to in this trie is `A`'s response to signal `S`. If `A` does not have a slot binded to `S`, then the slot will be `NULL`. So in summary, each account will now have a trie that helps to map signal identifiers to a its own slot (can be `NULL`) and potentially several listener contract addresses. 
To guarentee that slots are executed prior to any other pending transactions in this account, a counter called `A.activeSlots` is maintained. This counter is incremented whenever a slot transaction is queued up and decremented when a slot transaction gets executed and mined. This way, when miners are selecting which transactions to include in a block, only transactions belonging to accounts with `activeSlots` equal to 0 are valid. 

#### Block Header
Now that we have a proper mapping between signals and slots/listeners, we need a way to queue up slots to be executed upon the emission of signals. We also need a way to verify that slots are executed properly and none are dropped. We do this by spontaneously creating a special slot transaction that can be picked up by miners to be mined and included in the next block. We store this in a trie that performs the mapping `KEC(blockNum) -> RLP(FIFOQUEUE(RLP(contractAddr, sigId, params)))`. This trie is represented by its root hash and will be referred to by `slotsRoot`. On top of the trie, we also keep a counter `currentSigBlock` that keeps track of the current blocknum of signals that we are executing. Note that this counter can only be incremented once the fifo queue associated with the block number has been exhausted. Additionally, `currentSigBlock` must be less than or equal to the current block number that is being mined. This ensures that no slot transactions are dropped and that an execution order for slot transactions is enforced. Because this trie is a part of the block header, miners can easily verify the correctness of the queued up slot transactions by using the root hash of the trie. Whenever miners want to include slot transactions in their block, they need to just pop an element off the fifo queue mapped to by `KEC(currentSigBlock)`.

#### State Transitions
In this subsection we will discuss how the new EVM opcodes BINDSIG and EMITSIG impact the world state and block header as well as what happens when slots are picked up and mined.
##### BINDSIG
This opcode takes the contract takes a contract address, signal identifier, and a slot (pointer to code) as arguments. BINDSIG can be called anywhere. Recall that a slot can bind to multiple signals but this operation cannot be undone. Let `A` be the account executing BINDSIG, `B` be the contract address passed as the argument, `SIG` be the signal identifier, and `SLT` be the slot. The first part of the execution involves updating the mapping so that `A.signalMap[SIG] -> RLP(SLT, NULL)`. At this time, the listener list should be `NULL`. Next, we form update the mapping on `B.signalMap` so that `B.signalMap[SIG] -> RLP(DC, L')` where `DC` is "don't care" and `L'` is the new list of listener contract addresses formed by appending `A` to the previous `L`. Note that having `A` be the same as `B` is valid,
##### EMITSIG
This opcode takes the signal identifier, block delay parameter, and pointer to the list of signal parameters as arguments. The block delay parameter must be greater than or equal to 0. EMITSIG can be called anywhere, including the contract constructor. Let `A` be the account that is executing EMITSIG. The system will use `A.signalMAP` to find the list of listener addresses. Let `Li` be i'th listener in the list. We increment `Li.activeSlots` to reflect that they now have a slot queued up for execution. The next step is to change the block header. Using the current block number and the delay parameter, we calculate the block number at which the slot should be executed. Let this be `B`. We then update the mapping in the queued slot tree so that `KEC(B) -> RLP(FIFOQUEUE(...).push(RLP(Li, SIG, P)))`. In this step, we also copy over the parameters into `P`. 
##### Mining a Slot 
The next step is for miners to pick up these special slot transactions, execute them, and include them in the next block. As mentioned before, a miner picks the slot transaction by popping an item off the queue mapped to by `KEC(currentSigBlock)`. If the queue is empty, increment `currentSigBlock` and try again until a valid slot is returned or that `currentSigBlock` becomes greater than the current block number. Once a slot transaction is returned, the miner can then use the `contractAddr` and `sigID` fields to index into the world state to find the code pointer of where execution of the slot should start. Once executed, the `activeSlots` counter on that contract is decremented. The counter is decremented no matter if the execution passed or failed. Gas is then taken off the account with the slot and paid to the miner. If execution failed due to a shortage of gas, state is reverted and the miner keeps the fees. 

#### Mining Incentives
When talking about state transitions, we left out one important aspect about mining. What is the gas price? To incentivize miners to do the extra work of supporting signals/slots, a fixed ratio multipled by the average gas price of regular transactions in the block will be used. We also ensure that a maximum ratio of slot to regular transactions is enforced. Because the gas price of slot transactions is always greater than the regular transactions, miners will be incentivized to mine these blocks. All execution fees are paid for by the contract which owns the slot.

## 4. Potential Applications
In this section, we examine some useful applications of signals/slots in real world decentralized finance (DeFi) applications. DeFi applications generally all need a method for price updating. Currently this is implemented using periodic update functions that get called by an external account. We also see a lot of need to delayed execution of code as seen in Compound's timelock contract. Both periodic update functions as well as delayed execution of code can be achieved with signals/slots. 

#### MakerDAO
MakerDAO implements a decentralized collateral backed stable currency called Dai. The value of Dai is soft-pegged to 1 USD. In order for MakerDAO to keep the value of Dai soft-pegged to USD, they need periodic updates to the outside prices. This is accomplished through the Median module and the Oracle Security Module (OSM).

![MakerDAO Price Update System](/examples/images/mcd_osm.png)

The Median communicates with outside sources to establish a price. The OSM delays this feed for the rest of the system for added security. Because there is no way for a smart contract to listen to the feed and update the price automatically off-chain users have to 'poke' the contracts in order to update the price. Ideally, contracts such as Median could broadcast an event which OSM or Spot could act on instead of having an external user poke.

The benefits to having this construct goes beyond style and convenience. On March 12-13, due to a huge drop in the crypto market as well as network congestion, many vault owners had their vaults liquidated for very little. There is a chance that with a new feature that allows for on-chain event handling, there would be less 'poking' across the entire Ethereum network and overall less network congestion.

The current implementation relies heavily on the external poke users. Therefore, a possible failure, which has been proved to be a threat to the integrity of the system, is the price is not updated frequently enough. This could arise for a few reasons including tragedy of the commons or miner collusion and could lead to negative outcomes such as inappropriate liquidations, or the  prevention of liquidations that should be possible.
```
// osm.sol: poke is supposed to be called by the poke user every hop (ONE_HOUR by default)
/* next value becomes current if poke is done hop after the prev poke */
function poke() external note stoppable {
	require(pass(), "OSM/not-passed");
	/* wut: price, ok: isValid */
	(bytes32 wut, bool ok) = DSValue(src).peek();
	if (ok) {
		cur = nxt;
		nxt = Feed(uint128(uint(wut)), 1);
		zzz = prev(era());
		emit LogValue(bytes32(uint(cur.val)));
	}
}
```

```
// spot.sol: poke is supposed to be called by the poke user so that value is updated from osm to vat
// --- Update value ---
function poke(bytes32 ilk) external {
	(bytes32 val, bool has) = ilks[ilk].pip.peek();
	// rdiv: divide two Rays and return a new Ray with the correct level of precision.
	// A Ray is a decimal number with 27 digits of precision that is being represented as an integer.
	uint256 spot = has ? rdiv(rdiv(mul(uint(val), 10 ** 9), par), ilks[ilk].mat) : 0;
	vat.file(ilk, "spot", spot);
	emit Poke(ilk, val, spot);
}
```

With the new syntax defined, those two functions can be rewritten as following:
```
// osm.sol: poke is supposed to be called by the poke user every hop (ONE_HOUR by default)
/* next value becomes current if poke is done hop after the prev poke */

signal PriceUpdate(uint price);

function poke() external note stoppable {
	require(pass(), "OSM/not-passed");
	/* wut: price, ok: isValid */
	(bytes32 wut, bool ok) = DSValue(src).peek();
	if (ok) {
		cur = nxt;
		nxt = Feed(uint128(uint(wut)), 1);
		zzz = prev(era());
		emit LogValue(bytes32(uint(cur.val)));
		emit PriceUpdate(bytes32(uint(cur.val)));
	}
}
```

```
// spot.sol: poke is supposed to be called by the poke user so that value is updated from osm to vat
// --- Data ---
struct Ilk {
  PipLike pip;
  uint256 mat;
}

mapping (bytes32 => Ilk) public ilks;

// Declare a slot
slot updatePrice(uint new_val) {
	uint256 spot = has ? rdiv(rdiv(mul(new_price, 10 ** 9), par), ilks[ilk].mat) : 0;
	vat.file(ilk, "spot", spot);
	emit Poke(ilk, val, spot); // just for logging, can be removed
}

constructor(...) public {
    updatePrice.bind(ilks[ilk].pip.PriceUpdate);
}
```

#### Compound
Compound is an implementation of a decentralized money market, where suppliers and borrowers of various decentralized assets can accrue and pay interest. The interest rates are algorithmically derived and are based on the supply and demand for the asset. Similar to MakerDAO, they need a price feed which relies on an Oracle. We can find similar inefficiencies in implementation in Compound. In the compound protocol, the oracle is updated periodically through the setUnderlyingPrice() method. Other contracts who then need the price reading call the getUnderlyingPrice() method. This implies that it would be up to other contracts to keep up to date with the oracle. It could very much be the case that there are redundant calls to the oracle, where we the newest price but the new price feed hasn't come in yet. This also opens up the possibility for other contracts to lag behind the most current price feed. This could be fixed using the new proposed feature. Instead of providing a method for pulling the newest price, we can simply emit a trigger from setUnderlyingprice(). We then have all contracts that are interested in the price feed declare a listener to listen to the trigger and act on it.

In source file SimplePriceOracle.
```
contract SimplePriceOracle is PriceOracle {
	...
    function getUnderlyingPrice(CToken cToken) public view returns (uint) {
        if (compareStrings(cToken.symbol(), "cETH")) {
            return 1e18;
        } else {
            return prices[address(CErc20(address(cToken)).underlying())];
        }
    }
    
    function setUnderlyingPrice(CToken cToken, uint underlyingPriceMantissa) public {
        address asset = address(CErc20(address(cToken)).underlying());
        emit PricePosted(asset, prices[asset], underlyingPriceMantissa, underlyingPriceMantissa);
        prices[asset] = underlyingPriceMantissa;
    }
	...
}
```
The source file Timelock.sol contains a series of time sensitive methods/actions. To make them time sensitive, a minimum and maximum delay between different calls is enforced. This means that the user has to time these calls to comply with the protocol. This could be made easier with the inclusion of triggers. If triggers existed, then a transaction could be executed upon a trigger emitted in queue_transaction. However under this construct, the method of cancelling a transaction would have to be implemented in a different way. Furthermore, the initial purpose of the Timelock contract is to provide a delay buffer for when a proposal is accepted and when it is taken into effect. If we could implement a time delay handler based on the block number, we theoretically wouldn't even need this time locking feature.

In source file Timelock.sol:
```
contract Timelock {
	...
    function queueTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) public returns (bytes32) {
        require(msg.sender == admin, "Timelock::queueTransaction: Call must come from admin.");
        require(eta >= getBlockTimestamp().add(delay), "Timelock::queueTransaction: Estimated execution block must satisfy delay.");
        ..
    }
    ...
    function executeTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) public payable returns (bytes memory) {
        require(msg.sender == admin, "Timelock::executeTransaction: Call must come from admin.");

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], "Timelock::executeTransaction: Transaction hasn't been queued.");
        require(getBlockTimestamp() >= eta, "Timelock::executeTransaction: Transaction hasn't surpassed time lock.");
        require(getBlockTimestamp() <= eta.add(GRACE_PERIOD), "Timelock::executeTransaction: Transaction is stale.");
		...
    }
	...
}
```

#### Augur
Augur is a prediction market on Ethereum. It uses a communal system driven by incentives to resolve the outcome of markets instead of using an oracle.

![Augur disputation workflow](/examples/images/augur_disputation.png)

The process is as following: After a market enters reporting phase, an Initial Reporter (typically the market creator), selects an outcome as the *Tentative Winning Outcome.* A user can *dispute* the Tentative Winning Outcome by staking REP on an alternative outcome. If a *Dispute Bond* is reached on an alternative outcome, the Tentative Winning Outcome changes to the new alternative outcome. Dispute Bond increases for each round of disputation.

The delays in the process are done through an off-chain script [dispute.ts](https://github.com/AugurProject/augur/blob/008eee7c88303a69fff52196a189664aa6e4677e/packages/augur-tools/src/flash/dispute.ts). For the price oracle, similar to MakerDao, the price feed update relies on a "poke" from off-chain components. It is not as beneficial as the other two examples to have the event-driven feature in Augur, as there is a single listener (for calculating the required bond) to the event (price feed). And an up-to-date and accurate price is not as important since the market is handled with the stablecoin Dai.

```
// packages/augur-core/source/contracts/reporting/Universe.sol
function runPeriodicals() external returns (bool) {
    uint256 _blockTimestamp = block.timestamp;
    uint256 _timeSinceLastSweep = _blockTimestamp - lastSweep;
    if (_timeSinceLastSweep > 1 days) {
        sweepInterest();
        return true;
      }
    uint256 _timeSinceLastRepOracleUpdate = _blockTimestamp - repOracle.getLastUpdateTimestamp(address(reputationToken));
    if (_timeSinceLastRepOracleUpdate > 1 days) {
        repOracle.poke(address(reputationToken));
    }
    return true;
}
```

## 5. Implementation on Conflux
This document aims to provide a rough outline for how this feature should be implemented on the conflux chain. Three main components of the Conflux core need to be changed.
1. Execution. Because we need to implement BINDSIG and EMITSIG opcodes, changes to the execution componenent of the core must be made. The particular areas of code that handle execution and change of state are found in the directorys /core/src/vm, /core/src/evm, and /core/src/executive. 
2. State. To maintain the signal-slot mapping trie in each account, we will need to modify /core/src/state, particularily the account_entry. The block state during execution can be found in core/src/vm/env.rs and is set up in /core/src/consensus/consensus_executor.rs. These will have to be changed to implement the global slot transaction trie.
3. Transaction Pool. Slot transactions will have to be added to the transaction pool to be handled by miners. 
4. Validation. High level state changes to executing a slot transaction will have to be implemented. This includes checking the validity of a slot transaction and regular transaction as well as popping the slot transaction queue found in each accound state.


#### Other Notes:
It is interesting to consider that each of the three DeFi applications above deploy their own oracle. It would be feasible with on-chain triggers to have only one trusted Oracle that updates the states of all the DeFi price feeds through emitting a single event.
