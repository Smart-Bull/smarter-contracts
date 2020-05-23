# Smarter Contracts Through On-Chain Event Handling:

This repository contains the design document for the implementation of on-chain event handling.

1. Introduction
2. Proposed Functionality and Syntax
3. Blockchain Support
4. Applications


## 1. Introduction:

Currently in the world of smart contract development, there is no way for a smart contract to execute its own code without an external agent explicitly calling it. As a result, seemingly simple tasks
such as updating the time of day periodically is not possible without either calling an update function from a seperate account, or subscribing to a service such as the Ethereum Alarm Clock.
In a more general sense, it would be nice if Ehtereum offered a way to allow for event driven programming. Some systems naturally lend themselves to the event driven paradigm. For example, it is the
common case with decentralized finance (DeFi) applications that they need information from oracles. Naturally it would seem natural for all contracts in the system to listen to the oracle,
and update their state when the oracle updates their information. Of course, this isn't possible right now. We will later look at a few DeFi applications and how they deal with this issue.
It involves a lot of periodic pokes/updates from external accounts that we believe are suboptimal both in a ease of development but also network usage.

There are three main pieces of functionality that we want to achieve:
	1. Emit a trigger that other contracts can listen to
	2. Listen to triggers that other contracts emit and handle them
	3. Provide functionality for delayed execution of code

To implement this feature, it will involve adding programming language features to Solidity as well as making slight modifications to the blockchain itself. This along with potential applications
of this feature will be discussed in this document. In order to avoid confusion between what we are trying to implement and the current implementation of events in ethereum, which really only exist
for logging, we will call on-chain events 'triggers'.

In this document, we will discuss what the feature might look like to smart contract developers, the challenges of implementing this on a blockchain, and finally a list of potential applications on
real world DeFi applications such as MakerDAO, Compound, and Augur.


## 2. Proposed Functionality and Syntax:

* To emit a trigger, we declare it in a contract similar to a logging event, then use the emit keyword to broadcast that trigger across the network.
```
contract Sender {
	// Declare a trigger
	trigger Update(uint info);

	function x(uint info) public {
		emit Update(info);
	}
}
```
* To listen to a trigger, we declare a listener and use a ES6 inspired call-back syntax to write an event handler.
```
contract Receiver {
	uint public info;
	Sender public s;

	// Declare a listener
	listener updateHandler;

	// Get ABI of Sender
	constructor(address sender_addr) public {
		s = Sender(sender_addr);
		info = 0;
		// Provide trigger handler
		updateHandler(s.Update, (new_info) => {
			info = new_info;
			// void return
		});
	}
}
```
* To emit a trigger after a time delay, emit with the delay method. The argument is the number of block numbers to delay by. As of writing, ethereum generates around one block every 13 seconds.
```
contract Sender {   
	// Declare a trigger
	trigger Update(uint info);

	function x(uint info) public {
		emit Update(info).delay(1000);
	}
}
```
* A common useful example would be to create an event handler that constantly updates its state periodically. This contact would look like something like this.
```
contract Heartbeat {
	uint public count;
	trigger Beep();
	listener countBeeps;

	constructor() public {
		count = 0;
		emit Beep().delay(1000);
	}

	countBeeps(Beep, () => {
		count = count + 1;
		emit Beep().delay(1000);
	}
}
```

## 3. Blockchain Support:

To bring these features to life, there are numerous challenges to address. These range from incentive mechanisms on the blockchain to introducing new constructs into solidity. In this section
we will look at some of these issues and describe potential solutions. A formal description can be found in FORMALIZED.md.

#### Blockchain State
In order for EVM to know which handlers to invoke at the emission of a trigger, there has to be some mapping between a trigger and its listeners. To this, we will have to treat events similar
to storage state of contracts. Since triggers are encoded into the state, we will need new opcodes in EVM that act on this state.

#### Execution of Listeners
There are two options into how we execute handlers. We can either interrupt the emitter of the trigger and execute the event handler right away, or we have the execution of the event handler be
delayed by creating another transaction on the spot. Because we can't be guarenteed about the size of event handlers, or whether they themselves emit events, we opted for the second option.
Each time a trigger is emitted, EVM will create a new transaction for the event handler and will be put in a transaction pool to be picked out by miners. Another idea we have is to impose a
contract wide lock to ensure that event handlers are executed before other calls to the contract.

#### Incentives
We need to provide incentives to miners to validate the block. Because event handler transactions are generated dynamically, it doesn't have a set gas price. To solve this, we could have the gas
price of the event handler contract be calculated as a fixed ratio (greater than 1) multiplied by the average gas price of the other contracts in the block. This way, miners would be incentivized to pick up
these special transactions. Also, we would need to put a limit on the ratio between the number of event handler trasactions we have and normal transactions. The gas for the execution of event
handlers payed for by the contract with the event handler, not the emitter. We also have to be careful to not overcharge users who want to use this feature properly.

