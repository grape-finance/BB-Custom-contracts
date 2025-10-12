## MoneyBin

Money bin is a kind of treasury designed to support liquidation operations

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
  - PLSXf ( 0xDDBE64F89268026027d7823d1141846d546d6bAC) - PLSX ( 0x95b303987a60c71504d99aa1b13b4da07b0790ab)
  - pDAIf 0xC8CCAeC1E239C8591cbB8715bd0A43Dd4c9Cc95A / pDAI 0x6b175474e89094c44da98b954eedeac495271d0f
  - EDAIf 0x2070Ea9C18DF743b3fdF37485fcCC390A3694EB9 /  EDAI 0xefd766ccb38eaf1dfd701853bfce31359239f305


Contract implements 2 step ownalble.

### TODO:

### Deployed instance and GUI

Instance: 0xD59400Eae8B3955018b2dA1939F6c1FCFa794849
GUI:  https://scgui.xyz/MoneyBin-EtrYC4g3Gm

## Liquidator contract instance

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
