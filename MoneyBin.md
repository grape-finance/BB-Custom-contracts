## MoneyBin

Money bin is a kind of trasury designed to support liquidation operations

### Deployment and configuration

Deployment params

- owner - owner of the contract  
- router - uniswap router address (0x165C3410fC91EF562C50559f7d2289fEbed552d9)
- factory - uniswap factory address (0x29eA7545DEf87022BAdc76323F373EA1e707C523)

Additional configuration params, to be set after deployment

- receiver - contract address to receive funds.  supposed to be liquidation contract. it will call desgnated methid  to get necessary funds.
- VAL997 - setting for uniswap calculations,   default value matches  9971 used in pulsex router.   Adjust if necessary
- favor / asset mappings
  - PLSf: 0xFf98Af981c113488B91934e8af779194Cc1b53Ad ,  WPLS: 0xa1077a294dde1b09bb078844df40758a5d0f9a27

Contract implements 2 step ownalble.


### Deployed instance and GUI

Instance: 0xD59400Eae8B3955018b2dA1939F6c1FCFa794849
GUI:  https://scgui.xyz/MoneyBin-EtrYC4g3Gm

### Liquidator instance

Instance:  0x780BDF5de6B6948Bb471379B3961A57729f2a52d
GUI: https://www.smartcontractgui.xyz/Liquidator-AxVRrP5kvj

### Checklist
- deployed and GUI created
- PLSf and WPLS mappings added
- register  liqiuodator contract as supply receiver  at MoneyBn
- register MoneyBin as Supplier by Liquidator (during construction)
- register MoneyBin as Treasury by Liquidator (during construction)

To do:
-  set as minter to plsf
-  set as tax exempt to plsf
