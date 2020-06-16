pragma solidity ^0.6.9;

// A contract with a function that is run periodically. This is a proof of concept and will not compile.
// Describes an interest update contract with MakerDAO system using periodically executed slots.
// This is directly inspired by Augur's Universe.sol source file.
// a simpler version of similar idea can be found in periodical_1.sol file.


contract periodicUpdate {
    IAugur public augur;
    ICash public cash;

    // a constant that should be set to the daily block rate of the network
    uint DAILYBLOCKRATE;

    // The DAI Savings Rate contract
    // It allows users to deposit dai and activate the Dai Savings Rate and earning savings on their dai
    IDaiPot public daiPot;

    // The DAI token contract and all of the adapters DaiJoin adapters.
    IDaiJoin public daiJoin;

    // The Maker Protocol's Core Accounting System
    IDaiVat public daiVat;

    uint256 constant public RAY = 10 ** 27;

    // Signal emitted when a transaction needs to be executed
    signal DailySignal();

    // Slot that does the executing
    slot Update() {
        sweepInterest();
        emit DailySignal().delay(DAILYBLOCKRATE);
        return true;
    }

    constructor(IAugur _augur) {
        augur = _augur;
        cash = ICash(augur.lookup("Cash"));
        daiVat = IDaiVat(augur.lookup("DaiVat"));
        daiPot = IDaiPot(augur.lookup("DaiPot"));
        daiJoin = IDaiJoin(augur.lookup("DaiJoin"));
        cash.approve(address(daiJoin), 2 ** 256 - 1);
        assertContractsNotZero();
        daiVat.hope(address(daiPot));
        daiVat.hope(address(daiJoin));
        cash.approve(address(daiJoin), 2 ** 256 - 1);
        daiVat.hope(address(augur));

        // bind slot to signal
        Update.bind(DailySignal);

        // Emit a signal for delayed execution of this transaction
        emit DailySignal().delay(DAILYBLOCKRATE);
     }

     /**
        * @param _initial Bool indicating if the window is an initial dispute window or a standard dispute window
        * @return The dispute window after the current one
        * note: details of this function are abbreviated
        */
       function getOrCreateNextDisputeWindow(bool _initial) public returns (IDisputeWindow)

     function withdrawSDaiFromDSR(uint256 _balance) private returns (bool) {
        // The wad * chi must be present in the vat and owned by the pot
        // and must be less than msg.sender's pie balance
        daiPot.exit(_balance);
        if (daiJoin.live() == 1) {
            daiJoin.exit(address(this), daiVat.dai(address(this)).div(RAY));
        }
        return true;
    }

    function saveDaiInDSR(uint256 _amount) private returns (bool) {
        // uint wad this parameter is based on the amount of dai
        // (since wad = dai/ chi ) that you want to join to the pot.
        // The wad * chi must be present in the vat and owned by the msg.sender
        daiJoin.join(address(this), _amount);
        uint256 _chi = daiPot.drip();

        // sDai may be lower than the full amount joined above.
        // This means the VAT may have some dust and we'll be saving
        // less than intended by a dust amount
        uint256 _sDaiAmount = _amount.mul(RAY) / _chi;
        daiPot.join(_sDaiAmount);
        return true;
    }

    function sweepInterest() public returns (bool) {
        lastSweep = block.timestamp;

        // gets the address' Pot balance
        uint256 _dsrBalance = daiPot.pie(address(this));
        // Do nothing if we have no DSR savings
        if (_dsrBalance == 0) {
            return true;
        }

        uint256 _extraCash = 0;

        // Calculates the most recent chi (cumulated interest rate) and pulls dai from the vow
        uint256 _chi = daiPot.drip();

        // Pull out all funds
        withdrawSDaiFromDSR(_dsrBalance);

        // Put the required funds back in savings
        saveDaiInDSR(totalBalance);

        // Rep token owned by this account
        _extraCash = cash.balanceOf(address(this));

        // The amount in the DSR pot and VAT must cover our totalBalance of Dai
        assert(daiPot.pie(address(this)).mul(_chi).add(daiVat.dai(address(this))) >= totalBalance.mul(RAY));
        require(cash.transfer(address(getOrCreateNextDisputeWindow(false)), _extraCash));
        return true;
    }


}
