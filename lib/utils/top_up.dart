int? calculateRequiredTopUp(int originalAmount, int? targetAmount) {
  if (targetAmount == null) return null;
  if (targetAmount <= originalAmount) return null;
  return targetAmount - originalAmount;
}

bool matchesTopUpPayment({
  required int expectedCustomerNumber,
  required int paymentCustomerNumber,
  required int requiredTopUp,
  required int paymentAmount,
}) {
  return expectedCustomerNumber == paymentCustomerNumber &&
      requiredTopUp == paymentAmount;
}

int combinedTransactionAmount(int originalAmount, int topUpAmount) {
  return originalAmount + topUpAmount;
}