#### Concerns
* One concern is that the EVM state could blow up if we had loops of triggers and listeners. We don't see this as an attack opportunity as the attack would have to pay for the gas of the event handler.
Also emitting events costs more gas than the regular operation so there would be a limit to the number of times someone could emit events.
* Another concern is whether the cost for event emitter is high enough so that they won't flood the system with events that no one listens to. We suggest to introduce cost to the emitter in the form of bonded storage. In other words, emitters need to "lock" some of their tokens for a period of time in order to emit an event.

### Implementation Proposal
This is an informal description of how we propose to implement this feature on an actual blockchain network.

#### Unique triggers
To make sure each trigger is identifiable, we assign it an id derived from the ethereum account address. During the contract construction, each trigger is given an arbitrary number. This number could just
be 1 for the first trigger, 2 for the second and so on. We let the trigger id be `Tid`, arbitrarily assigned trigger number be `Tn`, and `A` be the contract address. Then: `Tid = KEC(A + Tn)`.
This ensures that trigger id's are almost guarenteed to be unique. When an id is assigned it cannot change and will be the way we refer to this trigger in the future.   

#### Account state
When a trigger is emitted, the miners need to know which handlers correspond to that trigger. We accomplish this through a trie that maps any given relevant trigger id to the RLP encoding of the
handling code as well as list of listening addresses. The code for the event handlers on this trie cannot be manipulated once the contract is deployed. However, listening contract addresses can be added
on but only by external contracts. This trie is the basis for how we determine which handlers to use for each trigger. When a miner executes the emit instruction, we use the trigger id to index into the
trie to figure out which contracts are listening to this event. A special handler transaction is then created and put on the block state and signed by the emitter of this trigger. 
Nodes that aren't full can just store the root hash instead of the entire tree. In this transaction, there will be three fields. The listener contract address, the trigger id, and the blocknum.
The blocknum indicates the blocknumber that we wait until before the transaction is valid to be executed.

#### Block state
To ensure that triggers are handled properly by miners, we add an extra field to the block. Similar to the transaction trie, we construct a handler trie consisting of all the handler transactions that 
are queued up to be mined. This trie is populated accordingly when triggers are emitted. Transactions on the trie are removed when miners decide to process those handler transactions. It is to note 
that it is invalid to process a transaction that has a blocknum greater than the current blocknum.  

#### EVM
The manipulations in the account state and block state are facillitated through a few new opcodes found in EVM. One of them will be used to emit triggers while the other will be used to subscribe a 
listener to another event. Furthermore, changes to init will have to be made to construct the account state trie. More detailed consideration of these opcodes are in FORMALIZED.md.

#### Generation of handler transactions
There are two types of handler transactions to create corresponding to each of the trigger types: immediate trigger and delayed trigger. Immediate trigger requires the call to handler added to the transaction pool immediately after an event is seen. On the other hand, call to handler for a delayed trigger is added after the specified block time expires.

Currently there are three ways to add transactions to the transaction pool of a node in the network. They all make calls to TransactionPool.insert_new_transactions:
1. core/src/sync/message/transactions.rs: transactions received from the network are added to the pool
2. core/src/light_protocol/provider: transactions generated by a light client
3. client/src/rpc/impls/cfx.rs: transactions generated by a full node

One way to generate the handler transactions is to have the clients to make a call to the handler when the corresponding trigger is seen (though 2 and 3). However, this would lead to redundant transactions being created by multiple clients. Another way is to populate the transaction while validating the trigger transaction inside the transaction pool. This requires addition of parameters to the configuration of transaction pool. At a glance, here is a few modifications required to core/src/transaction_pool/mod.rs:
1. pub struct TransactionPool
	- TransactionPoolInner
	- VerificationConfig
	- TxPoolConfig: required ratio between normal transactions and handler transactions, gas price for handler transactions
2. insert_new_transactions
	- where the lookup for handler happens
	- generate transaction for handler calls here on behalf of the handler contract (also need to memorize a transaction for delayed handler) [Unanswered question: is it feasible to create a handler contract transaction in the transaction pool?]


## 4. Applications:

#### MakerDAO
MakerDAO implements a decentralized collateral backed stable currency called Dai. The value of Dai is soft-pegged to 1 USD. In order for MakerDAO to keep the value of Dai soft-pegged to USD,
they need periodic updates to the outside prices. This is accomplished through the Median module and the Oracle Security Module (OSM).

![MakerDAO Price Update System](/images/mcd_osm.png)

The Median communicates with outside sources to establish a price. The OSM delays this feed for the rest of the system for added security. Because there is no way
for a smart contract to listen to the feed and update the price automatically, off-chain users have to 'poke' the contracts in order to update the price. Ideally, contracts such as Median
could broadcast an event which OSM or Spot could act on instead of having an external user poke.

