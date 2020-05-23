
# Formal Implementation Proposal
 
This document aims to extend the Ethereum Yellow Paper to include the states and state transitions that will make signal/event driven programming on a blockchain possible. This document will cover 
the main components that need to be added to the state as well as how they work together to implement the basic functionality of signals and handlers. We will cover the following:

1. Signals and Handlers
2. World State
3. Block Fields
4. Emitting a Signal
5. Signal Handler Transactions
6. Executing handler code
7. EVM Opcodes
8. Problems and Considerations


## Signals and Handlers
A signal is uniquely represented by a public 64 byte unsigned integer. This unique identifier is generated from the contract address via the Keccak-256 hash function (denoted as KEC()). 
We generate it using the followingprocedure. Let `Sigs` be the collection of signals that need to be initialized, `a` be the account address, and `n` be a natural number. 
```  
n = 1
for s in Sigs {
	s = KEC(a + n)
	n++
}
```
A signal can also send parameters that handlers take as arguments into their code. The number of parameters and their types must be known before the contract is deployed and like the identifier,
cannot change afterwards. A signal can be emitted with or without a delay through the delay method. For example, if the miner executes `emit UpdateSig(data).delay(5)` when `block_number=1000`, then
the handlers listening to this signal will execute when `block_number >= 1005`.

Handlers are defined as a block of code that gets executed upon the emission of the signal of interest. The signal of interest can come from any contract including the contract hosting the handler.
This block of code takes the signal parameters as inputs and returns void. Similar to normal EVM code, this code is immutable and cannot be changed once the contract has been deployed.
Using unique signal identifiers, handlers are binded to a specific signal at the creation of the contract and as a result, the signal to listen to must be known before the contract is deployed. 
A signal is specified by its host contract address as well as the unique identifier that was generated through the KEC hash function. Both need to be supplied to successfully create a handler. 
If an invalid contract address or signal identifier is used in the creation of the handler, the handler code will never be executed.


## World State 
Let `S` be the world state and `a` be an account address. In the Ethereum Yellow Paper, the world state is formally defined as a trie that maps `KEC(a)` to 
`RLP((S[a].nonce, S[a].balance, S[a].storageRoot, S[a].codeHash))`. We simplify notation by defining `S[a] = RLP((S[a].nonce, S[a].balance, S[a].storageRoot, S[a].codeHash))`.
To support signals and handlers, we introduce a new field to the world state, `S[a].signalMap`. This new field will define the mapping between signals and their corresponding handlers. 

Let `sid` be a signal identifier, `handlerCodeHas` be the hash of the code attributed to the handler, and `L` be an array of contract addresses that are listening to this particular event. 
We define `S[a].signalMap` to map `KEC(sid)` to `RLP((handlerCodeHash, L))`. 

  




