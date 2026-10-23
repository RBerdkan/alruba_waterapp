class Payment {
  final String id;
  final String saleId;
  final double amount;
  final DateTime paymentDate;
  final String? note;

  Payment({
    required this.id,
    required this.saleId,
    required this.amount,
    required this.paymentDate,
    this.note,
  });

  factory Payment.fromMap(Map<String, dynamic> map) => Payment(
        id: map['id'] as String,
        saleId: map['sale_id'] as String,
        amount: (map['amount'] as num).toDouble(),
        paymentDate: DateTime.parse(map['payment_date'] as String),
        note: map['note'] as String?,
      );
}
