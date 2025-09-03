## Latest notes
- Pushed latest live version contracts of Favor for pulse tokens with correct oracle interface for calculating bonuses
- Removed unused contracts for current deplyment ie favorEth ETH, favorEth USDT, Liquidity wrapper, old Arb minter
- Updated versions of minteroracle, esteem mint/redeemer for pulse and also uniswap wrapper with hack fix (Needs tests suite)

## TO DO 

- After sell tax to base token is collected need to split tax base token output 80/20 to holding and team wallets respectively with the 80 being deposited into the aave stonghold pools and sent as deposit tokens (uniswapWrapper does this)
- Tests for uniswap wrapper fix to prevent bogus token swap as per hack
- refactor main contracts ie wrapper, zapper, minter, favorEth
- test suite for above main contracts (mint/redeemer/ favorEth, zapper (inc flash hack test), wrapper)
- Adjust zapper _swapAndLog to log buy for esteem bonus only if twap of favorEth token is < 3.00 as similar in buy wrapper as below
        uint256 twap = minterOracle.getTokenTWAP(favorToken);
        if(twap < 3e18){
            IFavorToken(favorToken).logBuy(msg.sender, got);
        }
- Add slippage protection on zapper for liquidity adds/swaps either from estimated getAmountsOut and getOptimalAddLiquidity router views or via user input from the UI


## DONE

- Fix tests for updated favorEth to change from ethLatestPrice to getLatestTokenPrice(token)
- Implement sell tax restrictions:
        - Immediate sell tax, we get the tax not in Favor, but in the paired token. Possible through uniswapWrapper sell all in one go and then split tax after. Or split and sell tax first then sell user portion.
        - Keep free transfer to EAO wallets as current
        - breaking and making LP maintain free. At current add liqudiity is taxed unless through the uniswapWrapper which is fine. Note: removing LP if done through transfer logic as is can be counted as a buy and so this is done through pulsex router or as normal atm
        - (Nicky additional requirement) If possible, no trades outside our ecosystem. (not super important, but would be nice). Possible if we disable transfers to all but tax exempt or to whitelisted CAs and have our uniswap wrapper be the single approved exchanger contract unless tax exempt.