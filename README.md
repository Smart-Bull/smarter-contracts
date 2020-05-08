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
no way for a smart contract to execute its own code without an external agent
telling it to. Although contracts can call the code of other contracts, the 
initial action stems from a human. Even something as simple as having a contract
store the time and date is not possible. As a result, decentralized finance applications
such as MakerDAO, Compound, and Augur have to employ sub-optimal code. For example, take 
MakerDAO price updating system.

![MakerDAO Price Update System](/images/MCD_System_2.0.png)

In order for MakerDAO to keep the value of Dai soft-pegged to USD, they need periodic updates
to the outside prices. This is accomplished through the Median module and the
Oracle Security Module (OSM). The Median communicates with outside sources to establish a price.
The OSM delays this feed for the rest of the system for added security. Because there is no way
for a smart contract to listen to the feed and update the price automatically, off-chain users
have to 'poke' the contracts in order to update the price. Ideally, contracts such as Median
could broadcast an event which OSM or Spot could act on instead of having an external user poke.

The benefits to having this construct goes beyond style and convinience. On March 12-13, due to
a huge drop in the crpyto market as well as network congestion, many vault owners had their
vaults liquidated for very little. There is a chance that with a new feature that allows for 
on-chain event handling, there would be less 'poking' across the entire ethereum network and 
overall less network congestion. 





