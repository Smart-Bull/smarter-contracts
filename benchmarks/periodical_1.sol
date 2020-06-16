pragma solidity ^0.6.9;

// A contract with a function that is run periodically. This is a proof of concept and will not compile.
// Describes an interest update using periodically executed slots.
// This shows a similar idea as the periodical.sol file while simplifying the interface to MakerDAO system as a savingInfo contract.


contract myWallet {

    // a constant that should be set to the daily block rate of the network
    uint DAILYBLOCKRATE;

    // the SavingInfo contract where interest rate is defined, funds generating interests are stored in this contract
    SavingInfo public savingInfo;

    // liquid token balance in the current wallet
    uint256 myBalance;

    // Signal emitted when a transaction needs to be executed
    signal DailySignal();

    // Slot that does the executing
    slot Update() {
        sweepInterest();
        emit DailySignal().delay(DAILYBLOCKRATE);
    }

    constructor(SavingInfo _savingInfo) {
        savingInfo = _savingInfo;

        // bind slot to signal
        Update.bind(DailySignal);

        // Emit a signal for delayed execution of this transaction
        emit DailySignal().delay(DAILYBLOCKRATE);
     }


    function sweepInterest() {
        // gets the address' illiquid token balance
        uint256 iBalance = savingInfo.balance(address(this));
        // Do nothing if we have no DSR savings
        if (balance == 0) {
            return;
        }

        // Calculates the current cumulated interest rate
        uint256 _chi = savingInfo.cumulatedInterestRate();

        // make the new interest earned liquid
        myBalance = myBalance + iBalance.mul(_chi);

        // reset the periodical signal
        emit DailySignal().delay(DAILYBLOCKRATE);
    }


}
