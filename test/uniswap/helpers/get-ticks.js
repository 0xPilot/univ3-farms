const getTicks = async (contract) => {
  const tickLower = await contract.tickLower();
  const tickUpper = await contract.tickUpper();

  return [tickLower, tickUpper];
};

module.exports = {
  getTicks,
};
