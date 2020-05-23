
# Formal Implementation Proposal
 
This document aims to extend the Ethereum Yellow Paper to include the states and state transitions that will make signal/event driven programming on a blockchain possible. This document will cover 
the main components that need to be added to the state as well as how they work together to implement the basic functionality of signals and handlers. We will cover the following:

1. Signals and Handlers
2. World State
3. Block Header
4. Emitting a Signal
5. Signal Handler Transactions
6. Executing handler code
7. EVM Opcodes
8. Problems and Considerations


## 1. Signals and Handlers
A signal is uniquely represented by a public 32 byte unsigned integer. This unique identifier is generated from the contract address via the Keccak-256 hash function (denoted as KEC()). 
We generate it using the followingprocedure. Let `Sigs` be the collection of signals that need to be initialized, `a` be the account address, and `n` be a natural number. 
```  
n = 1
for s in Sigs {
	s = KEC(a + n)
	n++
}
```
A signal can also send parameters that handlers take as arguments into their code. The number of parameters and their types must be known before the contract is deployed and like the identifier,
cannot change afterwards. A signal can be emitted with or without a delay through the delay method. For example, if the miner executes `emit UpdateSig(data).delay(5)` when `blocknum=1000`, then
the handlers listening to this signal be will executed when `blocknum >= 1005`.

Handlers are defined as a block of code that gets executed upon the emission of the signal of interest. The signal of interest can come from any contract including the contract hosting the handler.
This block of code takes the signal parameters as inputs and returns void. Similar to normal EVM code, this code is immutable and cannot be changed once the contract has been deployed.
Using unique signal identifiers, handlers are binded to a specific signal at the creation of the contract and as a result, the signal to listen to must be known before the contract is deployed. 
A signal is specified by its host contract address as well as the unique identifier that was generated through the KEC hash function. Both need to be supplied to successfully create a handler. 
If an invalid contract address or signal identifier is used in the creation of the handler, the handler code will never be executed.


## 2. World State 
Let `S` be the world state and `a` be an account address. In the Ethereum Yellow Paper, the world state is formally defined as a trie that maps `KEC(a)` to 
`RLP((S[a].nonce, S[a].balance, S[a].storageRoot, S[a].codeHash))`. We simplify notation by defining `S[a] = RLP((S[a].nonce, S[a].balance, S[a].storageRoot, S[a].codeHash))`.
To support signals and handlers, we introduce a new field to the world state, `S[a].signalMap`. This new field will define the mapping between signals and their corresponding handlers. 

Let `sid` be a signal identifier, `codePtr` be a pointer to the handler code, and `L` be an array of contract addresses that are listening to this particular event. 
We define `S[a].signalMap` to map `KEC(sid)` to `RLP((codePtr, L))`. We simplify notation by defining `S[a].signalMap[sid] = RLP((codePtr, L))`. Since this data structure is trie, only full nodes
need to keep the full tree. Other nodes can simply keep the root hash of this tree. If an account is not a contract account or has no signals or handlers, the tree is empty and `S[a].signalMap = KEC(())`. 
The `signalMap` trie is created during contract creation and is an append only data structure with the exception of the `SELFDESTRUCT` EVM opcode. Once the trie is created, the only change permissable
to this data structure is the appending of addresses to `L`. The `codePtr` field cannot be changed. This means that the handler code that is executed when a certain signal is emitted cannot be changed.
The `L` field is manipulated using a specific opcode that is used in the creation of a handler. For example, let `A` be an existing contract on the network that emits a signal with a 32 byte identifier 
`0xf3a5cf2ce244be0a2253a78dbda39eb3344bfd2f5b38d764e8bfe353b9a4194`. Also, let `A` have a handler which exists at address `A.handlerAddr` that listens to its own signal. Let `B` be a new contract with a 
handler that listens to the same signal from `A` but with seperate handler code existing at `B.handlerAddr`. Before `B` is created, the state of `A` is the following:

`S[A].signalMap[0xf3a5cf2ce244be0a2253a78dbda39eb3344bfd2f5b38d764e8bfe353b9a4194] = RLP((A.handleAddr, A))` 

Then, after the deployment of contract B, the states will look as follows:
```
S[A].signalMap[0xf3a5cf2ce244be0a2253a78dbda39eb3344bfd2f5b38d764e8bfe353b9a4194] = RLP((A.handleAddr, A, B))
S[B].signalMap[0xf3a5cf2ce244be0a2253a78dbda39eb3344bfd2f5b38d764e8bfe353b9a4194] = RLP((B.handleAddr, NULL))
```  
Sections 4 and 5 will discuss how these tries will be used to bring forth the functionality of signal emission and handlng. 
The specific opcodes that will make this possible along with their gas prices will be discussed in section 7.


## 3. Block Header
Our proposed implementation for the execution of signal handlers involves spontaneously creating a special handler transaction that can picked up by miners and which have a dynamically determined 
gas price and an unlimited gas limit. To ensure that emitted signals are handled properly and can be verified amongst groups of miners, we introduce a new field to the block header that keeps track of
which handler transactions currently exist and need to be executed by the miners. This will be implemented as a trie that maps `KEC(blocknum)` to `RLP(T)` where `blocknum` is block number at which
the handler transaction should be executed and `T` is a collection of handler transactions that should be executed at a block number greater than or equal to `blocknum`. The handler transaction 
can be described as the following tuple: `T[0] = (contractAddress, sig)`. This will be discussed in depth in section 5. Similar to the transaction tree, we just need to compare the root hash to 
verify that the state of the trie is the way it should be.

Note: To implement contract wide locks, we can add a seperate counter to the world state to keep track of the number signal handlers that haven't been executed yet.
To optimize this, we can also include a way to keep track of when all handlers before a certain blocknum are handled. This way we can cut down on the amount of searching we have to do through the trie
while ensuring that all handlers are eventually executed and mined.

This trie can go through 2 possible state changes. The first is that a signal is emitted and handler transactions are added accordingly. The second occurs when the handler transactions are mined and
are taken off the trie. We show both transitions with examples. Let the trie be defined as `H.h`. 
For the furst case, suppose contract `A` emits a signal that contract `B` is listening to. Let this signal have identifier `sig`. Suppose also that the signal is emitted at `blocknum=1000` with 
`delay=5`. The resulting state after the emission of the signal will be `H.h[1005] = RLP(Told + (B, sig))`. 




## 

