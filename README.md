# Smarter Contracts Through On-Chain Event Handling:

This repository contains the design document for the implementation of
on-chain event handling. This document will go over:

1. Motivation
2. Proposed Syntax
3. Applications
4. Blockchain Support
5. Other Considerations


## 1. Motivation:

Currently smart contracts, although very versatile, are not very smart. There is
no way for a smart contract to execute its own code without an external agent explicitly
calling the function. As a result, the seemingly simple task of updating the time of day
autonomously is not possible in the current smart contract programming paradigm. For example,
say you have a contract that needs to update interest rates once a month. Currently there
are two options. You either poke the contract with an external account yourself, or you get
someone else such as the Ethereum Alarm Clock to do it. Either way, shouldn't doing something
like this be a little more automated? In an event driven programming paradigm, you could just
listen to another contract that emits events signifying the passing of time, and update the
interest rate accordingly.  

From now on in order to avoid confusion between the idea of on-chain events and the current
implementation of events in ethereum, which really only exist for logging, we will call
on-chain events 'triggers'. To explore the potential benefit of triggers, we will
examine how it could be used to revise large DeFi applications such as MakerDAO and Compound
to be more efficient. First we will provide a rough outline of what the syntax might look like.


## 2. Proposed Syntax:

What we proposed is very similar to current event driven programming languages such as JavaScript.
Event is an reserved keyword in solidity, whose arguments are logged on the ledger so that anyone can listen to.
To avoid confusion, we use trigger as the alternative keyword. A trigger carries
some information that should be delivered to the listener. A trigger is by default
public and therefore accessible from outside of the contract. The listener then
handles the trigger through a handler. The trigger handler must have void return.

* Use 'trigger' keyword to define a trigger
* Instantiate a 'Listener' contract to define a listener

~~~~
contract Listener {
  trigger listen_to;
  func fall_back;
  constructor(trigger _trigger, func _fall_back) public {
		listen_to = _trigger;
		fall_back = _fall_back;
	}

  // handle fall back...
}
~~~~

~~~~
contract Sender {
	// Declare a trigger
	trigger Update(uint info);

	function x(uint info) public {
		emit Update(info);
	}
}

contract Receiver {
	uint public info;
	Sender public s;

	// get ABI of Sender
	constructor(address sender_addr) public {
		s = Sender(sender_addr);
		info = 0;
	}

	// Declare a listener
	listen Listener(s.Update, (new_info) => {
		info = new_info;

		// do other stuff...
	});

}
~~~~


## 3. Applications:

##### MakerDAO
MakerDAO implements a decentralized collateral backed stable currency called Dai. The value of
Dai is soft-pegged to 1 USD. In order for MakerDAO to keep the value of Dai soft-pegged to USD,
they need periodic updates to the outside prices. This is accomplished through the Median
module and the Oracle Security Module (OSM).

![MakerDAO Price Update System](/images/MCD_System_2.0.png)

The Median communicates with outside sources to establish a price.
The OSM delays this feed for the rest of the system for added security. Because there is no way
for a smart contract to listen to the feed and update the price automatically, off-chain users
have to 'poke' the contracts in order to update the price. Ideally, contracts such as Median
could broadcast an event which OSM or Spot could act on instead of having an external user poke.

The benefits to having this construct goes beyond style and convenience. On March 12-13, due to
a huge drop in the crypto market as well as network congestion, many vault owners had their
vaults liquidated for very little. There is a chance that with a new feature that allows for
on-chain event handling, there would be less 'poking' across the entire Ethereum network and
overall less network congestion.

The current implementation relies heavily on the external poke users. Therefore, a possible failure,
which has been proved to be a threat to the integrity of the system, is the price is not updated frequently enough.
This could arise for a few reasons including tragedy of the commons or miner collusion
and could lead to negative outcomes such as inappropriate liquidations, or the
 prevention of liquidations that should be possible.
~~~~
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
~~~~

~~~~
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
~~~~

With the new syntax defined, those two functions can be rewritten as following:
~~~~
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
~~~~

~~~~
// spot.sol: poke is supposed to be called by the poke user so that value is updated from osm to vat
// --- Data ---
struct Ilk {
  PipLike pip;
  uint256 mat;
}

mapping (bytes32 => Ilk) public ilks;
mapping (bytes32 => listener) public price_listeners;

// --- Registering osm ---
function file(bytes32 ilk, bytes32 what, address osm_) external note auth {
	require(live == 1, "Spotter/not-live");
	if (what == "pip") {
		ilks[ilk].pip = OSM(osm_);

		// populate listener list
    Listener updatePrice =
    Listener(ilks[ilk].pip.PriceUpdate, (new_price) => {
			uint256 spot = has ? rdiv(rdiv(mul(new_price, 10 ** 9), par), ilks[ilk].mat) : 0;
			vat.file(ilk, "spot", spot);
			emit Poke(ilk, val, spot); // just for logging, can be removed
		});
    listen updatePrice;
		price_listeners[ilk] = updatePrice;
	}
	else revert("Spotter/file-unrecognized-param");
}
~~~~

##### Compound
Compound is an implementation of a decentralized money market, where suppliers and borrowers of
various decentralized assets can accrue and pay interest. The interest rates are algorithmically
derived and are based on the supply and demand for the asset. Similar to MakerDAO, they need a price
feed which relies on an Oracle. We can find similar inefficiencies in implementation in Compound.

In source file SimplePriceOracle.sol:
~~~~
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
~~~~
In the compound protocol, the oracle is updated periodically through the setUnderlyingPrice() method. Other contracts
who then need the price reading call the getUnderlyingPrice() method. This implies that it would be up to other contracts
to keep up to date with the oracle. It could very much be the case that there are redundant calls to the oracle, where we
the newest price but the new price feed hasn't come in yet. This also opens up the possibility for other contracts to lag
behind the most current price feed. This could be fixed using the new proposed feature. Instead of providing a
method for pulling the newest price, we can simply emit a trigger from setUnderlyingprice(). We then have all contracts
that are interested in the price feed declare a listener to listen to the trigger and act on it.

In source file Timelock.sol:
~~~~
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
~~~~
This source file contains a series of time sensitive methods/actions. To make them time sensitive, a minimum and maximum
delay between different calls is enforced. This means that the user has to time these calls to comply with the protocol.
This could be made easier with the inclusion of triggers. If triggers existed, then a transaction could be executed upon
a trigger emitted in queue_transaction. However under this construct, the method of cancelling a transaction would have
to be implemented in a different way.

##### Augur
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
  

## 4: Blockchain Support:
Notes:
* It would be really helpful to implement a timer event based on the block length
* Figure out how the timelock code in compound is used
* When a trigger is emitted, special transactions are created spontaneously. These transactions are the event handlers for each
of the contracts who are listening. There are a two main issues that have to be tackled:
	* How to ensure that event handling seems immediate. We could employ the idea of a contract-wide lock. When an event 
	handler gets executed, the transactions from the same contract currently in queue will be disabled until the event 
	handler finished being executed.
	* How to charge gas. One way to do it is to take the average of the gas prices of the regular transactions in the block
	and multiply by a fixed ratio. This problem ties into how we incentivize miners to take on these transactions.


## 5: Other Considerations:
