## MoneyBin

Money bin is a kind of trasury designed to support liquidation operations

### Deploymen and configuration

Deployment params

- owner - owner of the contract  
- router - uniswap router address (0x165C3410fC91EF562C50559f7d2289fEbed552d9)
- factory - uniswap factory address (0x29eA7545DEf87022BAdc76323F373EA1e707C523)

Additional configuration params, to be set after deployment

- receiver - contract address to receive funds.  supposed to be liquidation contract. it will call desgnated methid  to get necessary funds.
- VAL997 - setting for uniswap calculations,   default value matches  9971 used in pulsex router.   Adjust if necessary
- favor / asset mappings

Contract implements 2 step ownalble.


### Deployed instance and GUI

Instance: 0x36476e1AEd91e7f4FA6ef51386e1bb3E997525Ba
GUI:  https://scgui.xyz/MoneyBin-3tfHq31dQA
