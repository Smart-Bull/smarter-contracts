# Smarter Contracts Through On-Chain Event Handling:

This repository contains the design document for the implementation of
on-chain event handling. This document will go over:

1. Motivation
2. Proposed syntax
3. Applications
4. Blockchain support
5. Other considerations


## 1. Motivation:

Currently smart contracts, although very versitile, are not very smart. There is
no way for a smart contract to execute its own code without an external agent explicitely
calling the function. As a result, the seemingly simple task of updating the time of day
autonomously is not possible in the current smart contract programming paradigm. For example,
say you have a contract that needs to update interest rates once a month. Currently there
are two options. You either poke the contract with an external account yourself, or you get
someone else such as the Ethereum Alarm Clock to do it. Either way, shouldn't doing something
like this be a little more automated? In an event driven programming paradigm, you could just
listen to another contract that emits events signifying the passing of time, and update the
interest rate accordingly.  

From now on in order to avoid confusion between the idea of on-chain events and the current
implmentation of events in ethereum, which really only exist for logging, we will call
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
* use 'listener' keywrod to define a listener

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
	listener incomingUpdate(s.Update, (new_info) => {
		info = new_info;

		// do other stuff...
	});
}

~~~~


## 3. Applications:


###### MakerDAO

![MakerDAO Price Update System](/images/MCD_System_2.0.png)

In order for MakerDAO to keep the value of Dai soft-pegged to USD, they need periodic updates
to the outside prices. This is accomplished through the Median module and the
Oracle Security Module (OSM). The Median communicates with outside sources to establish a price.
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


// --- Registering osm ---
function file(bytes32 ilk, bytes32 what, address osm_) external note auth {
        require(live == 1, "Spotter/not-live");
        if (what == "pip") ilks[ilk].pip = OSM(osm_);
        else revert("Spotter/file-unrecognized-param");
    }

// --- Listener ---
listener updatePrice(s.PriceUpdate, (new_price) => {
  uint256 spot = has ? rdiv(rdiv(mul(new_price, 10 ** 9), par), ilks[ilk].mat) : 0;
  vat.file(ilk, "spot", spot);
  emit Poke(ilk, val, spot); // just for logging, can be removed
});
~~~~

###### Compound
