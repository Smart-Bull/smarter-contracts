pragma solidity ^0.6.9;

// Delayed price feed benchmark contract. This is a proof of concept and will not compile.
// Describes a price update system using signals and slots.
// Contracts A, and B all automatically update their prices when the
// price oracle receives something on its external feed.
// This is inspired by MakerDAO's osm.sol source file.

// External library for accessing external oracle data
import "ds-value/value.sol";

// Contract acts as a one hour buffer for information from an oracle to reach receivers
contract PriceOracleBuffer {
    // Address of price oracle
    address public src;
    // Number of block generation cycles between price updates
    uint public constant ONE_HOUR = 180; // 3600/20
    // Price feeds
    uint cur;
    uint nxt;

    // Price update signal
    signal public PriceFeedUpdate(uint price);

    // Function that queries the new price and sends an update signal
    slot SendUpdate(uint unused) {
        (bytes32 price, bool valid) = DSValue(src).peek();
        if (valid) {
            cur = nxt;
            nxt = price;
            emit PriceFeedUpdate(cur).delay(ONE_HOUR);
        }
    }

    // Constructor
    constructor(address oracle_addr) public {
        // Bind SendUpdate slot to the signal PriceFeedUpdate. This way the price feed is automatically
        // updated every single hour. Feed is also then relayed to other receivers.
        src = oracle_addr;
        SendUpdate.bind(PriceFeedUpdate);
        emit PriceFeedUpdate(0);
    }
}

// Both contracts RecieverA and RecieverB are listening for the new price
contract ReceiverA {
    // Address of PriceOracle
    PriceOracleBuffer public oracle;
    // Price
    uint price;

    slot RecievePrice(uint new_price) {
        price = new_price;
    }

    constructor(address oracle_addr) {
        oracle = PriceOracleBuffer(oracle_addr);
        RecievePrice.bind(oracle.PriceFeedUpdate());
    }
    
    function detatch() public {
        RecievePrice.detatch(oracle.PriceFeedUpdate());
    }
}

// Identical to contract A. Should recieve the same price update.
contract ReceiverB {
    // Address of PriceOracle
    PriceOracleBuffer public oracle;
    // Price
    uint price;

    slot RecievePrice(uint new_price) {
        price = new_price;
    }

    constructor(address oracle_addr) {
        oracle = PriceOracleBuffer(oracle_addr);
        RecievePrice.bind(oracle.PriceFeedUpdate());
    }
    
    function detatch() public {
        RecievePrice.detatch(oracle.PriceFeedUpdate());
    }
}
