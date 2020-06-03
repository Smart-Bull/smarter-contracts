
# Rough Notes on Implementation:
This document aims to provide a rough outline for how this feature should be implemented on the conflux chain. Three main components of the Conflux core need to be changed.
1. Execution. Because we need to implement BINDSIG and EMITSIG opcodes, changes to the execution componenent of the core must be made. The particular areas of code that handle execution and change of state are found in the directorys /core/src/vm, /core/src/evm, and /core/src/executive. 
2. State. To maintain the signal-slot mapping trie in each account, we will need to modify /core/src/state, particularily the account_entry. The block state during execution can be found in core/src/vm/env.rs and is set up in /core/src/consensus/consensus_executor.rs. These will have to be changed to implement the global slot transaction trie.
3. Transaction Pool. Slot transactions will have to be added to the transaction pool to be handled by miners. 
4. Validation. High level state changes to executing a slot transaction will have to be implemented. This includes checking the validity of a slot transaction and regular transaction as well as popping the slot transaction queue found in each accound state.