The benefits to having this construct goes beyond style and convenience. On March 12-13, due to a huge drop in the crypto market as well as network congestion, many vault owners had their
vaults liquidated for very little. There is a chance that with a new feature that allows for on-chain event handling, there would be less 'poking' across the entire Ethereum network and
overall less network congestion.

The current implementation relies heavily on the external poke users. Therefore, a possible failure, which has been proved to be a threat to the integrity of the system, is the price
is not updated frequently enough. This could arise for a few reasons including tragedy of the commons or miner collusion and could lead to negative outcomes such as inappropriate liquidations,
or the  prevention of liquidations that should be possible.
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

trigger PriceUpdate(uint price);

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
// Declare a listener
listener updatePrice;

// --- Registering osm ---
function file(bytes32 ilk, bytes32 what, address osm_) external note auth {
	require(live == 1, "Spotter/not-live");
	if (what == "pip") {
		ilks[ilk].pip = OSM(osm_);

		// instantiate a listener for each crypto price update
		updatePrice(ilks[ilk].pip.PriceUpdate, (new_price) => {
			uint256 spot = has ? rdiv(rdiv(mul(new_price, 10 ** 9), par), ilks[ilk].mat) : 0;
			vat.file(ilk, "spot", spot);
			emit Poke(ilk, val, spot); // just for logging, can be removed
		});
		listen updatePrice;
		price_listeners[ilk] = updatePrice;
	}
	else revert("Spotter/file-unrecognized-param");
}
```

#### Compound
Compound is an implementation of a decentralized money market, where suppliers and borrowers of
various decentralized assets can accrue and pay interest. The interest rates are algorithmically
derived and are based on the supply and demand for the asset. Similar to MakerDAO, they need a price
feed which relies on an Oracle. We can find similar inefficiencies in implementation in Compound.

In the compound protocol, the oracle is updated periodically through the setUnderlyingPrice() method. Other contracts
who then need the price reading call the getUnderlyingPrice() method. This implies that it would be up to other contracts
to keep up to date with the oracle. It could very much be the case that there are redundant calls to the oracle, where we
the newest price but the new price feed hasn't come in yet. This also opens up the possibility for other contracts to lag
behind the most current price feed. This could be fixed using the new proposed feature. Instead of providing a
method for pulling the newest price, we can simply emit a trigger from setUnderlyingprice(). We then have all contracts
that are interested in the price feed declare a listener to listen to the trigger and act on it.

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

This source file contains a series of time sensitive methods/actions. To make them time sensitive, a minimum and maximum
delay between different calls is enforced. This means that the user has to time these calls to comply with the protocol.
This could be made easier with the inclusion of triggers. If triggers existed, then a transaction could be executed upon
a trigger emitted in queue_transaction. However under this construct, the method of cancelling a transaction would have
to be implemented in a different way.
Furthermore, the initial purpose of the Timelock contract is to provide a delay buffer for when a proposal is accepted
and when it is taken into effect. If we could implement a time delay handler based on the block number, we theoretically
wouldn't even need this time locking feature.

In source file Timelock.sol:
```
contract Timelock {
	...

    function queueTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) public returns (bytes32) {
        require(msg.sender == admin, "Timelock::queueTransaction: Call must come from admin.");
        require(eta >= getBlockTimestamp().add(delay), "Timelock::queueTransaction: Estimated execution block must satisfy delay.");

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(txHash, target, value, signature, data, eta);
        return txHash;
    }

    function cancelTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) public {
        require(msg.sender == admin, "Timelock::cancelTransaction: Call must come from admin.");

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(txHash, target, value, signature, data, eta);
    }

    function executeTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) public payable returns (bytes memory) {
        require(msg.sender == admin, "Timelock::executeTransaction: Call must come from admin.");

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], "Timelock::executeTransaction: Transaction hasn't been queued.");
        require(getBlockTimestamp() >= eta, "Timelock::executeTransaction: Transaction hasn't surpassed time lock.");
        require(getBlockTimestamp() <= eta.add(GRACE_PERIOD), "Timelock::executeTransaction: Transaction is stale.");

		...

        emit ExecuteTransaction(txHash, target, value, signature, data, eta);

        return returnData;
    }

	...
}
```

#### Augur
Augur is a prediction market on Ethereum. It uses a communal system driven by incentives to resolve the outcome of markets instead of using an oracle.

![Augur disputation workflow](/images/augur_disputation.png)

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

#### Other Notes:
It is interesting to consider that each of the three DeFi applications above deploy their own oracle. It would be feasible
with on-chain triggers to have only one trusted Oracle that updates the states of all the DeFi price feeds through emitting
a single event.

## References:



