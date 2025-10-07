import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("FavorModule", (m) => {
  // Required inputs
  const owner       = m.getParameter<string>("owner");        
  const treasury    = m.getParameter<string>("treasury");     
  const esteemAddr  = m.getParameter<string>("esteemAddress"); 

  // Favor metadata
  const name        = m.getParameter<string>("name");
  const symbol      = m.getParameter<string>("symbol");
  const initial     = m.getParameter<bigint>("initialSupply");

  const esteem = m.contractAt("Esteem", esteemAddr);

  const favor = m.contract("Favor", [
    owner,
    name,
    symbol,
    initial,
    treasury,
    esteem
  ]);

  m.call(esteem, "addMinter", [favor]);
  m.call(favor, "addMinter", [owner]);
  m.call(favor, "setTaxExempt", [owner, true]); // For initial liquidity add

  return { favor };
});
